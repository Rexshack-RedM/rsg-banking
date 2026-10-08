local RSGCore = exports['rsg-core']:GetCoreObject()
lib.locale()

local busy     = {}   -- [src] = true while a transaction is running
local lastCall = {}   -- [src] = GetGameTimer() of last request (rate limit)

---------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------
local function round(n) return math.floor(n * 100 + 0.5) / 100 end

local function notify(src, key, ntype, ...)
    TriggerClientEvent('ox_lib:notify', src, {
        title = locale('cl_title'), description = locale(key, ...), type = ntype or 'inform', duration = 5000
    })
end

local function rateLimited(src)
    local now = GetGameTimer()
    if lastCall[src] and now - lastCall[src] < Config.Cooldown then BankLogBlocked(src, 'Rate limited'); return true end
    lastCall[src] = now
    return false
end

local function nearBank(src, bankId)
    local bank = type(bankId) == 'string' and Config.Banks[bankId]
    if not bank then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    return #(GetEntityCoords(ped) - bank.coords) <= Config.ServerMaxDistance
end

local function validAmount(src, amount)
    amount = tonumber(amount)
    if not amount or amount ~= amount or amount == math.huge then
        notify(src, 'sv_invalid_amount', 'error'); return nil
    end
    amount = round(amount)
    if amount < 0.01 then notify(src, 'sv_invalid_amount', 'error'); return nil end
    if amount > Config.MaxTransaction then
        notify(src, 'sv_max_amount', 'error', Config.MaxTransaction); return nil
    end
    return amount
end

local function getBalance(cid, bankId)
    return tonumber(MySQL.scalar.await('SELECT balance FROM rsg_bank_accounts WHERE citizenid = ? AND bank = ?', { cid, bankId }))
end

local function hasAccount(cid, bankId) return getBalance(cid, bankId) ~= nil end

-- Atomic balance changes. Return true only if a row was actually changed.
local function credit(cid, bankId, amount)
    local n = MySQL.update.await('UPDATE rsg_bank_accounts SET balance = balance + ? WHERE citizenid = ? AND bank = ?', { amount, cid, bankId })
    return (n or 0) > 0
end

local function debit(cid, bankId, amount)
    local n = MySQL.update.await('UPDATE rsg_bank_accounts SET balance = balance - ? WHERE citizenid = ? AND bank = ? AND balance >= ?', { amount, cid, bankId, amount })
    return (n or 0) > 0
end

local function logTx(cid, bankId, txType, amount, note)
    MySQL.insert('INSERT INTO rsg_bank_transactions (citizenid, bank, type, amount, note) VALUES (?, ?, ?, ?, ?)',
        { cid, bankId, txType, amount, note })
end

