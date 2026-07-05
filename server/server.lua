local RSGCore = exports['rsg-core']:GetCoreObject()
local banking = nil
lib.locale()
math = lib.math
local SendDiscordWebhook = require('server.discord_webhook')

local rateLimits = {}
local function isRateLimited(source, eventType)
    local maxCalls = Config.RateLimitMaxCalls
    local windowSec = Config.RateLimitWindowSec
    if not rateLimits[source] then rateLimits[source] = {} end
    if not rateLimits[source][eventType] then rateLimits[source][eventType] = {} end
    local now = os.time()
    local window = rateLimits[source][eventType]
    for i = #window, 1, -1 do
        if now - window[i] > windowSec then
            table.remove(window, i)
        end
    end
    if #window >= maxCalls then
        print(('[%s] Rate limit exceeded for player %s on %s'):format(GetCurrentResourceName(), source, eventType))
        return true
    end
    window[#window + 1] = now
    return false
end

local function isValidMoneyType(moneytype)
    for _, v in ipairs(Config.BankLocations) do
        if v.moneytype == moneytype then return true end
    end
    return false
end

local ValidTowns = { Armadillo = true, Blackwater = true, Rhodes = true, SaintDenis = true, Valentine = true }
local function isValidTown(town)
    return ValidTowns[town] == true
end

---------------
-- stash
----------------
RegisterNetEvent('rsg-banking:server:opensafedeposit', function(town)
    local src = source
    if isRateLimited(src, 'opensafedeposit') then return end
    if not isValidTown(town) then
        print(('[%s] Player %s attempted to open invalid town: %s'):format(GetCurrentResourceName(), src, town))
        return
    end
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    local data = { label = locale('sv_lang'), maxweight = Config.StorageMaxWeight, slots = Config.StorageMaxSlots }
    local citizenId = Player.PlayerData.citizenid
    local stashName = 'safedeposit_' .. citizenId .. town
    exports['rsg-inventory']:OpenInventory(src, stashName, data)
end)

---------------------------------
-- callback for bank balance
---------------------------------
RSGCore.Functions.CreateCallback('rsg-banking:getBankingInformation', function(source, cb, moneytype)

    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player then return cb(nil) end
    if not isValidMoneyType(moneytype) then
        print(('[%s] Player %s attempted to access invalid moneytype: %s'):format(GetCurrentResourceName(), source, moneytype))
        return cb(nil)
    end

    local banking = nil
    local cash = Player.Functions.GetMoney('cash')
    if Player.PlayerData.money[moneytype] then
        banking = Player.PlayerData.money[moneytype]
    end

    cb({bank = banking, cash = cash})
end)

---------------------------------
-- deposit & withdraw
---------------------------------
RegisterNetEvent('rsg-banking:server:transact', function(type, amount, moneytype)
    local src = source
    if isRateLimited(src, 'transact') then return end
    if not isValidMoneyType(moneytype) then
        print(('[%s] Player %s attempted to transact with invalid moneytype: %s'):format(GetCurrentResourceName(), src, moneytype))
        return
    end
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    local currentCash = Player.Functions.GetMoney('cash')
    local currentBank = Player.Functions.GetMoney(moneytype)

    amount = math.round(amount, 2)
    if amount <= 0 then
        lib.notify(src, {title = locale('sv_lang_1'), type = 'error'})
        print(('[%s] Player %s attempted transaction with invalid amount: %s'):format(GetCurrentResourceName(), src, amount))
        return
    end

    if type == 1 then
        if amount > Config.MaxWithdraw then
            lib.notify(src, {title = locale('sv_lang_1'), type = 'error'})
            print(('[%s] Player %s exceeded max withdraw amount: %s > %s'):format(GetCurrentResourceName(), src, amount, Config.MaxWithdraw))
            return
        end
        local bankRemove = amount
        if Config.WithdrawChargeRate and Config.WithdrawChargeRate > 0 then
            local charge = amount * (Config.WithdrawChargeRate / 100)
            bankRemove = math.round(amount + charge, 2)
        end

        if currentBank >= bankRemove then
            Player.Functions.RemoveMoney(moneytype, bankRemove, 'bank-withdraw')
            Player.Functions.AddMoney('cash', amount, 'bank-withdraw')
            local newBankBalance = Player.Functions.GetMoney(moneytype)
            TriggerClientEvent('rsg-banking:client:UpdateBanking', src, newBankBalance, moneytype)
            if Config.Discord.TrackWithdrawals and amount >= Config.Discord.TransactionThreshold then
                local playerName = Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname
                SendDiscordWebhook(playerName, "Bank (" .. moneytype .. ")", amount, "Withdrawal")
            end
        else
            lib.notify(src, {title = locale('sv_lang_2'), type = 'error'})
            print(('[%s] Player %s insufficient bank funds for withdraw of %s'):format(GetCurrentResourceName(), src, bankRemove))
        end
        return
    end

    if type == 2 then
        if amount > Config.MaxDeposit then
            lib.notify(src, {title = locale('sv_lang_1'), type = 'error'})
            print(('[%s] Player %s exceeded max deposit amount: %s > %s'):format(GetCurrentResourceName(), src, amount, Config.MaxDeposit))
            return
        end
        if currentCash >= amount then
            Player.Functions.RemoveMoney('cash', amount, 'bank-deposit')
            Player.Functions.AddMoney(moneytype, amount, 'bank-deposit')
            local newBankBalance = Player.Functions.GetMoney(moneytype)
            TriggerClientEvent('rsg-banking:client:UpdateBanking', src, newBankBalance, moneytype)
            if Config.Discord.TrackDeposits and amount >= Config.Discord.TransactionThreshold then
                local playerName = Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname
                SendDiscordWebhook(playerName, "Bank (" .. moneytype .. ")", amount, "Deposit")
            end
        else
            lib.notify(src, {title = locale('sv_lang_2'), type = 'error'})
            print(('[%s] Player %s insufficient cash for deposit of %s'):format(GetCurrentResourceName(), src, amount))
        end
        return
    end

    if type == 3 then
        if amount > Config.MaxMoneyClip then
            lib.notify(src, {title = locale('sv_lang_1'), type = 'error'})
            print(('[%s] Player %s exceeded max money clip amount: %s > %s'):format(GetCurrentResourceName(), src, amount, Config.MaxMoneyClip))
            return
        end
        if currentBank >= amount then
            local info = { money = amount }
            Player.Functions.RemoveMoney(moneytype, amount, 'bank-money_clip')
            Player.Functions.AddItem('money_clip', 1, false, info)
            local newBankBalance = Player.Functions.GetMoney(moneytype)
            TriggerClientEvent('rsg-banking:client:UpdateBanking', src, newBankBalance, moneytype)
            lib.notify(src, { title = locale('sv_lang_9'), description = locale('sv_lang_10') .. ' ' .. amount .. ' ' .. locale('sv_lang_11'), type = 'success' })
            if Config.Discord.TrackMoneyClips and amount >= Config.Discord.TransactionThreshold then
                local playerName = Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname
                SendDiscordWebhook(playerName, "Money Clip", amount, "Money Clip Created")
            end
        else
            lib.notify(src, {title = locale('sv_lang_2'), type = 'error'})
            print(('[%s] Player %s insufficient bank funds for money clip of %s'):format(GetCurrentResourceName(), src, amount))
        end
        return
    end

end)

if Config.UseGMInventory then
    RegisterNetEvent("rsg-banking:server:getMoneyClip", function(input)
        local src = source
        input = tonumber(input) -- Convert input to a number

        if not input or input <= 0 then
            lib.notify(src, {title = locale('sv_lang_27'), type = 'error'})
            return
        end

        local Player = RSGCore.Functions.GetPlayer(src)
        local charName = Player.PlayerData.charinfo.firstname.. ' ' .. Player.PlayerData.charinfo.lastname

        if not Player then return end

        local money = Player.Functions.GetMoney('cash')

        if money and money >= input then
            if exports.gm_inventory:CanCarryItem(src, "money_clip", 1) then
                if Player.Functions.RemoveMoney('cash', input, 'give-money') then
                    local info =
                    {
                        money = input
                    }

                    TriggerEvent('rsg-log:server:CreateLog', 'create-money-clip', 'Create Own Money Clip', 'green',
                        '**Player name**: ' .. GetPlayerName(src) ..
                        "\n **Character Name:** " .. charName ..
                        '\n **Player ID**: ' .. src ..
                        "\n **Amount**: " .. string.format("%.2f", input)
                    , false)
                    Player.Functions.AddItem('money_clip', 1, false, info)
                    lib.notify(src, {title = locale('sv_lang_28') .. string.format("%.2f", input) .. locale('sv_lang_29'), type = 'success'})
                    TriggerClientEvent("rsg-banking:client:closeInventory", src)
                end
            else
                TriggerClientEvent('RSGCore:Notify', src, "Your inventory is full", 'warning', 4500)
            end
        end
    end)

    RegisterNetEvent("rsg-banking:server:getOthersMoneyClip", function(id, input)
        local src = source
        local id = id
        input = tonumber(input) -- Convert input to a number
    
        if not input or input <= 0 then
            RSGCore.Functions.Notify(src, locale('sv_lang_27'), 'error')
            return
        end
    
        local Player = RSGCore.Functions.GetPlayer(src)
        local charName = Player.PlayerData.charinfo.firstname.. ' ' .. Player.PlayerData.charinfo.lastname
    
        local otherPlayer = RSGCore.Functions.GetPlayer(id)
        local otherCharName = otherPlayer.PlayerData.charinfo.firstname.. ' ' .. otherPlayer.PlayerData.charinfo.lastname
    
        if not Player then return end
        if not otherPlayer then return end
    
        local money = otherPlayer.Functions.GetMoney('cash')
    
        if money and money >= input then
            if otherPlayer.Functions.RemoveMoney('cash', input, 'give-money') then
                local info =
                {
                    money = input
                }
    
                TriggerEvent('rsg-log:server:CreateLog', 'create-money-clip', 'Create Stolen Money Clip', 'green',
                    '**Player name**: ' .. GetPlayerName(src) ..
                    '\n **Player ID**: ' .. src ..
                    "\n **Character Name:** " .. charName ..
                    "\n **Amount**: " .. string.format("%.2f", input) ..
                    "\n **Stole money from**" ..
                    "\n **Player Name**: " .. GetPlayerName(id) ..
                    "\n **Character Name**: " .. otherCharName ..
                    "\n **Player ID**: " .. id
                , false)
    
                Player.Functions.AddItem('money_clip', 1, false, info)
                lib.notify(src, {title = locale('sv_lang_28') .. string.format("%.2f", input) .. locale('sv_lang_29'), type = 'success'})
                TriggerClientEvent("rsg-banking:client:closeInventory", src)
            end
        end
    end)
end

---------------------------------
-- money clip made usable
---------------------------------
RSGCore.Functions.CreateUseableItem('money_clip', function(source, item)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local itemData = Player.Functions.GetItemBySlot(item.slot)
    if not itemData then return end

    local amount = itemData.info.money
    if Player.Functions.RemoveItem(item.name, 1, item.slot) then
        Player.Functions.AddMoney('cash', amount)
        lib.notify({ title = locale('sv_lang_3'), description = locale('sv_lang_4') ..' ' .. amount .. ' ' .. locale('sv_lang_5'), type = 'success' })
    end

    if Config.UseGMInventory then
        TriggerClientEvent("rsg-banking:client:closeInventory", src)
    end
end)

---------------------------------
-- create money clip command
---------------------------------
RSGCore.Commands.Add('moneyclip', locale('sv_lang_6'), {{ name = 'amount', help = locale('sv_lang_7') }}, true, function(source, args)
    local src = source
    local args1 = tonumber(args[1])
    if args1 <= 0 then
        lib.notify({ title = locale('sv_lang_2'), description = locale('sv_lang_8'), type = 'error' })
        return
    end

    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local money = Player.Functions.GetMoney('cash')
    if money and money >= args1 then
        if Player.Functions.RemoveMoney('cash', args1, 'give-money') then
            local info =
            {
                money = args1
            }

            Player.Functions.AddItem('money_clip', 1, false, info)
            lib.notify({ title = locale('sv_lang_9'), description = locale('sv_lang_10') .. ' ' .. args1 .. ' ' .. locale('sv_lang_11'), type = 'success' })
        end
    end
end, 'user')

---------------------------------
-- blood money_clip made usable
---------------------------------
RSGCore.Functions.CreateUseableItem('blood_money_clip', function(source, item)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local itemData = Player.Functions.GetItemBySlot(item.slot)
    if not itemData then return end

    local amount = itemData.info.money
    if Player.Functions.RemoveItem(item.name, 1, item.slot) then
        Player.Functions.AddMoney('bloodmoney', amount)
        lib.notify({ title = locale('sv_lang_12'), description = locale('sv_lang_4') ..' ' .. amount ..' ' .. locale('sv_lang_13'), type = 'success' })
    end
end)

---------------------------------
-- create blood money clip command
---------------------------------
RSGCore.Commands.Add('bloodmoneyclip', locale('sv_lang_14'), {{ name = 'amount', help = locale('sv_lang_15') }}, true, function(source, args)
    local src = source
    local args1 = tonumber(args[1])

    if args1 <= 0 then
        lib.notify({ title = locale('sv_lang_2'), description = locale('sv_lang_8'), type = 'error' })
        return
    end

    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local money = Player.Functions.GetMoney('bloodmoney')
    if money and money >= args1 then
        if Player.Functions.RemoveMoney('bloodmoney', args1, 'give-blood-money') then
            local info =
            {
                money = args1
            }

            Player.Functions.AddItem('blood_money_clip', 1, false, info)
            lib.notify({ title = locale('sv_lang_16'), description = locale('sv_lang_10') ..' ' .. args1 ..' ' .. locale('sv_lang_17'), type = 'success' })
        end
    end
end, 'user')

---------------------------------
-- target give money transfer
---------------------------------
RegisterNetEvent('rsg-banking:server:givemoney', function(targetPlayerId, amount)
    local src = source
    if isRateLimited(src, 'givemoney') then return end
    local targetId = tonumber(targetPlayerId)
    amount = math.round(amount, 2)
    if amount <= 0 then
        TriggerClientEvent('lib.notify', src, { title = locale('sv_lang_18'), description = locale('sv_lang_26'), type = 'error' })
        print(('[%s] Player %s attempted transfer with invalid amount: %s'):format(GetCurrentResourceName(), src, amount))
        return
    end
    if amount > Config.MaxTransfer then
        TriggerClientEvent('lib.notify', src, { title = locale('sv_lang_18'), description = locale('sv_lang_26'), type = 'error' })
        print(('[%s] Player %s exceeded max transfer amount: %s > %s'):format(GetCurrentResourceName(), src, amount, Config.MaxTransfer))
        return
    end
    local Player = RSGCore.Functions.GetPlayer(src)
    local targetPlayer = RSGCore.Functions.GetPlayer(targetId)

    if not Player then
        TriggerClientEvent('lib.notify', src, { title = locale('sv_lang_18'), description = locale('sv_lang_19'), type = 'error' })
        return
    end

    if not targetPlayer then
        TriggerClientEvent('lib.notify', src, { title = locale('sv_lang_18'), description = locale('sv_lang_20'), type = 'error' })
        return
    end

    if Player.Functions.GetMoney('cash') >= amount then
        Player.Functions.RemoveMoney('cash', amount)
        targetPlayer.Functions.AddMoney('cash', amount)
        TriggerClientEvent('lib.notify', Player.PlayerData.source, { title = locale('sv_lang_21'), description = locale('sv_lang_22') .. amount .. locale('sv_lang_23') .. targetPlayer.PlayerData.charinfo.firstname, type = 'success' })
        TriggerClientEvent('lib.notify', targetPlayer.PlayerData.source, { title = locale('sv_lang_21'), description = locale('sv_lang_24') .. amount .. locale('sv_lang_25') .. Player.PlayerData.charinfo.firstname, type = 'success' })
        if Config.Discord.TrackTransfers and amount >= Config.Discord.TransactionThreshold then
            local senderName = Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname
            local receiverName = targetPlayer.PlayerData.charinfo.firstname .. " " .. targetPlayer.PlayerData.charinfo.lastname
            SendDiscordWebhook(senderName, receiverName, amount, "Player to Player Transfer")
        end
    else
        TriggerClientEvent('lib.notify', Player.PlayerData.source, { title = locale('sv_lang_18'), description = locale('sv_lang_26'), type = 'error' })
        print(('[%s] Player %s insufficient cash for transfer of %s'):format(GetCurrentResourceName(), src, amount))
    end
end)
