local BankOpen = false
local SpawnedBankBilps = {}

-------------------------------------------------------------------------------------------
-- prompts and blips if needed
-------------------------------------------------------------------------------------------
Citizen.CreateThread(function()
    for _,v in pairs(Config.BankLocations) do
        exports['rsg-core']:createPrompt(v.id, v.coords, RSGCore.Shared.Keybinds[Config.Keybind], 'Open '..v.name, {
            type = 'client',
            event = 'rsg-banking:client:OpenBanking',
        })
        if v.showblip == true then    
            local BankingBlip = BlipAddForCoords(1664425300, v.coords)
            SetBlipSprite(BankingBlip,  joaat(v.blipsprite))
            SetBlipScale(BankingBlip, v.blipscale)
            SetBlipName(BankingBlip, v.name)
            table.insert(SpawnedBankBilps, BankingBlip)
        end
    end
end)

-- set bank door default state
Citizen.CreateThread(function()
    for _,v in pairs(Config.BankDoors) do
        AddDoorToSystemNew(v.door, 1, 1, 0, 0, 0, 0)
        DoorSystemSetDoorState(v.door, v.state)
    end
end)

-- open bank with opening hours
local OpenBank = function()
    local hour = GetClockHours()
    if (hour < Config.OpenTime) or (hour >= Config.CloseTime) then
        lib.notify({
            title = 'Bank Closed',
            description = 'come back after '..Config.OpenTime..'am',
            type = 'error',
            icon = 'fa-solid fa-building-columns',
            iconAnimation = 'shake',
            duration = 7000
        })
        return
    end
    RSGCore.Functions.TriggerCallback('rsg-banking:getBankingInformation', function(banking)
        if banking ~= nil then
            SendNUIMessage({action = "OPEN_BANK", balance = banking})
            SetNuiFocus(true, true)
            BankOpen = true
            SetTimecycleModifier('RespawnLight')
            for i = 0, 10 do SetTimecycleModifierStrength(0.1 + (i / 10)); Wait(10) end
        end
    end)
end

-- get bank hours function
local GetBankHours = function()
    local hour = GetClockHours()
    if (hour < Config.OpenTime) or (hour >= Config.CloseTime) and not Config.StoreAlwaysOpen then
        for k, v in pairs(SpawnedBankBilps) do
            -- Citizen.InvokeNative(0x662D364ABF16DE2F, v, joaat('BLIP_MODIFIER_MP_COLOR_2'))
            BlipAddModifier(v, joaat('BLIP_MODIFIER_MP_COLOR_2'))
        end
    else
        for k, v in pairs(SpawnedBankBilps) do
            -- Citizen.InvokeNative(0x662D364ABF16DE2F, v, joaat('BLIP_MODIFIER_MP_COLOR_8'))
            BlipAddModifier(v, joaat('BLIP_MODIFIER_MP_COLOR_8'))
        end
    end           
    Wait(60000) -- every min
end

-- update shop hourse every min
CreateThread(function()
    while true do
        if LocalPlayer.state.isLoggedIn then
            if Config.StoreAlwaysOpen then
            GetButcherHours()
            Wait(60000) -- every min
            end
        end
        Wait(1000)
    end
end)

-- close bank
local CloseBank = function()
    SendNUIMessage({action = "CLOSE_BANK"})
    SetNuiFocus(false, false)
    BankOpen = false
    for i = 1, 10 do SetTimecycleModifierStrength(1.0 - (i / 10)); Wait(15) end
    ClearTimecycleModifier()
end

RegisterNUICallback('CloseNUI', function()
    CloseBank()
end)

RegisterNUICallback('SafeDeposit', function()
    CloseBank()
    TriggerEvent('rsg-banking:client:safedeposit')
end)

AddEventHandler("rsg-banking:client:OpenBanking", function()
    OpenBank()
end)

RegisterNUICallback('Transact', function(data)
    TriggerServerEvent('rsg-banking:server:transact', data.type, data.amount)
end)

-- update bank balance
RegisterNetEvent('rsg-banking:client:UpdateBanking', function(newbalance)
    if not BankOpen then return end
    SendNUIMessage({action = "UPDATE_BALANCE", balance = newbalance})
end)

-- bank safe deposit box
RegisterNetEvent('rsg-banking:client:safedeposit', function()
    RSGCore.Functions.GetPlayerData(function(PlayerData)
        local cid = PlayerData.citizenid
        local ZoneTypeId = 1
        local x, y, z =  table.unpack(GetEntityCoords(cache.ped))
        local town = GetMapZoneAtCoords( x, y, z, ZoneTypeId)

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

        TriggerServerEvent("inventory:server:OpenInventory", "stash", cid..town, { maxweight = Config.StorageMaxWeight, slots = Config.StorageMaxSlots } )
        TriggerEvent("inventory:client:SetCurrentStash", cid..town)
    end)
end)
