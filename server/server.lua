local RSGCore = exports['rsg-core']:GetCoreObject()
local banking = nil
lib.locale()
math = lib.math
local SendDiscordWebhook = require('server.discord_webhook')

---------------
-- stash
----------------
RegisterNetEvent('rsg-banking:server:opensafedeposit', function(town)
    local src = source
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

    local banking = nil
    local cash = Player.Functions.GetMoney('cash')
    if Player.PlayerData.money[moneytype] then
        banking = tonumber(Player.PlayerData.money[moneytype])
    end

    cb({bank = banking, cash = cash})
end)

---------------------------------
-- deposit & withdraw
---------------------------------
RegisterNetEvent('rsg-banking:server:transact', function(type, amount, moneytype)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    local currentCash = Player.Functions.GetMoney('cash')
    local currentBank = Player.Functions.GetMoney(moneytype)

    amount = math.round(amount, 2)
    if amount <= 0 then
        lib.notify(src, {title = locale('sv_lang_1'), type = 'error'})
        return
    end

    -- bank-withdraw
    if type == 1 then
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
            
            -- Discord webhook for withdrawals
            if Config.Discord.TrackWithdrawals and amount >= Config.Discord.TransactionThreshold then
                local playerName = Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname
                SendDiscordWebhook(playerName, "Bank (" .. moneytype .. ")", amount, "Withdrawal")
            end
        else
            lib.notify(src, {title = locale('sv_lang_2'), type = 'error'})
        end
    end

    -- bank-deposit
    if type == 2 then
        if currentCash >= amount then
            Player.Functions.RemoveMoney('cash', tonumber(amount), 'bank-deposit')
            Player.Functions.AddMoney(moneytype, tonumber(amount), 'bank-deposit')
            local newBankBalance = Player.Functions.GetMoney(moneytype)
            TriggerClientEvent('rsg-banking:client:UpdateBanking', src, newBankBalance, moneytype)
            
            -- Discord webhook for deposits
            if Config.Discord.TrackDeposits and amount >= Config.Discord.TransactionThreshold then
                local playerName = Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname
                SendDiscordWebhook(playerName, "Bank (" .. moneytype .. ")", amount, "Deposit")
            end
        else
            lib.notify(src, {title = locale('sv_lang_2'), type = 'error'})
        end
    end

    -- create money_clip
    if type == 3 then
        if currentBank >= amount then
            local info = { money = amount }
            Player.Functions.RemoveMoney(moneytype, tonumber(amount), 'bank-money_clip')
            Player.Functions.AddItem('money_clip', 1, false, info)
            local newBankBalance = Player.Functions.GetMoney(moneytype)
            TriggerClientEvent('rsg-banking:client:UpdateBanking', src, newBankBalance, moneytype)
            lib.notify(src, { title = locale('sv_lang_9'), description = locale('sv_lang_10') .. ' ' .. amount .. ' ' .. locale('sv_lang_11'), type = 'success' })
            
            -- Discord webhook for money clip creation
            if Config.Discord.TrackMoneyClips and amount >= Config.Discord.TransactionThreshold then
                local playerName = Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname
                SendDiscordWebhook(playerName, "Money Clip", amount, "Money Clip Created")
            end
        else
            lib.notify(src, {title = locale('sv_lang_2'), type = 'error'})
        end
    end

end)

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
    local Player = RSGCore.Functions.GetPlayer(src)
    local targetPlayer = RSGCore.Functions.GetPlayer(tonumber(targetPlayerId))
    
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
        
        -- Discord webhook for large transactions
        if Config.Discord.TrackTransfers and amount >= Config.Discord.TransactionThreshold then
            local senderName = Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname
            local receiverName = targetPlayer.PlayerData.charinfo.firstname .. " " .. targetPlayer.PlayerData.charinfo.lastname
            SendDiscordWebhook(senderName, receiverName, amount, "Player to Player Transfer")
        end
    else
        TriggerClientEvent('lib.notify', Player.PlayerData.source, { title = locale('sv_lang_18'), description = locale('sv_lang_26'), type = 'error' })
    end
end)
