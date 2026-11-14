-----------------------------------------------------------------------
-- Vault lockboxes: per-branch safe-deposit box for whitelisted items
-----------------------------------------------------------------------
local RSGCore = exports['rsg-core']:GetCoreObject()
local XC = Config.Lockbox or {}

-- every size in Config.Lockbox.sizes, smallest first (so custom sizes show up too)
local SIZE_ORDER = {}
for id in pairs(XC.sizes or {}) do SIZE_ORDER[#SIZE_ORDER + 1] = id end
table.sort(SIZE_ORDER, function(a, b)
    local sa, sb = XC.sizes[a], XC.sizes[b]
    if sa.capacity ~= sb.capacity then return sa.capacity < sb.capacity end
    return a < b
end)

local function itemInfo(name)
    local it = RSGCore.Shared.Items[name] or {}
    return it.label or name, it.image or (name .. '.png')
end

local RC = XC.rent or {}
local function periodDays() return math.max(1, tonumber(RC.periodDays) or 7) end

-- rent_until / now are UNIX seconds read from the database clock (so they always compare correctly)
local function getBox(cid, bankId)
    return MySQL.single.await(
        'SELECT size, upgrades, UNIX_TIMESTAMP(rent_until) AS rent_until, UNIX_TIMESTAMP(NOW()) AS now FROM rsg_bank_lockboxes WHERE citizenid = ? AND bank = ?',
        { cid, bankId })
end

local function rentPrice(box)
    local s = XC.sizes[box.size]
    return s and tonumber(s.rent) or 0
end

local function rentOverdue(box)
    return RC.enabled and box.rent_until ~= nil and tonumber(box.rent_until) < tonumber(box.now)
end

local function capacityOf(box)
    local s = XC.sizes[box.size]
    if not s then return 0 end
    local up = XC.upgrade or {}
    local extra = (box.size == up.size) and (tonumber(box.upgrades) or 0) * (up.step or 0) or 0
    return s.capacity + extra
end

local function getStored(cid, bankId)
    return MySQL.query.await(
        'SELECT item, amount FROM rsg_bank_lockbox_items WHERE citizenid = ? AND bank = ? AND amount > 0 ORDER BY item', { cid, bankId }) or {}
end

local function usedOf(stored)
    local n = 0
    for _, r in ipairs(stored) do n = n + (tonumber(r.amount) or 0) end
    return n
end

-- how many of an item the player is carrying
local function countItem(Player, name)
    return tonumber(exports['rsg-inventory']:GetItemCount(Player.PlayerData.source, name)) or 0
end

local function canUpgrade(box)
    local up = XC.upgrade
    return up and box.size == up.size and (tonumber(box.upgrades) or 0) < (up.maxSteps or 0)
end

-- take a fee from the branch vault or cash depending on Config.Lockbox.payWith
local function charge(src, Player, cid, bankId, price, reason)
    if price <= 0 then return true end
    if XC.payWith == 'cash' then
        if Player.Functions.RemoveMoney('cash', price, reason) then return true end
        Bank.notify(src, 'sv_not_enough_cash', 'error'); return false
    end
    if Bank.debit(cid, bankId, price) then return true end
    Bank.notify(src, 'sv_not_enough_balance', 'error'); return false
end

local function refund(Player, cid, bankId, price)
    if price <= 0 then return end
    if XC.payWith == 'cash' then Player.Functions.AddMoney('cash', price, 'bank-lockbox-refund')
    else Bank.credit(cid, bankId, price) end
end

-- data for the NUI
function BuildLockboxData(Player, bankId)
    if not XC.enabled then return nil end
    local cid = Player.PlayerData.citizenid
    local sizes = {}
    for _, id in ipairs(SIZE_ORDER) do
        local s = XC.sizes[id]
        if s then sizes[#sizes + 1] = { id = id, label = s.label, capacity = s.capacity, price = s.price, rent = RC.enabled and (tonumber(s.rent) or 0) or 0 } end
    end

    local data = { sizes = sizes, payWith = XC.payWith, imagePath = XC.imagePath, rentDays = RC.enabled and periodDays() or 0 }

    local carry = {}
    for name in pairs(XC.items or {}) do
        local n = countItem(Player, name)
        if n > 0 then
            local label, image = itemInfo(name)
            carry[#carry + 1] = { name = name, label = label, image = image, amount = n }
        end
    end
    table.sort(carry, function(a, b) return a.label < b.label end)
    data.carry = carry

    local allowed = {}
    for name in pairs(XC.items or {}) do allowed[#allowed + 1] = (itemInfo(name)) end
    table.sort(allowed)
    data.allowed = allowed

    local box = getBox(cid, bankId)
    if box then
        local stored = getStored(cid, bankId)
        local items = {}
        for _, r in ipairs(stored) do
            local label, image = itemInfo(r.item)
            items[#items + 1] = { name = r.item, label = label, image = image, amount = tonumber(r.amount) }
        end
        local up = XC.upgrade or {}
        data.box = {
            size = box.size, label = XC.sizes[box.size] and XC.sizes[box.size].label or box.size,
            capacity = capacityOf(box), used = usedOf(stored), items = items,
            upgrades = tonumber(box.upgrades) or 0, maxUpgrades = up.maxSteps or 0,
            canUpgrade = canUpgrade(box), upgradePrice = up.price or 0, upgradeStep = up.step or 0,
        }
        if RC.enabled and box.rent_until then
            local due = tonumber(box.rent_until)
            data.box.rent = {
                price = rentPrice(box), periodDays = periodDays(), due = due, now = tonumber(box.now),
                overdue = rentOverdue(box) and true or false, graceDays = RC.graceDays or 0,
                canPay = (due - tonumber(box.now)) < (RC.maxPrepayPeriods or 4) * periodDays() * 86400,
            }
        end
    end
    return data
end

Bank.register('rsg-banking:server:buyLockbox', function(src, bankId, size)
    return Bank.guarded(src, bankId, function(Player, cid)
        if not XC.enabled then return end
        local s = type(size) == 'string' and XC.sizes[size]
        if not s then return end
        if not Bank.hasAccount(cid, bankId) then return Bank.notify(src, 'sv_no_account', 'error') end
        if getBox(cid, bankId) then return Bank.notify(src, 'sv_lockbox_exists', 'error') end
        if not charge(src, Player, cid, bankId, s.price, 'bank-lockbox-' .. bankId) then return end

        local n = MySQL.update.await(
            'INSERT IGNORE INTO rsg_bank_lockboxes (citizenid, bank, size, rent_until) VALUES (?, ?, ?, NOW() + INTERVAL ? DAY)',
            { cid, bankId, size, periodDays() })
        if (n or 0) == 0 then
            refund(Player, cid, bankId, s.price)
            return Bank.notify(src, 'sv_lockbox_exists', 'error')
        end
        if XC.payWith ~= 'cash' then Bank.logTx(cid, bankId, 'lockbox', s.price, s.label) end
        Bank.notify(src, 'sv_lockbox_bought', 'success', s.label, Bank.money(s.price))
        BankLog('lockbox', src, {
            { name = 'Action', value = 'Lockbox rented', inline = true },
            { name = 'Branch', value = Config.Banks[bankId].label, inline = true },
            { name = 'Size', value = s.label, inline = true },
            { name = 'Price', value = BankMoney(s.price), inline = true },
        })
    end)
end)

Bank.register('rsg-banking:server:upgradeLockbox', function(src, bankId)
    return Bank.guarded(src, bankId, function(Player, cid)
        if not XC.enabled then return end
        local box = getBox(cid, bankId)
        if not box then return Bank.notify(src, 'sv_no_lockbox', 'error') end
        if not canUpgrade(box) then return Bank.notify(src, 'sv_lockbox_max', 'error') end
        if rentOverdue(box) then return Bank.notify(src, 'sv_rent_overdue_lock', 'error') end
        local up = XC.upgrade
        if not charge(src, Player, cid, bankId, up.price, 'bank-lockbox-upgrade-' .. bankId) then return end
        local n = MySQL.update.await(
            'UPDATE rsg_bank_lockboxes SET upgrades = upgrades + 1 WHERE citizenid = ? AND bank = ? AND size = ? AND upgrades < ?',
            { cid, bankId, up.size, up.maxSteps })
        if (n or 0) == 0 then
            refund(Player, cid, bankId, up.price)
            return Bank.notify(src, 'sv_lockbox_max', 'error')
        end
        box.upgrades = box.upgrades + 1
        if XC.payWith ~= 'cash' then Bank.logTx(cid, bankId, 'lockbox_up', up.price, locale('tx_lockbox_up', capacityOf(box))) end
        Bank.notify(src, 'sv_lockbox_upgraded', 'success', capacityOf(box))
        BankLog('lockbox', src, {
            { name = 'Action', value = 'Lockbox enlarged', inline = true },
            { name = 'Branch', value = Config.Banks[bankId].label, inline = true },
            { name = 'New Capacity', value = tostring(capacityOf(box)), inline = true },
            { name = 'Price', value = BankMoney(up.price), inline = true },
        })
    end)
end)

local function validQty(src, qty)
    qty = math.floor(tonumber(qty) or 0)
    if qty < 1 or qty > 100000 then Bank.notify(src, 'sv_invalid_amount', 'error'); return nil end
    return qty
end

Bank.register('rsg-banking:server:lockboxDeposit', function(src, bankId, item, qty)
    return Bank.guarded(src, bankId, function(Player, cid)
        if not XC.enabled then return end
        if type(item) ~= 'string' or not (XC.items or {})[item] or not RSGCore.Shared.Items[item] then
            return Bank.notify(src, 'sv_lockbox_not_allowed', 'error')
        end
        qty = validQty(src, qty); if not qty then return end
        local box = getBox(cid, bankId)
        if not box then return Bank.notify(src, 'sv_no_lockbox', 'error') end
        if rentOverdue(box) then return Bank.notify(src, 'sv_rent_overdue_lock', 'error') end
        local free = capacityOf(box) - usedOf(getStored(cid, bankId))
        if qty > free then return Bank.notify(src, 'sv_lockbox_full', 'error', math.max(free, 0)) end
        if countItem(Player, item) < qty then return Bank.notify(src, 'sv_lockbox_not_enough', 'error') end

        -- record it in the lockbox first, then take the item: a failure can never destroy items
        MySQL.insert.await(
            'INSERT INTO rsg_bank_lockbox_items (citizenid, bank, item, amount) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE amount = amount + VALUES(amount)',
            { cid, bankId, item, qty })
        if not exports['rsg-inventory']:RemoveItem(src, item, qty, nil, 'bank-lockbox-store') then
            MySQL.update.await('UPDATE rsg_bank_lockbox_items SET amount = amount - ? WHERE citizenid = ? AND bank = ? AND item = ? AND amount >= ?',
                { qty, cid, bankId, item, qty })
            return Bank.notify(src, 'sv_lockbox_not_enough', 'error')
        end
        local label = itemInfo(item)
        Bank.notify(src, 'sv_lockbox_stored', 'success', qty, label)
        BankLog('lockbox', src, {
            { name = 'Action', value = 'Item stored', inline = true },
            { name = 'Branch', value = Config.Banks[bankId].label, inline = true },
            { name = 'Item', value = ('%sx %s (%s)'):format(qty, label, item), inline = true },
        })
    end)
end)

Bank.register('rsg-banking:server:lockboxWithdraw', function(src, bankId, item, qty)
    return Bank.guarded(src, bankId, function(_, cid)
        if not XC.enabled or type(item) ~= 'string' or not RSGCore.Shared.Items[item] then return end
        qty = validQty(src, qty); if not qty then return end
        if not getBox(cid, bankId) then return Bank.notify(src, 'sv_no_lockbox', 'error') end

        if not exports['rsg-inventory']:CanAddItem(src, item, qty) then return Bank.notify(src, 'sv_lockbox_cant_carry', 'error') end

        local n = MySQL.update.await(
            'UPDATE rsg_bank_lockbox_items SET amount = amount - ? WHERE citizenid = ? AND bank = ? AND item = ? AND amount >= ?',
            { qty, cid, bankId, item, qty })
        if (n or 0) == 0 then return Bank.notify(src, 'sv_lockbox_not_stored', 'error') end

        if not exports['rsg-inventory']:AddItem(src, item, qty, nil, nil, 'bank-lockbox-take') then
            MySQL.update.await('UPDATE rsg_bank_lockbox_items SET amount = amount + ? WHERE citizenid = ? AND bank = ? AND item = ?',
                { qty, cid, bankId, item })
            return Bank.notify(src, 'sv_lockbox_cant_carry', 'error')
        end
        MySQL.update('DELETE FROM rsg_bank_lockbox_items WHERE citizenid = ? AND bank = ? AND item = ? AND amount <= 0', { cid, bankId, item })
        local label = itemInfo(item)
        Bank.notify(src, 'sv_lockbox_taken', 'success', qty, label)
        BankLog('lockbox', src, {
            { name = 'Action', value = 'Item withdrawn', inline = true },
            { name = 'Branch', value = Config.Banks[bankId].label, inline = true },
            { name = 'Item', value = ('%sx %s (%s)'):format(qty, label, item), inline = true },
        })
    end)
end)

---------------------------------------------------------------------
-- rent
---------------------------------------------------------------------
local rentNotified = {} -- [cid:bank] = true once the "overdue" warning has been shown

local function notifyCid(cid, key, ntype, ...)
    local P = RSGCore.Functions.GetPlayerByCitizenId(cid)
    if P then Bank.notify(P.PlayerData.source, key, ntype, ...) end
end

-- manual payment: covers one more rent period starting now (also clears any overdue state)
Bank.register('rsg-banking:server:payRent', function(src, bankId)
    return Bank.guarded(src, bankId, function(Player, cid)
        if not XC.enabled or not RC.enabled then return end
        local box = getBox(cid, bankId)
        if not box then return Bank.notify(src, 'sv_no_lockbox', 'error') end
        local ahead = (tonumber(box.rent_until) or tonumber(box.now)) - tonumber(box.now)
        if ahead >= (RC.maxPrepayPeriods or 4) * periodDays() * 86400 then return Bank.notify(src, 'sv_rent_prepaid_max', 'error') end
        local price = rentPrice(box)
        if not charge(src, Player, cid, bankId, price, 'bank-lockbox-rent-' .. bankId) then return end
        local n = MySQL.update.await(
            'UPDATE rsg_bank_lockboxes SET rent_until = GREATEST(COALESCE(rent_until, NOW()), NOW()) + INTERVAL ? DAY WHERE citizenid = ? AND bank = ?',
            { periodDays(), cid, bankId })
        if (n or 0) == 0 then refund(Player, cid, bankId, price); return Bank.notify(src, 'sv_no_lockbox', 'error') end
        rentNotified[cid .. ':' .. bankId] = nil
        if price > 0 and XC.payWith ~= 'cash' then Bank.logTx(cid, bankId, 'lockbox_rent', price, locale('tx_lockbox_rent')) end
        Bank.notify(src, 'sv_rent_paid', 'success', periodDays())
        BankLog('lockbox', src, {
            { name = 'Action', value = 'Rent paid', inline = true },
            { name = 'Branch', value = Config.Banks[bankId].label, inline = true },
            { name = 'Price', value = BankMoney(price), inline = true },
        })
    end)
end)

local function evict(cid, bankId, label)
    local items = tonumber(MySQL.scalar.await(
        'SELECT COALESCE(SUM(amount), 0) FROM rsg_bank_lockbox_items WHERE citizenid = ? AND bank = ?', { cid, bankId })) or 0
    MySQL.update.await('DELETE FROM rsg_bank_lockbox_items WHERE citizenid = ? AND bank = ?', { cid, bankId })
    MySQL.update.await('DELETE FROM rsg_bank_lockboxes WHERE citizenid = ? AND bank = ?', { cid, bankId })
    rentNotified[cid .. ':' .. bankId] = nil
    notifyCid(cid, 'sv_rent_evicted', 'error', label)
    BankLog('lockbox', nil, {
        { name = 'Action', value = 'Lockbox cleared for unpaid rent', inline = true },
        { name = 'Citizen ID', value = cid, inline = true },
        { name = 'Branch', value = label, inline = true },
        { name = 'Items forfeited', value = tostring(items), inline = true },
    })
    TriggerEvent('rsg-banking:server:lockboxEvicted', cid, bankId, items) -- hook for other resources
end

local function processRent()
    -- boxes from before rent existed start their first period now
    MySQL.update.await('UPDATE rsg_bank_lockboxes SET rent_until = NOW() + INTERVAL ? DAY WHERE rent_until IS NULL', { periodDays() })
    local rows = MySQL.query.await(
        'SELECT citizenid, bank, size, UNIX_TIMESTAMP(rent_until) AS due, UNIX_TIMESTAMP(NOW()) AS now FROM rsg_bank_lockboxes WHERE rent_until < NOW()') or {}
    for _, r in ipairs(rows) do
        local cid, bankId = r.citizenid, r.bank
        local label = Config.Banks[bankId] and Config.Banks[bankId].label or bankId
        local key = cid .. ':' .. bankId
        local price = rentPrice(r)
        if price <= 0 then
            MySQL.update.await('UPDATE rsg_bank_lockboxes SET rent_until = NOW() + INTERVAL ? DAY WHERE citizenid = ? AND bank = ?', { periodDays(), cid, bankId })
        elseif Bank.debit(cid, bankId, price) then
            MySQL.update.await('UPDATE rsg_bank_lockboxes SET rent_until = rent_until + INTERVAL ? DAY WHERE citizenid = ? AND bank = ?', { periodDays(), cid, bankId })
            Bank.logTx(cid, bankId, 'lockbox_rent', price, locale('tx_lockbox_rent_auto'))
            rentNotified[key] = nil
            notifyCid(cid, 'sv_rent_auto', 'inform', Bank.money(price), label)
            BankLog('lockbox', nil, {
                { name = 'Action', value = 'Rent collected from vault', inline = true },
                { name = 'Citizen ID', value = cid, inline = true },
                { name = 'Branch', value = label, inline = true },
                { name = 'Rent', value = BankMoney(price), inline = true },
            })
        elseif tonumber(r.now) > tonumber(r.due) + (RC.graceDays or 3) * 86400 then
            evict(cid, bankId, label)
        elseif not rentNotified[key] then
            rentNotified[key] = true
            notifyCid(cid, 'sv_rent_overdue', 'error', label, RC.graceDays or 3)
        end
    end
end

CreateThread(function()
    if not XC.enabled or not RC.enabled then return end
    while not BankingDBReady do Wait(1000) end
    while true do
        local ok, err = pcall(processRent)
        if not ok then print(('[rsg-banking] ^1lockbox rent error:^7 %s'):format(err)) end
        Wait(math.max(1, RC.checkInterval or 30) * 60000)
    end
end)

---------------------------------------------------------------------
-- exports
---------------------------------------------------------------------
exports('GetLockboxItems', function(citizenid, bankId)
    local out = {}
    for _, r in ipairs(getStored(citizenid, bankId)) do out[r.item] = tonumber(r.amount) end
    return out
end)
