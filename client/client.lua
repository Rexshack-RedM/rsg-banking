local RSGCore = exports['rsg-core']:GetCoreObject()
lib.locale()

local blips = {}       -- [bankId] = blip
local blipState = {}   -- [bankId] = true (open) / false (closed)
local currentBank = nil

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
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

-- every UI string is sent to the NUI from the active ox_lib locale
local UI_KEYS = {
    'ui_vault', 'ui_close', 'ui_bank', 'ui_customer', 'ui_no_account_title', 'ui_no_account_desc', 'ui_open_account',
    'ui_branch_vault', 'ui_cash_on_hand', 'ui_tab_teller', 'ui_tab_wire', 'ui_tab_branches', 'ui_tab_ledger',
    'ui_amount', 'ui_all_cash', 'ui_all_vault', 'ui_deposit', 'ui_withdraw', 'ui_no_other_title', 'ui_no_other_desc',
    'ui_wire_desc', 'ui_send_wire', 'ui_fee_info', 'ui_opening_fee', 'ui_free_to_open', 'ui_tx_deposit', 'ui_tx_withdraw',
    'ui_tx_wire_in', 'ui_tx_wire_out', 'ui_tx_opened', 'ui_branch_no_account', 'ui_branch_here', 'ui_branch_visit',
    'ui_pill_here', 'ui_free', 'ui_no_transactions', 'ui_pill_home', 'ui_make_home', 'ui_home_hint',
}
local uiLocales

local function getUILocales()
    if not uiLocales then
        uiLocales = {}
        for _, k in ipairs(UI_KEYS) do uiLocales[k] = locale(k) end
    end
    return uiLocales
end

local function pushData(data)
    if data then SendNUIMessage({ action = 'update', data = data }) end
end

RegisterNetEvent('rsg-banking:client:open', function(bankId)
    if currentBank or not Config.Banks[bankId] then return end
    if not isOpen() then
        lib.notify({ title = locale('cl_title'), description = locale('cl_bank_closed', Config.OpenHour, Config.CloseHour), type = 'error', duration = 5000 })
        return
    end
    local data = lib.callback.await('rsg-banking:server:getData', false, bankId)
    if not data then return end
    currentBank = bankId
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = data, locales = getUILocales() })
end)

RegisterNUICallback('close', function(_, cb) closeUI(); cb('ok') end)

RegisterNUICallback('openAccount', function(_, cb)
    if currentBank then pushData(lib.callback.await('rsg-banking:server:openAccount', false, currentBank)) end
    cb('ok')
end)

RegisterNUICallback('setHome', function(_, cb)
    if currentBank then pushData(lib.callback.await('rsg-banking:server:setHome', false, currentBank)) end
    cb('ok')
end)

RegisterNUICallback('deposit', function(d, cb)
    if currentBank then pushData(lib.callback.await('rsg-banking:server:deposit', false, currentBank, d.amount)) end
    cb('ok')
end)

RegisterNUICallback('withdraw', function(d, cb)
    if currentBank then pushData(lib.callback.await('rsg-banking:server:withdraw', false, currentBank, d.amount)) end
    cb('ok')
end)

RegisterNUICallback('transfer', function(d, cb)
    if currentBank then pushData(lib.callback.await('rsg-banking:server:transfer', false, currentBank, d.target, d.amount)) end
    cb('ok')
end)

-- close the menu if the player walks away or the bank closes
CreateThread(function()
    while true do
        if currentBank then
            Wait(1000)
            local dist = #(GetEntityCoords(cache.ped) - Config.Banks[currentBank].coords)
            if dist > Config.ServerMaxDistance or not isOpen() then closeUI() end
        else
            Wait(2000)
        end
    end
end)

local function setBlipStatus(id, open)
    local blip = blips[id]
    if not blip or blipState[id] == open then return end
    if blipState[id] ~= nil then
        local old = blipState[id] and Config.Blip.openColor or Config.Blip.closedColor
        Citizen.InvokeNative(0xB059D7BD3D78C16F, blip, joaat(old)) -- BlipRemoveModifier
    end
    local new = open and Config.Blip.openColor or Config.Blip.closedColor
    Citizen.InvokeNative(0x662D364ABF16DE2F, blip, joaat(new))     -- BlipAddModifier
    blipState[id] = open