local function buildData(src, bankId)
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return nil end
    local cid = Player.PlayerData.citizenid

    local owned = {}
    for _, row in ipairs(MySQL.query.await('SELECT bank, balance FROM rsg_bank_accounts WHERE citizenid = ?', { cid }) or {}) do
        owned[row.bank] = tonumber(row.balance) or 0
    end

    local branches = {}
    for id, b in pairs(Config.Banks) do
        branches[#branches + 1] = { id = id, label = b.label, balance = owned[id] or 0, open = owned[id] ~= nil }
    end
    table.sort(branches, function(a, b) return a.label < b.label end)

    local history = {}
    if owned[bankId] then
        history = MySQL.query.await(
            'SELECT type, amount, note, UNIX_TIMESTAMP(created_at) AS ts FROM rsg_bank_transactions WHERE citizenid = ? AND bank = ? ORDER BY id DESC LIMIT ?',
            { cid, bankId, Config.HistoryLimit }) or {}
    end

    local ci = Player.PlayerData.charinfo or {}
    local name = ('%s %s'):format(ci.firstname or '', ci.lastname or ''):match('^%s*(.-)%s*$')
    return {
        bankId     = bankId,
        label      = Config.Banks[bankId].label,
        name       = name,
        hasAccount = owned[bankId] ~= nil,
        balance    = owned[bankId] or 0,
        cash       = Player.Functions.GetMoney('cash') or 0,
        openFee    = Config.AccountOpenFee,
        feePercent = Config.TransferFeePercent,
        minFee     = Config.TransferMinFee,
        branches   = branches,
        history    = history,
    }
end

-- Player lookup, DB ready, distance, rate limit and per-player lock around every action
local function guarded(src, bankId, fn)
    if not BankingDBReady or busy[src] or rateLimited(src) then return nil end
    if not nearBank(src, bankId) then
        notify(src, 'sv_too_far', 'error')
        BankLogSuspicious(src, 'Transaction attempted away from the bank', bankId)
        return nil
    end
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return nil end

    busy[src] = true
    local ok, err = pcall(fn, Player, Player.PlayerData.citizenid)
    busy[src] = nil
    if not ok then print(('[rsg-banking] ^1error:^7 %s'):format(err)) end
    return buildData(src, bankId)
end

---------------------------------------------------------------------
-- callbacks
---------------------------------------------------------------------
lib.callback.register('rsg-banking:server:getData', function(src, bankId)
    if not BankingDBReady or rateLimited(src) then return nil end
    if not nearBank(src, bankId) then BankLogBlocked(src, 'Menu request away from the bank', tostring(bankId)); return nil end
    return buildData(src, bankId)
end)

lib.callback.register('rsg-banking:server:openAccount', function(src, bankId)
    return guarded(src, bankId, function(Player, cid)
        if hasAccount(cid, bankId) then return notify(src, 'sv_account_exists', 'error') end
        local fee = math.max(0, tonumber(Config.AccountOpenFee) or 0)
        if fee > 0 and not Player.Functions.RemoveMoney('cash', fee, 'bank-open-' .. bankId) then
            return notify(src, 'sv_cant_afford_open', 'error', fee)
        end
        local id = MySQL.insert.await('INSERT IGNORE INTO rsg_bank_accounts (citizenid, bank, balance) VALUES (?, ?, 0)', { cid, bankId })
        if not id or id == 0 then
            if fee > 0 then Player.Functions.AddMoney('cash', fee, 'bank-open-refund') end
            return notify(src, 'sv_account_exists', 'error')
        end
        logTx(cid, bankId, 'opened', fee, nil)
        notify(src, 'sv_account_opened', 'success', Config.Banks[bankId].label)
        BankLog('account_opened', src, {
            { name = 'Branch', value = Config.Banks[bankId].label, inline = true },
            { name = 'Fee', value = BankMoney(fee), inline = true },
        })
    end)
end)

lib.callback.register('rsg-banking:server:deposit', function(src, bankId, amount)
    return guarded(src, bankId, function(Player, cid)
        if not hasAccount(cid, bankId) then return notify(src, 'sv_no_account', 'error') end
        amount = validAmount(src, amount); if not amount then return end
        if not Player.Functions.RemoveMoney('cash', amount, 'bank-deposit-' .. bankId) then
            return notify(src, 'sv_not_enough_cash', 'error')
        end
        if not credit(cid, bankId, amount) then
            Player.Functions.AddMoney('cash', amount, 'bank-deposit-refund')
            return notify(src, 'sv_no_account', 'error')
        end
        logTx(cid, bankId, 'deposit', amount, nil)
        notify(src, 'sv_deposited', 'success', amount)
        local label = Config.Banks[bankId].label
        BankLog('deposit', src, {
            { name = 'Branch', value = label, inline = true },
            { name = 'Amount', value = BankMoney(amount), inline = true },
            { name = 'New Balance', value = BankMoney(getBalance(cid, bankId)), inline = true },
        })
        BankLogLarge('Deposit', src, label, amount)
    end)
end)

lib.callback.register('rsg-banking:server:withdraw', function(src, bankId, amount)
    return guarded(src, bankId, function(Player, cid)
        amount = validAmount(src, amount); if not amount then return end
        if not debit(cid, bankId, amount) then return notify(src, 'sv_not_enough_balance', 'error') end
        Player.Functions.AddMoney('cash', amount, 'bank-withdraw-' .. bankId)
        logTx(cid, bankId, 'withdraw', amount, nil)
        notify(src, 'sv_withdrew', 'success', amount)
        local label = Config.Banks[bankId].label
        BankLog('withdraw', src, {
            { name = 'Branch', value = label, inline = true },
            { name = 'Amount', value = BankMoney(amount), inline = true },
            { name = 'New Balance', value = BankMoney(getBalance(cid, bankId)), inline = true },
        })
        BankLogLarge('Withdrawal', src, label, amount)
    end)
end)

lib.callback.register('rsg-banking:server:transfer', function(src, bankId, targetId, amount)
    return guarded(src, bankId, function(_, cid)
        if type(targetId) ~= 'string' or not Config.Banks[targetId] then return end
        if targetId == bankId then return notify(src, 'sv_same_bank', 'error') end
        if not hasAccount(cid, targetId) then
            return notify(src, 'sv_no_account_target', 'error', Config.Banks[targetId].label)
        end
        amount = validAmount(src, amount); if not amount then return end

        local fee   = round(math.max(Config.TransferMinFee, amount * Config.TransferFeePercent / 100))
        local total = round(amount + fee)

        if not debit(cid, bankId, total) then return notify(src, 'sv_not_enough_balance', 'error') end
        if not credit(cid, targetId, amount) then
            credit(cid, bankId, total) -- roll back
            return notify(src, 'sv_no_account_target', 'error', Config.Banks[targetId].label)
        end

        local toLabel = Config.Banks[targetId].label
        logTx(cid, bankId, 'wire_out', total, locale('tx_wire_to', toLabel, fee))
        logTx(cid, targetId, 'wire_in', amount, locale('tx_wire_from', Config.Banks[bankId].label))
        notify(src, 'sv_transferred', 'success', amount, toLabel, fee)
        local fromLabel = Config.Banks[bankId].label
        BankLog('transfer', src, {
            { name = 'From', value = fromLabel, inline = true },
            { name = 'To', value = toLabel, inline = true },
            { name = 'Amount', value = BankMoney(amount), inline = true },
            { name = 'Fee', value = BankMoney(fee), inline = true },
            { name = 'Total Debited', value = BankMoney(total), inline = true },
        })
        BankLogLarge('Wire', src, fromLabel, amount, { { name = 'To', value = toLabel, inline = true } })
    end)
end)

AddEventHandler('playerDropped', function()
    busy[source], lastCall[source] = nil, nil
end)

---------------------------------------------------------------------
-- exports for other resources (server-side only)
---------------------------------------------------------------------
exports('HasAccount', hasAccount)

exports('GetBranchBalance', function(citizenid, bankId)
    return getBalance(citizenid, bankId) or 0
end)

exports('GetTotalBalance', function(citizenid)
    return tonumber(MySQL.scalar.await('SELECT COALESCE(SUM(balance), 0) FROM rsg_bank_accounts WHERE citizenid = ?', { citizenid })) or 0
end)

exports('AddBranchMoney', function(citizenid, bankId, amount, note)
    amount = round(tonumber(amount) or 0)
    if amount <= 0 or not Config.Banks[bankId] or not credit(citizenid, bankId, amount) then return false end
    logTx(citizenid, bankId, 'deposit', amount, note)
    BankLog('export', nil, {
        { name = 'Action', value = 'AddBranchMoney', inline = true },
        { name = 'Resource', value = GetInvokingResource() or 'unknown', inline = true },
        { name = 'Citizen ID', value = citizenid, inline = true },
        { name = 'Branch', value = Config.Banks[bankId].label, inline = true },
        { name = 'Amount', value = BankMoney(amount), inline = true },
        { name = 'Note', value = note, inline = false },
    })
    return true
end)

exports('RemoveBranchMoney', function(citizenid, bankId, amount, note)
    amount = round(tonumber(amount) or 0)
    if amount <= 0 or not Config.Banks[bankId] or not debit(citizenid, bankId, amount) then return false end
    logTx(citizenid, bankId, 'withdraw', amount, note)
    BankLog('export', nil, {
        { name = 'Action', value = 'RemoveBranchMoney', inline = true },
        { name = 'Resource', value = GetInvokingResource() or 'unknown', inline = true },
        { name = 'Citizen ID', value = citizenid, inline = true },
        { name = 'Branch', value = Config.Banks[bankId].label, inline = true },
        { name = 'Amount', value = BankMoney(amount), inline = true },
        { name = 'Note', value = note, inline = false },
    })
    return true
end)
