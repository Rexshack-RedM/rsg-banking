-----------------------------------------------------------------------
-- Business accounts: one shared account per job / gang per branch
--  * stored in rsg_bank_accounts with the org key as the owner id: 'job:<name>' / 'gang:<name>'
--    (so exports like GetBranchBalance / AddBranchMoney work with those keys too)
--  * the boss opens it and manages who may withdraw (rsg_bank_business_members)
--  * anyone currently holding the job / gang may deposit cash
--  * access is checked against the player's CURRENT job / gang, so firing someone revokes it
-----------------------------------------------------------------------
local RSGCore = exports['rsg-core']:GetCoreObject()
local BC = Config.Business or {}

local function validCid(cid)
    return type(cid) == 'string' and #cid > 0 and #cid <= 50 and cid:match('^[%w_%-]+$') ~= nil
end

-- { ['job:sheriff'] = { key, kind, name, label, isBoss } } for the player's current job and gang
local function orgsOf(Player)
    local out = {}
    local function add(kind, data, allowed)
        if not allowed or type(data) ~= 'table' or type(data.name) ~= 'string' then return end
        if (BC.excluded or {})[data.name] then return end
        local key = kind .. ':' .. data.name
        out[key] = { key = key, kind = kind, name = data.name, label = data.label or data.name, isBoss = data.isboss == true }
    end
    add('job', Player.PlayerData.job, BC.allowJobs ~= false)
    add('gang', Player.PlayerData.gang, BC.allowGangs ~= false)
    return out
end

local function members(orgKey)
    return MySQL.query.await('SELECT citizenid, name FROM rsg_bank_business_members WHERE org = ? ORDER BY name', { orgKey }) or {}
end

local function isMember(orgKey, cid)
    return MySQL.scalar.await('SELECT 1 FROM rsg_bank_business_members WHERE org = ? AND citizenid = ?', { orgKey, cid }) ~= nil
end

local function canWithdraw(org, cid) return org.isBoss or isMember(org.key, cid) end

