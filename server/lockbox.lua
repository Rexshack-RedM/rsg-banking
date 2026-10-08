-----------------------------------------------------------------------
-- Vault lockboxes: per-branch safe-deposit box for whitelisted items
-----------------------------------------------------------------------
local RSGCore = exports['rsg-core']:GetCoreObject()
local XC = Config.Lockbox or {}
local SIZE_ORDER = { 'small', 'medium', 'large' }

local function itemInfo(name)
    local it = RSGCore.Shared.Items[name] or {}
    return it.label or name, it.image or (name .. '.png')
end

local function getBox(cid, bankId)
    return MySQL.single.await('SELECT size, upgrades FROM rsg_bank_lockboxes WHERE citizenid = ? AND bank = ?', { cid, bankId })
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
    local n = 0
    for _, it in pairs(Player.PlayerData.items or {}) do
        if it and it.name == name then n = n + (tonumber(it.amount) or 0) end
    end
    return n
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

local function itemBox(src, name, kind, amount)
    local it = RSGCore.Shared.Items[name]
    if it then TriggerClientEvent('rsg-inventory:client:ItemBox', src, it, kind, amount) end
end

-- data for the NUI
function BuildLockboxData(Player, bankId)
    if not XC.enabled then return nil end
    local cid = Player.PlayerData.citizenid
    local sizes = {}
    for _, id in ipairs(SIZE_ORDER) do
        local s = XC.sizes[id]
        if s then sizes[#sizes + 1] = { id = id, label = s.label, capacity = s.capacity, price = s.price } end
    end

    local data = { sizes = sizes, payWith = XC.payWith, imagePath = XC.imagePath }

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
    end
    return data
end

lib.callback.register('rsg-banking:server:buyLockbox', function(src, bankId, size)
    return Bank.guarded(src, bankId, function(Player, cid)
        if not XC.enabled then return end
        local s = type(size) == 'string' and XC.sizes[size]
        if not s then return end
        if not Bank.hasAccount(cid, bankId) then return Bank.notify(src, 'sv_no_account', 'error') end
        if getBox(cid, bankId) then return Bank.notify(src, 'sv_lockbox_exists', 'error') end
        if not charge(src, Player, cid, bankId, s.price, 'bank-lockbox-' .. bankId) then return end

        local n = MySQL.update.await('INSERT IGNORE INTO rsg_bank_lockboxes (citizenid, bank, size) VALUES (?, ?, ?)', { cid, bankId, size })
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

lib.callback.register('rsg-banking:server:upgradeLockbox', function(src, bankId)
    return Bank.guarded(src, bankId, function(Player, cid)
        if not XC.enabled then return end
        local box = getBox(cid, bankId)
        if not box then return Bank.notify(src, 'sv_no_lockbox', 'error') end
        if not canUpgrade(box) then return Bank.notify(src, 'sv_lockbox_max', 'error') end
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

lib.callback.register('rsg-banking:server:lockboxDeposit', function(src, bankId, item, qty)
    return Bank.guarded(src, bankId, function(Player, cid)
        if not XC.enabled then return end
        if type(item) ~= 'string' or not (XC.items or {})[item] or not RSGCore.Shared.Items[item] then
            return Bank.notify(src, 'sv_lockbox_not_allowed', 'error')
        end
        qty = validQty(src, qty); if not qty then return end
        local box = getBox(cid, bankId)
        if not box then return Bank.notify(src, 'sv_no_lockbox', 'error') end
        local free = capacityOf(box) - usedOf(getStored(cid, bankId))
        if qty > free then return Bank.notify(src, 'sv_lockbox_full', 'error', math.max(free, 0)) end
        if countItem(Player, item) < qty then return Bank.notify(src, 'sv_lockbox_not_enough', 'error') end
        if not exports['rsg-inventory']:RemoveItem(src, item, qty, nil, 'bank-lockbox-store') then return Bank.notify(src, 'sv_lockbox_not_enough', 'error') end

        MySQL.insert.await(
            'INSERT INTO rsg_bank_lockbox_items (citizenid, bank, item, amount) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE amount = amount + VALUES(amount)',
            { cid, bankId, item, qty })
        itemBox(src, item, 'remove', qty)
        local label = itemInfo(item)
        Bank.notify(src, 'sv_lockbox_stored', 'success', qty, label)
        BankLog('lockbox', src, {
            { name = 'Action', value = 'Item stored', inline = true },
            { name = 'Branch', value = Config.Banks[bankId].label, inline = true },
            { name = 'Item', value = ('%sx %s (%s)'):format(qty, label, item), inline = true },
        })
    end)
end)

lib.callback.register('rsg-banking:server:lockboxWithdraw', function(src, bankId, item, qty)
    return Bank.guarded(src, bankId, function(Player, cid)
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
        itemBox(src, item, 'add', qty)
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
-- exports
---------------------------------------------------------------------
exports('GetLockboxItems', function(citizenid, bankId)
    local out = {}
    for _, r in ipairs(getStored(citizenid, bankId)) do out[r.item] = tonumber(r.amount) end
    return out
end)
