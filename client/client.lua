local RSGCore = exports['rsg-core']:GetCoreObject()

local blips = {}       -- [bankId] = blip
local blipState = {}   -- [bankId] = true (open) / false (closed)
local currentBank = nil
local opening = false

local function applyNuiFocus(enable)
    if enable then
        SetNuiFocus(true, true)
        if Config.AllowPushToTalkWhileOpen then
            SetNuiFocusKeepInput(true)
        end
    else
        SetNuiFocusKeepInput(false)
        SetNuiFocus(false, false)
    end
end

local function runPttWhitelist()
    if not Config.AllowPushToTalkWhileOpen then return end
    DisableAllControlActions(0)
    DisableAllControlActions(1)
    DisableAllControlActions(2)
    local list = Config.PushToTalkControls
    if list then
        for i = 1, #list do
            local c = list[i]
            EnableControlAction(0, c, true)
            EnableControlAction(1, c, true)
            EnableControlAction(2, c, true)
        end
    end
end

local function notify(key, ntype, duration, ...)
    RSGCore.Functions.Notify({ title = locale('cl_title'), description = locale(key, ...), type = ntype, duration = duration or 5000 })
end

local function isOpen()
    if not Config.UseHours then return true end
    local h = GetClockHours()
    if Config.OpenHour < Config.CloseHour then
        return h >= Config.OpenHour and h < Config.CloseHour
    end
    return h >= Config.OpenHour or h < Config.CloseHour
end

local function closeUI()
    currentBank = nil
    applyNuiFocus(false)
    SendNUIMessage({ action = 'close' })
end

-- every ui_* locale key is sent to the NUI (built once)
local uiLocales
local function getUILocales()
    if not uiLocales then
        uiLocales = {}
        for k in pairs(locale()) do
            if k:sub(1, 3) == 'ui_' then uiLocales[k] = locale(k) end
        end
    end
    return uiLocales
end

RegisterNetEvent('rsg-banking:client:open', function(bankId)
    if currentBank or opening or not Config.Banks[bankId] then return end
    if not isOpen() then
        return notify('cl_bank_closed', 'error', 5000, Config.OpenHour, Config.CloseHour)
    end
    opening = true
    local data = RSGCore.Functions.AwaitCallback('rsg-banking:server:getData', 10000, bankId)
    opening = false
    if not data then return end
    currentBank = bankId
    applyNuiFocus(true)
    SendNUIMessage({ action = 'open', data = data, locales = getUILocales() })
end)

RegisterNUICallback('close', function(_, cb) closeUI(); cb('ok') end)

