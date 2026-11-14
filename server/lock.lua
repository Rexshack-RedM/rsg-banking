-----------------------------------------------------------------------
-- Branch lockdown
-- Other resources (e.g. rsg-bankrobbery) lock a branch while it is being robbed.
-- A locked branch refuses every banking action and closes open menus.
--   exports['rsg-banking']:LockBranch(bankId, seconds, reason)   -- seconds optional, capped at Config.Lock.maxSeconds
--   exports['rsg-banking']:UnlockBranch(bankId)
--   exports['rsg-banking']:IsBranchLocked(bankId)
-- Server-side event equivalents (cannot be triggered by clients):
--   TriggerEvent('rsg-banking:server:lockBranch', bankId, seconds, reason)
--   TriggerEvent('rsg-banking:server:unlockBranch', bankId)
-----------------------------------------------------------------------
local LK = Config.Lock or {}
local locks = {} -- [bankId] = os.time() expiry

local function broadcast(bankId, locked)
    TriggerClientEvent('rsg-banking:client:branchLock', -1, bankId, locked)
end

function IsBranchLocked(bankId)
    if not LK.enabled or type(bankId) ~= 'string' then return false end
    local expires = locks[bankId]
    if not expires then return false end
    if os.time() >= expires then
        locks[bankId] = nil
        broadcast(bankId, false)
        return false
    end
    return true
end

function LockBranch(bankId, seconds, reason)
    if not LK.enabled or type(bankId) ~= 'string' or not Config.Banks[bankId] then return false end
    local maxS = math.max(1, tonumber(LK.maxSeconds) or 1800)
    seconds = tonumber(seconds) or maxS
    if seconds <= 0 or seconds > maxS then seconds = maxS end
    locks[bankId] = os.time() + math.floor(seconds)
    broadcast(bankId, true)
    BankLog('system', nil, {
        { name = 'Branch', value = Config.Banks[bankId].label, inline = true },
        { name = 'Seconds', value = tostring(math.floor(seconds)), inline = true },
        { name = 'Resource', value = GetInvokingResource() or 'unknown', inline = true },
        { name = 'Reason', value = tostring(reason or 'n/a'), inline = false },
    }, { description = 'Branch locked down' })
    return true
end

function UnlockBranch(bankId)
    if type(bankId) ~= 'string' or not locks[bankId] then return false end
    locks[bankId] = nil
    broadcast(bankId, false)
    BankLog('system', nil, { { name = 'Branch', value = tostring(Config.Banks[bankId] and Config.Banks[bankId].label or bankId), inline = true } },
        { description = 'Branch lockdown lifted' })
    return true
end

-- expire locks even when nobody is using the bank
CreateThread(function()
    while true do
        Wait(5000)
        for id in pairs(locks) do IsBranchLocked(id) end
    end
end)

-- clients ask for the current locks when they start
Bank.register('rsg-banking:server:getLocks', function()
    local out = {}
    for id in pairs(locks) do if IsBranchLocked(id) then out[#out + 1] = id end end
    return out
end)

AddEventHandler('rsg-banking:server:lockBranch', function(bankId, seconds, reason) LockBranch(bankId, seconds, reason) end)
AddEventHandler('rsg-banking:server:unlockBranch', function(bankId) UnlockBranch(bankId) end)

exports('LockBranch', LockBranch)
exports('UnlockBranch', UnlockBranch)
exports('IsBranchLocked', IsBranchLocked)
