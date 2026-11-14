-----------------------------------------------------------------------
-- rsg-telegram integration (optional)
-- rsg-telegram has no send export, so telegrams are written straight into its
-- `rsg_telegrams` table and the recipient (if online) gets its normal arrival
-- notification. Nothing happens when rsg-telegram is not running.
-----------------------------------------------------------------------
local RSGCore = exports['rsg-core']:GetCoreObject()
local TC = Config.Telegram or {}
local stmtLast = {} -- [citizenid] = os.time() of the last statement

function TelegramAvailable()
    return TC.enabled and GetResourceState('rsg-telegram') == 'started' or false
end

local function clean(s, max)
    s = tostring(s or ''):gsub('[<>]', '')
    return s:sub(1, max)
end

---Write a telegram from the bank into a citizen's inbox. Returns true on success.
function TelegramSend(cid, subject, message)
    if not TelegramAvailable() or type(cid) ~= 'string' then return false end
    local name = CitizenName(cid)
    if not name then return false end
    local ok, id = pcall(MySQL.insert.await,
        'INSERT INTO rsg_telegrams (citizenid, recipient_name, sender_citizenid, sender_name, subject, message) VALUES (?, ?, ?, ?, ?, ?)',
        { cid, clean(name, 100), 'bank', clean(TC.senderName or 'Bank', 100), clean(subject, 50), clean(message, 1000) })
    if not ok or not id then return false end
    local P = RSGCore.Functions.GetPlayerByCitizenId(cid)
    if P then TriggerClientEvent('rsg-telegram:client:newTelegram', P.PlayerData.source, TC.senderName or 'Bank') end
    return true
end

-- the recipient of "send money" gets a receipt
function TelegramReceiptSend(rcid, senderName, amount, homeLabel)
    if not TC.sendReceipts then return end
    TelegramSend(rcid, locale('tg_received_subject'), locale('tg_received_body', senderName, BankMoney(amount), homeLabel))
end

local KIND = {
    Deposit = 'tg_kind_deposit', Withdrawal = 'tg_kind_withdraw', Wire = 'tg_kind_wire', Send = 'tg_kind_send',
    ['Business deposit'] = 'tg_kind_biz_deposit', ['Business withdrawal'] = 'tg_kind_biz_withdraw',
}

-- called from BankLogLarge for every deposit / withdrawal / wire / transfer
function TelegramLarge(kind, src, bankLabel, amount)
    if not TC.alertLarge or (tonumber(amount) or 0) < (TC.largeAmount or math.huge) or not TelegramAvailable() then return end
    local P = RSGCore.Functions.GetPlayer(src)
    if not P then return end
    local kindText = KIND[kind] and locale(KIND[kind]) or tostring(kind)
    TelegramSend(P.PlayerData.citizenid, locale('tg_large_subject', kindText), locale('tg_large_body', kindText, BankMoney(amount), bankLabel))
end

-- ledger line signs, matching the NUI
local SIGN = {
    deposit = 1, withdraw = -1, wire_in = 1, wire_out = -1, opened = -1, loan = 1, loan_payment = -1, loan_late = 0,
    lockbox = -1, lockbox_up = -1, lockbox_rent = -1, send_in = 1, send_out = -1, interest = 1, loan_default = 0,
}

Bank.register('rsg-banking:server:sendStatement', function(src, bankId)
    return Bank.guarded(src, bankId, function(Player, cid)
        if not TelegramAvailable() then return Bank.notify(src, 'sv_statement_failed', 'error') end
        local now = os.time()
        if stmtLast[cid] and now - stmtLast[cid] < (TC.statementCooldown or 60) then return Bank.notify(src, 'sv_slow_down', 'warning') end
        if not Bank.hasAccount(cid, bankId) then return Bank.notify(src, 'sv_no_account', 'error') end
        stmtLast[cid] = now

        local label = Config.Banks[bankId].label
        local rows = MySQL.query.await(
            'SELECT type, amount, UNIX_TIMESTAMP(created_at) AS ts FROM rsg_bank_transactions WHERE citizenid = ? AND bank = ? ORDER BY id DESC LIMIT ?',
            { cid, bankId, math.max(1, math.min(30, TC.statementLines or 12)) }) or {}

        local lines = { locale('tg_statement_header', label, BankMoney(Bank.getBalance(cid, bankId) or 0)), '' }
        for _, r in ipairs(rows) do
            local sign = SIGN[r.type] or 0
            local typeLabel = locale('ui_tx_' .. r.type)
            local amt = (sign > 0 and '+' or sign < 0 and '-' or '') .. BankMoney(r.amount)
            lines[#lines + 1] = ('%s  %s  %s'):format(os.date('%d %b', tonumber(r.ts) or now), typeLabel, amt)
        end
        if #rows == 0 then lines[#lines + 1] = locale('tg_statement_empty') end

        if TelegramSend(cid, locale('tg_statement_subject', label), table.concat(lines, '\n')) then
            Bank.notify(src, 'sv_statement_sent', 'success')
        else
            Bank.notify(src, 'sv_statement_failed', 'error')
        end
    end)
end)

