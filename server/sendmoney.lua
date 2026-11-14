-----------------------------------------------------------------------
-- Send money to another citizen
-- Debited from the sender's branch vault, paid into the recipient's home
-- branch (works while they are offline). Fee, per-transfer max and a
-- rolling 24h limit come from Config.Send.
-----------------------------------------------------------------------
local RSGCore = exports['rsg-core']:GetCoreObject()
local SC = Config.Send or {}
local lookupLast = {} -- [src] = GetGameTimer() of the last recipient lookup

local function validCid(cid)
    return type(cid) == 'string' and #cid > 0 and #cid <= 50 and cid:match('^[%w_%-]+$') ~= nil
end

local function sentToday(cid)
    return tonumber(MySQL.scalar.await(
        "SELECT COALESCE(SUM(amount), 0) FROM rsg_bank_transactions WHERE citizenid = ? AND type = 'send_out' AND created_at > (NOW() - INTERVAL 1 DAY)",
        { cid })) or 0
end

-- data for the NUI
function BuildSendData(cid)
    if not SC.enabled then return nil end
    local limit = tonumber(SC.dailyLimit) or 0
    return {
        feePercent = SC.feePercent or 0, minFee = SC.minFee or 0, max = SC.maxAmount or Config.MaxTransaction,
        dailyLeft = limit > 0 and math.max(0, Bank.round(limit - sentToday(cid))) or nil,
    }
end

-- shows the recipient's name before sending (throttled, only near a bank)
Bank.register('rsg-banking:server:lookupRecipient', function(src, bankId, cid)
    if not SC.enabled or not BankingDBReady or not validCid(cid) or not Bank.nearBank(src, bankId) then return nil end
    local now = GetGameTimer()
    if lookupLast[src] and now - lookupLast[src] < 400 then return nil end
    lookupLast[src] = now
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player or Player.PlayerData.citizenid == cid then return nil end
    return CitizenName(cid)
end)

Bank.register('rsg-banking:server:sendMoney', function(src, bankId, rcid, amount)
    return Bank.guarded(src, bankId, function(Player, cid)
        if not SC.enabled then return end
        if not validCid(rcid) then return Bank.notify(src, 'sv_send_unknown', 'error') end
        if rcid == cid then return Bank.notify(src, 'sv_send_self', 'error') end
        if not Bank.hasAccount(cid, bankId) then return Bank.notify(src, 'sv_no_account', 'error') end
        amount = Bank.validAmount(src, amount); if not amount then return end
        local maxAmount = tonumber(SC.maxAmount) or Config.MaxTransaction
        if amount > maxAmount then return Bank.notify(src, 'sv_send_max', 'error', Bank.money(maxAmount)) end

        local name = CitizenName(rcid)
        if not name then return Bank.notify(src, 'sv_send_unknown', 'error') end
        if not GetHomeBranch(rcid) then return Bank.notify(src, 'sv_send_no_home', 'error') end

        local fee   = Bank.round(math.max(SC.minFee or 0, amount * (SC.feePercent or 0) / 100))
        local total = Bank.round(amount + fee)
        local limit = tonumber(SC.dailyLimit) or 0
        if limit > 0 then
            local left = math.max(0, Bank.round(limit - sentToday(cid)))
            if total > left then return Bank.notify(src, 'sv_send_limit', 'error', Bank.money(left)) end
        end

        if not Bank.debit(cid, bankId, total) then return Bank.notify(src, 'sv_not_enough_balance', 'error') end

        local ci = Player.PlayerData.charinfo or {}
        local senderName = ('%s %s'):format(ci.firstname or '', ci.lastname or ''):match('^%s*(.-)%s*$')
        local ok, homeId = pcall(AddHomeMoney, rcid, amount, locale('tx_send_from', senderName), 'send_in')
        if not ok or not homeId then
            Bank.credit(cid, bankId, total) -- nothing was paid out: give it back
            return Bank.notify(src, 'sv_send_no_home', 'error')
        end

        Bank.logTx(cid, bankId, 'send_out', total, locale('tx_send_to', name, Bank.money(fee)))
        Bank.notify(src, 'sv_sent', 'success', Bank.money(amount), name, Bank.money(fee))

        local homeLabel = Config.Banks[homeId] and Config.Banks[homeId].label or homeId
        local R = RSGCore.Functions.GetPlayerByCitizenId(rcid)
        if R then Bank.notify(R.PlayerData.source, 'sv_send_received', 'success', senderName, Bank.money(amount), homeLabel) end
        if TelegramReceiptSend then pcall(TelegramReceiptSend, rcid, senderName, amount, homeLabel) end

        local label = Config.Banks[bankId].label
        BankLog('send', src, {
            { name = 'From Branch', value = label, inline = true },
            { name = 'To', value = ('%s (%s)'):format(name, rcid), inline = true },
            { name = 'Amount', value = BankMoney(amount), inline = true },
            { name = 'Fee', value = BankMoney(fee), inline = true },
            { name = 'Paid into', value = homeLabel, inline = true },
        })
        BankLogLarge('Send', src, label, amount, { { name = 'To', value = name, inline = true } })
    end)
end)

AddEventHandler('playerDropped', function() lookupLast[source] = nil end)