end

-- Doors: main doors (state 0) follow opening hours, the rest stay locked
local doorsOpen = nil

local function registerDoors()
    for _, d in ipairs(Config.BankDoors or {}) do
        if not Citizen.InvokeNative(0xC153C43EA202C8C1, d.door) then           -- IsDoorRegisteredWithSystem
            Citizen.InvokeNative(0xD99229FE93B46286, d.door, 1, 1, 0, 0, 0, 0)  -- AddDoorToSystemNew
        end
    end
end

local function setDoors(open, force)
    if doorsOpen == open and not force then return end
    for _, d in ipairs(Config.BankDoors or {}) do
        local state = (d.state == 0 and open) and 0 or 1
        Citizen.InvokeNative(0x6BAB9442830C7F53, d.door, state)                 -- DoorSystemSetDoorState
    end
    doorsOpen = open
end

-- Which bank (if any) the player is standing inside
local function bankInside()
    local ped = cache.ped
    if GetInteriorFromEntity(ped) == 0 then return nil end
    local pos = GetEntityCoords(ped)
    for id, bank in pairs(Config.Banks) do
        if #(pos - bank.coords) <= Config.Closing.insideRadius then return id end
    end
end

local function minutesToClose()
    local now = GetClockHours() * 60 + GetClockMinutes()
    local close = Config.CloseHour * 60
    return (close - now) % 1440
end

local function escortOut(id)
    local exit = Config.Banks[id].exit
    if not exit then return end
    DoScreenFadeOut(800)
    while not IsScreenFadedOut() do Wait(50) end
    SetEntityCoords(cache.ped, exit.x, exit.y, exit.z, false, false, false, false)
    SetEntityHeading(cache.ped, exit.w or 0.0)
    Wait(500)
    DoScreenFadeIn(800)
    lib.notify({ title = locale('cl_title'), description = locale('cl_escorted_out'), type = 'inform', duration = 6000 })
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
                lib.notify({ title = locale('cl_title'), description = locale('cl_closing_soon', Config.CloseHour), type = 'warning', duration = 7000 })
            end
        elseif open == false then
            warned = false
        end

        -- After closing: doors stay usable for anyone still inside so they can walk out
        if not open and inside then
            if not closedAt then
                closedAt = GetGameTimer()
                lib.notify({ title = locale('cl_title'), description = locale('cl_bank_closed_leave'), type = 'warning', duration = 7000 })
            elseif Config.Closing.escort and GetGameTimer() - closedAt >= Config.Closing.graceSeconds * 1000 then
                escortOut(inside)
                closedAt = nil
            end
        else
            closedAt = nil
        end

        local doorsShouldOpen = open or inside ~= nil
        setDoors(doorsShouldOpen)
        tick = tick + 1
        if tick >= 6 then           -- periodically re-apply in case another script or streaming reset them
            tick = 0
            registerDoors()
            setDoors(doorsShouldOpen, true)
        end
        for id in pairs(blips) do setBlipStatus(id, open) end

        -- check more often while someone is inside a closed bank so doors lock soon after they leave
        Wait(inside and 2000 or (Config.Blip.updateInterval or 10000))
    end
end)

CreateThread(function()
    for id, bank in pairs(Config.Banks) do
        exports['rsg-core']:createPrompt('rsg_bank_' .. id, bank.coords, RSGCore.Shared.Keybinds[Config.OpenKey],
            locale('cl_open_bank', bank.label), {
                type = 'client', event = 'rsg-banking:client:open', args = { id },
            })
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

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, b in pairs(blips) do RemoveBlip(b) end
    for id in pairs(Config.Banks) do exports['rsg-core']:deletePrompt('rsg_bank_' .. id) end
    SetNuiFocus(false, false)
end)
