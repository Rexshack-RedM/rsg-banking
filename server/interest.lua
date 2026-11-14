-----------------------------------------------------------------------
-- Savings interest
-- Once per interval every personal branch balance earns interest on its first
-- `maxBalance` dollars (accounts under `minBalance` earn nothing). Shared job /
-- gang accounts never earn interest. Each payout is a ledger entry.
-----------------------------------------------------------------------
local IC = Config.Interest or {}
local lastPaid = nil -- unix seconds of the last payout (database clock is not needed: only used for the UI countdown)

local EARNED = 'ROUND(LEAST(balance, ?) * ? / 100, 2)'
local PERSONAL = "citizenid NOT LIKE 'job:%' AND citizenid NOT LIKE 'gang:%'"

local function intervalSeconds() return math.max(1, tonumber(IC.intervalHours) or 24) * 3600 end

function BuildInterestData()
    if not IC.enabled then return nil end
    return {
        percent = IC.percentPerDay, cap = IC.maxBalance, min = IC.minBalance,
        nextAt = lastPaid and (lastPaid + intervalSeconds()) or nil, hours = IC.intervalHours or 24,
    }
end

local function payout()
    local rate, cap, min = tonumber(IC.percentPerDay) or 0, tonumber(IC.maxBalance) or 0, tonumber(IC.minBalance) or 0
    if rate <= 0 or cap <= 0 then return end

    local sum = MySQL.single.await(
        ('SELECT COUNT(*) AS n, COALESCE(SUM(%s), 0) AS total FROM rsg_bank_accounts WHERE balance >= ? AND %s AND %s >= 0.01'):format(EARNED, PERSONAL, EARNED),
        { cap, rate, min, cap, rate })
    if not sum or (tonumber(sum.n) or 0) == 0 then return end

    -- ledger rows and balances change together or not at all
    local ok = MySQL.transaction.await({
        { query = ("INSERT INTO rsg_bank_transactions (citizenid, bank, type, amount, note) SELECT citizenid, bank, 'interest', %s, ? FROM rsg_bank_accounts WHERE balance >= ? AND %s AND %s >= 0.01"):format(EARNED, PERSONAL, EARNED),
          values = { cap, rate, locale('tx_interest'), min, cap, rate } },
        { query = ('UPDATE rsg_bank_accounts SET balance = balance + %s WHERE balance >= ? AND %s AND %s >= 0.01'):format(EARNED, PERSONAL, EARNED),
          values = { cap, rate, min, cap, rate } },
    })
    if not ok then print('[rsg-banking] ^1interest payout failed (rolled back)^7'); return end

    print(('[rsg-banking] ^2interest paid: $%s to %s accounts^7'):format(BankMoney(sum.total):sub(2), sum.n))
    BankLog('interest', nil, {
        { name = 'Accounts', value = tostring(sum.n), inline = true },
        { name = 'Total paid', value = BankMoney(sum.total), inline = true },
    })
end

local function setLast(ts)
    lastPaid = ts
    MySQL.query.await("INSERT INTO rsg_bank_meta (k, v) VALUES ('last_interest', ?) ON DUPLICATE KEY UPDATE v = VALUES(v)", { tostring(ts) })
end

local function check()
    local last = tonumber(MySQL.scalar.await("SELECT v FROM rsg_bank_meta WHERE k = 'last_interest'"))
    local now = os.time()
    if not last then
        setLast(now) -- first start: the first payout comes one interval from now
    elseif now - last >= intervalSeconds() then
        setLast(now) -- record first, so a crash can never pay the same interval twice
        payout()
    else
        lastPaid = last
    end
end

CreateThread(function()
    if not IC.enabled then return end
    while not BankingDBReady do Wait(1000) end
    while true do
        local ok, err = pcall(check)
        if not ok then print(('[rsg-banking] ^1interest error:^7 %s'):format(err)) end
        Wait(10 * 60000)
    end
end)

-- server console: force a payout now (for testing)
RegisterCommand('bankinterestnow', function(src)
    if src ~= 0 or not IC.enabled then return end
    setLast(os.time())
    payout()
end, true)