-- NUI button -> server callback (current bank is always passed first) -> refreshed data back to the UI
local function nuiAction(name, cbName, ...)
    local args = { ... }
    RegisterNUICallback(name, function(d, cb)
        if currentBank then
            local params = {}
            for i, k in ipairs(args) do params[i] = d[k] end
            local data = RSGCore.Functions.AwaitCallback(cbName, 10000, currentBank, table.unpack(params, 1, #args))
            if data and currentBank then SendNUIMessage({ action = 'update', data = data }) end
        end
        cb('ok')
    end)
end

nuiAction('openAccount',     'rsg-banking:server:openAccount')
nuiAction('setHome',         'rsg-banking:server:setHome')
nuiAction('deposit',         'rsg-banking:server:deposit',         'amount')
nuiAction('withdraw',        'rsg-banking:server:withdraw',        'amount')
nuiAction('transfer',        'rsg-banking:server:transfer',        'target', 'amount')
nuiAction('takeLoan',        'rsg-banking:server:takeLoan',        'amount')
nuiAction('repayLoan',       'rsg-banking:server:repayLoan',       'amount', 'method')
nuiAction('buyLockbox',      'rsg-banking:server:buyLockbox',      'size')
nuiAction('upgradeLockbox',  'rsg-banking:server:upgradeLockbox')
nuiAction('lockboxDeposit',  'rsg-banking:server:lockboxDeposit',  'item', 'qty')
nuiAction('lockboxWithdraw', 'rsg-banking:server:lockboxWithdraw', 'item', 'qty')

-- close the menu if the player walks away or the bank closes
CreateThread(function()
    while true do
        if currentBank then
            Wait(1000)
            local bank = currentBank and Config.Banks[currentBank] -- may have closed during the wait
            if bank and (#(GetEntityCoords(PlayerPedId()) - bank.coords) > Config.ServerMaxDistance or not isOpen()) then
                closeUI()
            end
        else
            Wait(2000)
        end
    end
end)

local function setBlipStatus(id, open)
    local blip = blips[id]
    if not blip or blipState[id] == open then return end
    if blipState[id] ~= nil then
        BlipRemoveModifier(blip, joaat(blipState[id] and Config.Blip.openColor or Config.Blip.closedColor))
    end
    BlipAddModifier(blip, joaat(open and Config.Blip.openColor or Config.Blip.closedColor))
    blipState[id] = open
end

-- Doors: main doors (state 0) follow opening hours, the rest stay locked
local doorsOpen = nil

local function registerDoors()
    for _, d in ipairs(Config.BankDoors or {}) do
        if not IsDoorRegisteredWithSystem(d.door) then
            Citizen.InvokeNative(0xD99229FE93B46286, d.door, 1, 1, 0, 0, 0, 0) -- _ADD_DOOR_TO_SYSTEM_NEW
        end
    end
end

local function setDoors(open, force)
    if doorsOpen == open and not force then return end
    for _, d in ipairs(Config.BankDoors or {}) do
        DoorSystemSetDoorState(d.door, (d.state == 0 and open) and 0 or 1)
    end
    doorsOpen = open
end

-- Which bank (if any) the player is standing inside
local function bankInside()
    local ped = PlayerPedId()
    if GetInteriorFromEntity(ped) == 0 then return nil end
    local pos = GetEntityCoords(ped)
    for id, bank in pairs(Config.Banks) do
        if #(pos - bank.coords) <= Config.Closing.insideRadius then return id end
    end
end

local function minutesToClose()
    local now = GetClockHours() * 60 + GetClockMinutes()
    return (Config.CloseHour * 60 - now) % 1440
end

-- returns true if the player was moved outside
local function escortOut(id)
    local exit = Config.Banks[id].exit
    if not exit then return false end
    local ped = PlayerPedId()
    DoScreenFadeOut(800)
    while not IsScreenFadedOut() do Wait(50) end
    SetEntityCoords(ped, exit.x, exit.y, exit.z, false, false, false, false)
    SetEntityHeading(ped, exit.w or 0.0)
    Wait(500)
    DoScreenFadeIn(800)
    notify('cl_escorted_out', 'inform', 6000)
    return true
end

local warned, closedAt = false, nil

-- Main loop: opening hours -> doors, blips, closing-time handling
CreateThread(function()
    registerDoors()
    setDoors(isOpen(), true)
    local tick = 0
    while true do
        local open = isOpen()
        local inside = Config.UseHours and bankInside() or nil

        -- Closing soon warning (once per day, only while inside a bank)
        if open and inside and Config.Closing.warnHours > 0 then
            if not warned and minutesToClose() <= Config.Closing.warnHours * 60 then
                warned = true
                notify('cl_closing_soon', 'warning', 7000, Config.CloseHour)
            end
        elseif not open then
            warned = false
        end

        -- After closing: doors stay usable for anyone still inside so they can walk out
        if not open and inside then
            if not closedAt then
                closedAt = GetGameTimer()
                notify('cl_bank_closed_leave', 'warning', 7000)
            elseif Config.Closing.escort and GetGameTimer() - closedAt >= Config.Closing.graceSeconds * 1000 then
                if escortOut(inside) then closedAt = nil end -- no exit set: keep the timer, don't re-warn
            end
        else
            closedAt = nil
        end

        local doorsShouldOpen = open or inside ~= nil
        setDoors(doorsShouldOpen)
        tick = tick + 1
        if tick >= 6 then -- periodically re-apply in case another script or streaming reset them
            tick = 0
            registerDoors()
            setDoors(doorsShouldOpen, true)
        end
        for id in pairs(blips) do setBlipStatus(id, open) end

        -- check more often while inside so doors lock soon after the player leaves
        Wait(inside and 2000 or (Config.Blip.updateInterval or 10000))
    end
end)

CreateThread(function()
    for id, bank in pairs(Config.Banks) do
        exports['rsg-core']:createPrompt('rsg_bank_' .. id, bank.coords, RSGCore.Shared.Keybinds[Config.OpenKey],
            locale('cl_open_bank', bank.label), { type = 'client', event = 'rsg-banking:client:open', args = { id } })
        if Config.Blip.enabled then
            local blip = BlipAddForCoords(1664425300, bank.coords.x, bank.coords.y, bank.coords.z)
            SetBlipSprite(blip, Config.Blip.sprite, true)
            SetBlipScale(blip, Config.Blip.scale)
            SetBlipName(blip, bank.label)
            blips[id] = blip
            setBlipStatus(id, isOpen())
        end
    end
end)

CreateThread(function()
    while true do
        if currentBank and Config.AllowPushToTalkWhileOpen then
            Wait(0)
            runPttWhitelist()
        else
            Wait(250)
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, b in pairs(blips) do RemoveBlip(b) end
    for id in pairs(Config.Banks) do exports['rsg-core']:deletePrompt('rsg_bank_' .. id) end
    applyNuiFocus(false)
end)
