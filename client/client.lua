local RSGCore = exports['rsg-core']:GetCoreObject()
local BankOpen = false
local SpawnedBankBlips = {}
lib.locale()

---------------------------------
-- prompts and blips if needed
---------------------------------
CreateThread(function()
    for _,v in pairs(Config.BankLocations) do
        if not Config.UseTarget then
            exports['rsg-core']:createPrompt(v.bankid, v.coords, RSGCore.Shared.Keybinds[Config.Keybind], locale('cl_lang_1'), {
                type = 'client',
                event = 'rsg-banking:client:OpenBanking',
                args = { v.moneytype },
            })
        end
        if v.showblip == true then
            local BankBlip = BlipAddForCoords(1664425300, v.coords)
            SetBlipSprite(BankBlip, joaat(v.blipsprite), true)
            SetBlipScale(BankBlip, v.blipscale)
            SetBlipName(BankBlip, v.name)
            table.insert(SpawnedBankBlips, BankBlip)
        end
    end
end)

---------------------------------
-- set bank door default state
---------------------------------
CreateThread(function()
    for _,v in pairs(Config.BankDoors) do
        AddDoorToSystemNew(v.door, 1, 1, 0, 0, 0, 0)
        DoorSystemSetDoorState(v.door, v.state)
    end
end)

---------------------------------
-- open bank with opening hours
---------------------------------
local OpenBank = function(moneytype)
    if not Config.AlwaysOpen then
        local hour = GetClockHours()
        if (hour < Config.OpenTime) or (hour >= Config.CloseTime) then
            lib.notify({ title = locale('cl_lang_2'), description = locale('cl_lang_3') .. ' ' .. Config.OpenTime .. ' ' .. locale('cl_lang_4'), type = 'error', icon = 'fa-solid fa-building-columns', iconAnimation = 'shake', duration = 7000 })
            return
        end
    end
    RSGCore.Functions.TriggerCallback('rsg-banking:getBankingInformation', function(banking)
        if banking ~= nil then
            SendNUIMessage({action = "OPEN_BANK", balance = banking.bank, cash = banking.cash, id = moneytype, withdrawChargeRate = Config.WithdrawChargeRate or 0})
            SetNuiFocus(true, true)
            BankOpen = true
            SetTimecycleModifier('RespawnLight')
            for i=0, 10 do SetTimecycleModifierStrength(0.1 + (i / 10)); Wait(10) end
        end
    end, moneytype)
end

---------------------------------
-- get bank hours function
---------------------------------
local GetBankHours = function()
    local hour = GetClockHours()
    if not Config.AlwaysOpen then
        if (hour < Config.OpenTime) or (hour >= Config.CloseTime) then
            for k, v in pairs(SpawnedBankBlips) do
                BlipAddModifier(v, joaat('BLIP_MODIFIER_MP_COLOR_2'))
            end
        else
            for k, v in pairs(SpawnedBankBlips) do
                BlipAddModifier(v, joaat('BLIP_MODIFIER_MP_COLOR_8'))
            end
        end
    else
        for k, v in pairs(SpawnedBankBlips) do
            BlipAddModifier(v, joaat('BLIP_MODIFIER_MP_COLOR_8'))
        end
    end
end

---------------------------------
-- get bank hours on player loading
---------------------------------
RegisterNetEvent('RSGCore:Client:OnPlayerLoaded', function()
    GetBankHours()
end)

---------------------------------
-- update bank hours every min
---------------------------------
CreateThread(function()
    while true do
        GetBankHours()
        Wait(60000) -- every min
    end
end)

---------------------------------
-- close bank
---------------------------------
local CloseBank = function()
    SendNUIMessage({action = "CLOSE_BANK"})
    SetNuiFocus(false, false)
    BankOpen = false
    for i=1, 10 do SetTimecycleModifierStrength(1.0 - (i / 10)); Wait(15) end
    ClearTimecycleModifier()
end

---------------------------------
-- NUI stuff
---------------------------------
RegisterNUICallback('CloseNUI', function()
    CloseBank()
end)

RegisterNUICallback('SafeDeposit', function()
    CloseBank()
    TriggerEvent('rsg-banking:client:safedeposit')
end)

AddEventHandler('rsg-banking:client:OpenBanking', function(moneytype)
    OpenBank(moneytype)
end)

RegisterNUICallback('Transact', function(data)
    TriggerServerEvent('rsg-banking:server:transact', data.type, data.amount, data.id)
end)

---------------------------------
-- update bank balance
---------------------------------
RegisterNetEvent('rsg-banking:client:UpdateBanking', function(newbalance, moneytype)
    if not BankOpen then return end
    local Player = RSGCore.Functions.GetPlayerData()
    local cash = Player.money['cash']
    SendNUIMessage({action = "UPDATE_BALANCE", balance = newbalance, cash = cash, id = moneytype})
end)

---------------------------------
-- bank safe deposit box
---------------------------------
RegisterNetEvent('rsg-banking:client:safedeposit', function()
    local ZoneTypeId = 1
    local x,y,z =  table.unpack(GetEntityCoords(cache.ped))
    local town = GetMapZoneAtCoords(x,y,z, ZoneTypeId)

    if town == -744494798 then
        town = 'Armadillo'
    end
    if town == 1053078005 then
        town = 'Blackwater'
    end
    if town == 2046780049 then
        town = 'Rhodes'
    end
    if town == -765540529 then
        town = 'SaintDenis'
    end
    if town == 459833523 then
        town = 'Valentine'
    end

    TriggerServerEvent('rsg-banking:server:opensafedeposit', town)
end)

---------------------------------
-- target to give player cash
---------------------------------
exports['ox_target']:addGlobalPlayer({
    {
        name = 'give_money',
        label = locale('cl_lang_5'),
        icon = 'fas fa-money-bill-wave',
        onSelect = function(data)
            local targetEntity = data.entity
            if IsEntityAPed(targetEntity) and IsPedAPlayer(targetEntity) then
                local targetPlayerIndex = NetworkGetPlayerIndexFromPed(targetEntity)
                local targetServerId = GetPlayerServerId(targetPlayerIndex)
            
                if targetServerId and targetServerId > 0 then
                    OpenGiveMoneyMenu(targetServerId)
                else
                    lib.notify({ title = locale('cl_lang_6'), type = 'error' })
                end
            else
                lib.notify({ title = locale('cl_lang_7'), type = 'error' })
            end
        end,
    },
}, 1.0)

---------------------------------
-- target give money input form
---------------------------------
function OpenGiveMoneyMenu(targetPlayerId)
    local input = lib.inputDialog(locale('cl_lang_8')..targetPlayerId, {
        {
            type = 'number',
            label = locale('cl_lang_9'),
        },
    })
    if input then
        local amount = tonumber(input[1])

        if amount and amount > 0 then
            TriggerServerEvent('rsg-banking:server:givemoney', targetPlayerId, amount)
        else
            lib.notify({ title = locale('cl_lang_10'), type = 'error' })
        end
    end
end