-- data for the NUI
function BuildBusinessData(Player, bankId)
    if not BC.enabled then return nil end
    local cid = Player.PlayerData.citizenid
    local list = {}
    for key, org in pairs(orgsOf(Player)) do
        local bal = Bank.getBalance(key, bankId)
        local entry = {
            key = key, kind = org.kind, label = org.label, isBoss = org.isBoss, hasAccount = bal ~= nil, balance = bal or 0,
            canOpen = org.isBoss or BC.bossOnlyOpen == false,
        }
        if bal ~= nil then
            entry.canWithdraw = canWithdraw(org, cid)
            if org.isBoss then entry.members = members(key) end
        end
        list[#list + 1] = entry
    end
    table.sort(list, function(a, b) return a.key < b.key end)
    return { openFee = BC.openFee or 0, limit = BC.memberLimit or 0, maxMembers = BC.maxMembers or 0, orgs = list }
end

local function playerName(Player)
    local ci = Player.PlayerData.charinfo or {}
    return ('%s %s'):format(ci.firstname or '', ci.lastname or ''):match('^%s*(.-)%s*$')
end

-- registers a callback that resolves the player's org from the key the client sent
local function orgAction(name, handler)
    Bank.register('rsg-banking:server:' .. name, function(src, bankId, orgKey, a)
        return Bank.guarded(src, bankId, function(Player, cid)
            if not BC.enabled or type(orgKey) ~= 'string' then return end
            local org = orgsOf(Player)[orgKey]
            if not org then return Bank.notify(src, 'sv_biz_no_org', 'error') end
            handler(src, Player, cid, bankId, org, a)
        end)
    end)
end

local function log(src, action, bankId, org, extra)
    local f = {
        { name = 'Action', value = action, inline = true },
        { name = 'Account', value = org.label .. ' (' .. org.key .. ')', inline = true },
        { name = 'Branch', value = Config.Banks[bankId].label, inline = true },
    }
    for _, x in ipairs(extra or {}) do f[#f + 1] = x end
    BankLog('business', src, f)
end

-- large movement: telegram everyone allowed to withdraw (the person who did it gets their own receipt via BankLogLarge)
local function alertMembers(kind, bankId, org, amount, actorCid)
    local TC = Config.Telegram or {}
    if not TC.alertLarge or amount < (TC.largeAmount or math.huge) or not TelegramAvailable() then return end
    local where = Config.Banks[bankId].label .. ' · ' .. org.label
    local kindText = locale(kind == 'Business deposit' and 'tg_kind_biz_deposit' or 'tg_kind_biz_withdraw')
    for _, m in ipairs(members(org.key)) do
        if m.citizenid ~= actorCid then
            TelegramSend(m.citizenid, locale('tg_large_subject', kindText), locale('tg_large_body', kindText, BankMoney(amount), where))
        end
    end
end

orgAction('bizOpen', function(src, Player, cid, bankId, org)
    if not (org.isBoss or BC.bossOnlyOpen == false) then return Bank.notify(src, 'sv_biz_not_boss', 'error') end
    if Bank.hasAccount(org.key, bankId) then return Bank.notify(src, 'sv_biz_exists', 'error') end
    local fee = math.max(0, tonumber(BC.openFee) or 0)
    if fee > 0 and not Player.Functions.RemoveMoney('cash', fee, 'bank-business-open-' .. bankId) then
        return Bank.notify(src, 'sv_biz_cant_afford_open', 'error', Bank.money(fee))
    end
    local id = MySQL.insert.await('INSERT IGNORE INTO rsg_bank_accounts (citizenid, bank, balance) VALUES (?, ?, 0)', { org.key, bankId })
    if not id or id == 0 then
        if fee > 0 then Player.Functions.AddMoney('cash', fee, 'bank-business-open-refund') end
        return Bank.notify(src, 'sv_biz_exists', 'error')
    end
    Bank.logTx(org.key, bankId, 'opened', fee, playerName(Player))
    Bank.notify(src, 'sv_biz_opened', 'success', org.label, Config.Banks[bankId].label)
    log(src, 'Account opened', bankId, org, { { name = 'Fee', value = BankMoney(fee), inline = true } })
end)

orgAction('bizDeposit', function(src, Player, cid, bankId, org, amount)
    if not Bank.hasAccount(org.key, bankId) then return Bank.notify(src, 'sv_biz_no_account', 'error') end
    amount = Bank.validAmount(src, amount); if not amount then return end
    if not Player.Functions.RemoveMoney('cash', amount, 'bank-business-deposit-' .. bankId) then
        return Bank.notify(src, 'sv_not_enough_cash', 'error')
    end
    if not Bank.credit(org.key, bankId, amount) then
        Player.Functions.AddMoney('cash', amount, 'bank-business-deposit-refund')
        return Bank.notify(src, 'sv_biz_no_account', 'error')
    end
    Bank.logTx(org.key, bankId, 'deposit', amount, playerName(Player))
    Bank.notify(src, 'sv_biz_deposited', 'success', Bank.money(amount), org.label)
    log(src, 'Deposit', bankId, org, { { name = 'Amount', value = BankMoney(amount), inline = true } })
    BankLogLarge('Business deposit', src, Config.Banks[bankId].label .. ' · ' .. org.label, amount)
    alertMembers('Business deposit', bankId, org, amount, cid)
end)

orgAction('bizWithdraw', function(src, Player, cid, bankId, org, amount)
    if not Bank.hasAccount(org.key, bankId) then return Bank.notify(src, 'sv_biz_no_account', 'error') end
    if not canWithdraw(org, cid) then
        BankLogBlocked(src, 'Business withdrawal without authorisation', bankId)
        return Bank.notify(src, 'sv_biz_not_authorised', 'error')
    end
    amount = Bank.validAmount(src, amount); if not amount then return end
    local limit = tonumber(BC.memberLimit) or 0
    if not org.isBoss and limit > 0 and amount > limit then return Bank.notify(src, 'sv_biz_limit', 'error', Bank.money(limit)) end
    if not Bank.debit(org.key, bankId, amount) then return Bank.notify(src, 'sv_not_enough_balance', 'error') end
    if not Player.Functions.AddMoney('cash', amount, 'bank-business-withdraw-' .. bankId) then
        Bank.credit(org.key, bankId, amount)
        return Bank.notify(src, 'sv_invalid_amount', 'error')
    end
    Bank.logTx(org.key, bankId, 'withdraw', amount, playerName(Player))
    Bank.notify(src, 'sv_biz_withdrew', 'success', Bank.money(amount), org.label)
    log(src, 'Withdrawal', bankId, org, { { name = 'Amount', value = BankMoney(amount), inline = true } })
    BankLogLarge('Business withdrawal', src, Config.Banks[bankId].label .. ' · ' .. org.label, amount)
    alertMembers('Business withdrawal', bankId, org, amount, cid)
end)

orgAction('bizAddMember', function(src, Player, cid, bankId, org, targetCid)
    if not org.isBoss then return Bank.notify(src, 'sv_biz_not_boss', 'error') end
    if not validCid(targetCid) then return Bank.notify(src, 'sv_biz_member_unknown', 'error') end
    if targetCid == cid or isMember(org.key, targetCid) then return Bank.notify(src, 'sv_biz_member_exists', 'error') end
    local name = CitizenName(targetCid)
    if not name then return Bank.notify(src, 'sv_biz_member_unknown', 'error') end
    if #members(org.key) >= (tonumber(BC.maxMembers) or 0) then return Bank.notify(src, 'sv_biz_member_max', 'error', BC.maxMembers or 0) end
    MySQL.insert.await('INSERT IGNORE INTO rsg_bank_business_members (org, citizenid, name, added_by) VALUES (?, ?, ?, ?)',
        { org.key, targetCid, name:sub(1, 100), cid })
    Bank.notify(src, 'sv_biz_added', 'success', name, org.label)
    log(src, 'Withdrawal rights granted', bankId, org, { { name = 'Citizen', value = ('%s (%s)'):format(name, targetCid), inline = true } })
end)

orgAction('bizRemoveMember', function(src, Player, cid, bankId, org, targetCid)
    if not org.isBoss then return Bank.notify(src, 'sv_biz_not_boss', 'error') end
    if not validCid(targetCid) then return end
    local n = MySQL.update.await('DELETE FROM rsg_bank_business_members WHERE org = ? AND citizenid = ?', { org.key, targetCid })
    if (n or 0) == 0 then return end
    Bank.notify(src, 'sv_biz_removed', 'success', CitizenName(targetCid) or targetCid)
    log(src, 'Withdrawal rights removed', bankId, org, { { name = 'Citizen', value = targetCid, inline = true } })
end)
