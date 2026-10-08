-----------------------------------------------------------------------
-- Loans: borrow from a branch, repay at the same branch
-----------------------------------------------------------------------
local RSGCore = exports['rsg-core']:GetCoreObject()
local LC = Config.Loans or {}

-- oxmysql returns TINYINT(1) as a boolean; accept both
local function isLate(v) return v == true or v == 1 end

local function getLoan(cid, bankId)
    local row = MySQL.single.await(
        'SELECT id, principal, owed, late, UNIX_TIMESTAMP(due_at) AS due FROM rsg_bank_loans WHERE citizenid = ? AND bank = ?',
        { cid, bankId })
    if not row then return nil end
    row.owed, row.principal, row.due = tonumber(row.owed), tonumber(row.principal), tonumber(row.due)
    return row
end

local function loanCount(cid)
    return tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM rsg_bank_loans WHERE citizenid = ?', { cid })) or 0
end

local function accountHours(cid, bankId)
    return tonumber(MySQL.scalar.await(
        'SELECT TIMESTAMPDIFF(HOUR, created_at, NOW()) FROM rsg_bank_accounts WHERE citizenid = ? AND bank = ?', { cid, bankId })) or 0
end

-- data for the NUI (one query for all of the player's loans)
function BuildLoanData(cid, bankId, owned)
    if not LC.enabled then return nil end
    local loans = MySQL.query.await(
        'SELECT bank, principal, owed, late, UNIX_TIMESTAMP(due_at) AS due FROM rsg_bank_loans WHERE citizenid = ?', { cid }) or {}
    local loan, elsewhere = nil, {}
    for _, l in ipairs(loans) do
        if l.bank == bankId then
            loan = { owed = tonumber(l.owed), principal = tonumber(l.principal), due = tonumber(l.due), late = isLate(l.late) }
        else
            elsewhere[#elsewhere + 1] = Config.Banks[l.bank] and Config.Banks[l.bank].label or l.bank
        end
    end
    local blocked = nil
    if not loan then
        if #loans >= (LC.maxActive or 1) then
            blocked = 'limit'
        elseif (LC.minAccountHours or 0) > 0 and owned[bankId] and accountHours(cid, bankId) < LC.minAccountHours then
            blocked = 'age'
        end
    end
    return {
        min = LC.minAmount, max = LC.maxAmount, interest = LC.interestPercent, termDays = LC.termDays,
        minHours = LC.minAccountHours, blocked = blocked, elsewhere = elsewhere, now = os.time(),
        active = loan and { owed = loan.owed, principal = loan.principal, due = loan.due, late = loan.late } or nil,
    }
end

lib.callback.register('rsg-banking:server:takeLoan', function(src, bankId, amount)
    return Bank.guarded(src, bankId, function(Player, cid)
        if not LC.enabled then return end
        if not Bank.hasAccount(cid, bankId) then return Bank.notify(src, 'sv_no_account', 'error') end
        if getLoan(cid, bankId) then return Bank.notify(src, 'sv_loan_exists', 'error') end
        if loanCount(cid) >= (LC.maxActive or 1) then return Bank.notify(src, 'sv_loan_limit', 'error') end
        if (LC.minAccountHours or 0) > 0 and accountHours(cid, bankId) < LC.minAccountHours then
            return Bank.notify(src, 'sv_loan_age', 'error', LC.minAccountHours)
        end
        amount = Bank.validAmount(src, amount); if not amount then return end
        if amount < LC.minAmount or amount > LC.maxAmount then
            return Bank.notify(src, 'sv_loan_range', 'error', Bank.money(LC.minAmount), Bank.money(LC.maxAmount))
        end

        local owed = Bank.round(amount * (1 + (LC.interestPercent or 0) / 100))
        local id = MySQL.insert.await(
            'INSERT IGNORE INTO rsg_bank_loans (citizenid, bank, principal, owed, due_at) VALUES (?, ?, ?, ?, NOW() + INTERVAL ? DAY)',
            { cid, bankId, amount, owed, LC.termDays })
        if not id or id == 0 then return Bank.notify(src, 'sv_loan_exists', 'error') end
        if not Bank.credit(cid, bankId, amount) then
            MySQL.update.await('DELETE FROM rsg_bank_loans WHERE id = ?', { id })
            return Bank.notify(src, 'sv_no_account', 'error')
        end

        Bank.logTx(cid, bankId, 'loan', amount, locale('tx_loan_taken', Bank.money(owed), LC.termDays))
        Bank.notify(src, 'sv_loan_taken', 'success', Bank.money(amount), Bank.money(owed), LC.termDays)
        BankLog('loan', src, {
            { name = 'Action', value = 'Loan taken', inline = true },
            { name = 'Branch', value = Config.Banks[bankId].label, inline = true },
            { name = 'Amount', value = BankMoney(amount), inline = true },
            { name = 'To Repay', value = BankMoney(owed), inline = true },
            { name = 'Term', value = LC.termDays .. ' days', inline = true },
        })
    end)
end)

-- method: 'bank' (from this branch vault) or 'cash'
lib.callback.register('rsg-banking:server:repayLoan', function(src, bankId, amount, method)
    return Bank.guarded(src, bankId, function(Player, cid)
        if not LC.enabled then return end
        local loan = getLoan(cid, bankId)
        if not loan then return Bank.notify(src, 'sv_no_loan', 'error') end
        amount = Bank.validAmount(src, amount); if not amount then return end
        amount = math.min(amount, loan.owed)

        if method == 'cash' then
            if not Player.Functions.RemoveMoney('cash', amount, 'bank-loan-repay-' .. bankId) then
                return Bank.notify(src, 'sv_not_enough_cash', 'error')
            end
        else
            if not Bank.debit(cid, bankId, amount) then return Bank.notify(src, 'sv_not_enough_balance', 'error') end
        end

        local n = MySQL.update.await('UPDATE rsg_bank_loans SET owed = owed - ? WHERE id = ? AND owed >= ?', { amount, loan.id, amount })
        if (n or 0) == 0 then -- loan changed underneath us (auto-collect); refund
            if method == 'cash' then Player.Functions.AddMoney('cash', amount, 'bank-loan-refund') else Bank.credit(cid, bankId, amount) end
            return Bank.notify(src, 'sv_no_loan', 'error')
        end

        local left = Bank.round(loan.owed - amount)
        if left <= 0 then MySQL.update.await('DELETE FROM rsg_bank_loans WHERE id = ?', { loan.id }) end
        Bank.logTx(cid, bankId, 'loan_payment', amount, locale(method == 'cash' and 'tx_loan_paid_cash' or 'tx_loan_paid_bank', Bank.money(left)))
        if left <= 0 then Bank.notify(src, 'sv_loan_cleared', 'success')
        else Bank.notify(src, 'sv_loan_paid', 'success', Bank.money(amount), Bank.money(left)) end
        BankLog('loan', src, {
            { name = 'Action', value = left <= 0 and 'Loan cleared' or 'Loan payment', inline = true },
            { name = 'Branch', value = Config.Banks[bankId].label, inline = true },
            { name = 'Paid', value = BankMoney(amount) .. ' (' .. (method == 'cash' and 'cash' or 'vault') .. ')', inline = true },
            { name = 'Remaining', value = BankMoney(math.max(left, 0)), inline = true },
        })
    end)
end)

---------------------------------------------------------------------
-- overdue handling: late penalty + automatic collection
---------------------------------------------------------------------
local function notifyCid(cid, key, ntype, ...)
    local P = RSGCore.Functions.GetPlayerByCitizenId(cid)
    if P then Bank.notify(P.PlayerData.source, key, ntype, ...) end
end

local function processOverdue()
    local rows = MySQL.query.await(
        'SELECT id, citizenid, bank, owed, late FROM rsg_bank_loans WHERE due_at < NOW()') or {}
    for _, loan in ipairs(rows) do
        local cid, bankId, owed = loan.citizenid, loan.bank, tonumber(loan.owed)
        local label = Config.Banks[bankId] and Config.Banks[bankId].label or bankId

        if not isLate(loan.late) then
            local penalty = Bank.round(owed * (LC.latePenaltyPercent or 0) / 100)
            MySQL.update.await('UPDATE rsg_bank_loans SET owed = owed + ?, late = 1 WHERE id = ? AND late = 0', { penalty, loan.id })
            owed = Bank.round(owed + penalty)
            if penalty > 0 then Bank.logTx(cid, bankId, 'loan_late', penalty, locale('tx_loan_late')) end
            notifyCid(cid, 'sv_loan_overdue', 'error', label, Bank.money(owed))
            BankLog('loan', nil, {
                { name = 'Action', value = 'Loan overdue', inline = true },
                { name = 'Citizen ID', value = cid, inline = true },
                { name = 'Branch', value = label, inline = true },
                { name = 'Penalty', value = BankMoney(penalty), inline = true },
                { name = 'Owed', value = BankMoney(owed), inline = true },
            })
        end

        if LC.autoCollect and owed > 0 then
            -- loan branch first, then any other branch with money
            local accounts = MySQL.query.await(
                'SELECT bank, balance FROM rsg_bank_accounts WHERE citizenid = ? AND balance > 0 ORDER BY (bank = ?) DESC, balance DESC',
                { cid, bankId }) or {}
            local collected = 0
            for _, acc in ipairs(accounts) do
                if owed <= 0 then break end
                local take = Bank.round(math.min(tonumber(acc.balance) or 0, owed))
                if take > 0 and Bank.debit(cid, acc.bank, take) then
                    -- guard: the player may have repaid at the counter meanwhile
                    local n = MySQL.update.await('UPDATE rsg_bank_loans SET owed = owed - ? WHERE id = ? AND owed >= ?', { take, loan.id, take })
                    if (n or 0) == 0 then Bank.credit(cid, acc.bank, take); break end
                    owed = Bank.round(owed - take)
                    collected = collected + take
                    Bank.logTx(cid, acc.bank, 'loan_payment', take, locale('tx_loan_collected', label))
                end
            end
            if owed <= 0 then MySQL.update.await('DELETE FROM rsg_bank_loans WHERE id = ?', { loan.id }) end
            if collected > 0 then
                notifyCid(cid, 'sv_loan_collected', 'error', Bank.money(collected), label, Bank.money(math.max(owed, 0)))
                BankLog('loan', nil, {
                    { name = 'Action', value = owed <= 0 and 'Overdue loan collected in full' or 'Overdue loan part-collected', inline = true },
                    { name = 'Citizen ID', value = cid, inline = true },
                    { name = 'Branch', value = label, inline = true },
                    { name = 'Collected', value = BankMoney(collected), inline = true },
                    { name = 'Remaining', value = BankMoney(math.max(owed, 0)), inline = true },
                })
            end
        end
    end
end

CreateThread(function()
    if not LC.enabled then return end
    while not BankingDBReady do Wait(1000) end
    while true do
        local ok, err = pcall(processOverdue)
        if not ok then print(('[rsg-banking] ^1loan check error:^7 %s'):format(err)) end
        Wait(math.max(1, LC.checkInterval or 10) * 60000)
    end
end)

---------------------------------------------------------------------
-- exports
---------------------------------------------------------------------
exports('GetLoans', function(citizenid)
    return MySQL.query.await(
        'SELECT bank, principal, owed, late, UNIX_TIMESTAMP(due_at) AS due FROM rsg_bank_loans WHERE citizenid = ?', { citizenid }) or {}
end)

exports('HasActiveLoan', function(citizenid)
    return loanCount(citizenid) > 0
end)
