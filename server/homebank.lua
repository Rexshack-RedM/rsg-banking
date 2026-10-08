-----------------------------------------------------------------------
-- Home branch + RSG-Core money bridge
--  * every player has one home branch (paychecks and any script paying
--    into RSG-Core 'bank' money land there)
--  * one-off migration of the old core money types into branch accounts
-----------------------------------------------------------------------
local RSGCore = exports['rsg-core']:GetCoreObject()

-- old RSG-Core money type -> branch id. 'bank' goes to the home branch.
local LEGACY = {
    valbank = 'valentine',
    rhobank = 'rhodes',
    blkbank = 'blackwater',
    armbank = 'armadillo',
}

local function round(n) return math.floor(n * 100 + 0.5) / 100 end

function GetHomeBranch(cid)
    local bank = MySQL.scalar.await('SELECT bank FROM rsg_bank_home WHERE citizenid = ?', { cid })
    if bank and Config.Banks[bank] then return bank end
    return nil
end

function SetHomeBranch(cid, bankId)
    if not Config.Banks[bankId] then return false end
    MySQL.query.await('INSERT INTO rsg_bank_home (citizenid, bank) VALUES (?, ?) ON DUPLICATE KEY UPDATE bank = VALUES(bank)', { cid, bankId })
    return true
end

-- credit a branch, opening the account if needed (used by migration and paychecks)
local function creditOrOpen(cid, bankId, amount, txType, note)
    MySQL.query.await([[INSERT INTO rsg_bank_accounts (citizenid, bank, balance) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE balance = balance + VALUES(balance)]], { cid, bankId, amount })
    MySQL.insert.await('INSERT INTO rsg_bank_transactions (citizenid, bank, type, amount, note) VALUES (?, ?, ?, ?, ?)',
        { cid, bankId, txType, amount, note })
end

---Pay money into a player's home branch. Returns the branch id, or false if they have no home branch.
function AddHomeMoney(cid, amount, note)
    amount = round(tonumber(amount) or 0)
    if amount <= 0 then return false end
    local home = GetHomeBranch(cid)
    if not home then return false end
    creditOrOpen(cid, home, amount, 'deposit', note)
    return home
end

---Work out where a citizen's legacy money goes. Returns { [bankId] = amount }, home
local function planMove(cid, money)
    local moves, total = {}, 0
    for key, bankId in pairs(LEGACY) do
        local v = round(tonumber(money[key]) or 0)
        if v > 0 and Config.Banks[bankId] then moves[bankId] = (moves[bankId] or 0) + v; total = total + v end
    end
    local home = GetHomeBranch(cid)
    local core = round(tonumber(money.bank) or 0)
    if not home and (core > 0 or total > 0) then
        -- no home yet: the branch holding the most money, else the default
        local best, bestAmt = nil, -1
        for b, a in pairs(moves) do if a > bestAmt then best, bestAmt = b, a end end
        home = best or Config.DefaultHomeBank
    end
    if core > 0 and home then moves[home] = (moves[home] or 0) + core end
    return moves, home
end

local function applyMoves(cid, moves, home)
    if home and not GetHomeBranch(cid) then SetHomeBranch(cid, home) end
    local n = 0
    for bankId, amount in pairs(moves) do
        creditOrOpen(cid, bankId, amount, 'deposit', 'Transferred from old bank account')
        n = n + amount
    end
    return n
end

---Online player: move legacy money out of PlayerData (the core saves it, so never touch their DB row)
local function sweepOnline(Player)
    local d = Player.PlayerData
    local moves, home = planMove(d.citizenid, d.money)
    if not next(moves) then return end
    -- zero first so a failure can't duplicate money
    for key in pairs(LEGACY) do if d.money[key] then d.money[key] = 0 end end
    if (tonumber(d.money.bank) or 0) > 0 then Player.Functions.SetMoney('bank', 0, 'moved-to-branch') end
    if Player.Functions.Save then Player.Functions.Save() end
    local moved = applyMoves(d.citizenid, moves, home)
    print(('[rsg-banking] ^2moved $%s of old bank money for %s^7'):format(moved, d.citizenid))
end

---Offline players: one-off bulk migration straight from the players table
local function migrateOffline()
    if MySQL.scalar.await("SELECT v FROM rsg_bank_meta WHERE k = 'core_migrated'") then return end
    local online = {}
    for _, P in pairs(RSGCore.Players) do online[P.PlayerData.citizenid] = true end

    local rows = MySQL.query.await('SELECT citizenid, money FROM players') or {}
    local players, total = 0, 0
    for _, row in ipairs(rows) do
        if not online[row.citizenid] then
            local money = json.decode(row.money or '{}') or {}
            local moves, home = planMove(row.citizenid, money)
            if next(moves) then
                for key in pairs(LEGACY) do money[key] = nil end
                money.bank = 0
                MySQL.update.await('UPDATE players SET money = ? WHERE citizenid = ?', { json.encode(money), row.citizenid })
                total = total + applyMoves(row.citizenid, moves, home)
                players = players + 1
            end
        end
    end
    MySQL.insert.await("INSERT INTO rsg_bank_meta (k, v) VALUES ('core_migrated', ?)", { os.date('%Y-%m-%d %H:%M:%S') })
    print(('[rsg-banking] ^2Migration done: $%s moved for %s offline characters^7'):format(round(total), players))
    BankLog('system', nil, {
        { name = 'Characters', value = tostring(players), inline = true },
        { name = 'Total moved', value = BankMoney(round(total)), inline = true },
    }, { description = 'Old RSG-Core bank money migrated to branches' })
end

CreateThread(function()
    while not BankingDBReady do Wait(500) end
    if Config.MigrateCoreMoney then
        local ok, err = pcall(migrateOffline)
        if not ok then print(('[rsg-banking] ^1Migration failed:^7 %s'):format(err)) end
    end
    if Config.MigrateCoreMoney or Config.ForwardCoreBank then
        for _, P in pairs(RSGCore.Players) do pcall(sweepOnline, P) end
    end
end)

-- sweep each character as they load in
AddEventHandler('RSGCore:Server:PlayerLoaded', function(Player)
    if not BankingDBReady or not (Config.MigrateCoreMoney or Config.ForwardCoreBank) then return end
    pcall(sweepOnline, Player)
end)

-- other scripts paying into RSG-Core 'bank' money -> forward to the home branch
AddEventHandler('RSGCore:Server:OnMoneyChange', function(src, moneytype, amount, operation, reason)
    if not Config.ForwardCoreBank or moneytype ~= 'bank' or operation ~= 'add' or not BankingDBReady then return end
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    local cid = Player.PlayerData.citizenid
    if not GetHomeBranch(cid) then return end -- stays in core bank; swept once they pick a home branch
    if Player.Functions.RemoveMoney('bank', amount, 'forward-to-branch') then
        AddHomeMoney(cid, amount, reason or 'Payment')
    end
end)

exports('GetHomeBranch', GetHomeBranch)
exports('AddHomeMoney', AddHomeMoney)
function SweepCoreBank(src)
    local P = RSGCore.Functions.GetPlayer(src); if P then sweepOnline(P) end
end
exports('SweepCoreBank', SweepCoreBank)
