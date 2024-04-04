local RSGCore = exports['rsg-core']:GetCoreObject()

-----------------------------------------------------------------------
-- version checker
-----------------------------------------------------------------------
local function versionCheckPrint(_type, log)
    local color = _type == 'success' and '^2' or '^1'

    print(('^5['..GetCurrentResourceName()..']%s %s^7'):format(color, log))
end

local function CheckVersion()
    PerformHttpRequest('https://raw.githubusercontent.com/Rexshack-RedM/rsg-banking/main/version.txt', function(err, text, headers)
        local currentVersion = GetResourceMetadata(GetCurrentResourceName(), 'version')

        if not text then 
            versionCheckPrint('error', 'Currently unable to run a version check.')
            return 
        end

        --versionCheckPrint('success', ('Current Version: %s'):format(currentVersion))
        --versionCheckPrint('success', ('Latest Version: %s'):format(text))
        
        if text == currentVersion then
            versionCheckPrint('success', 'You are running the latest version.')
        else
            versionCheckPrint('error', ('You are currently running an outdated version, please update to version %s'):format(text))
        end
    end)
end

-- callback for bank balance
RSGCore.Functions.CreateCallback('rsg-banking:getBankingInformation', function(source, cb)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player then return cb(nil) end
    local banking = tonumber(Player.PlayerData.money['bank'])
    cb(banking)
end)

-- deposit & withdraw
RegisterNetEvent("rsg-banking:server:transact", function(type, amount)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(source)
    local currentCash = Player.Functions.GetMoney('cash')
    local currentBank = Player.Functions.GetMoney('bank')
    amount = tonumber(amount)
    if amount <= 0 then
        lib.notify(src, {title = "Invalid amount.", type = "error"})
        return
    end
    if type == 1 then
        if currentBank >= amount then
            Player.Functions.RemoveMoney('bank', tonumber(amount), 'bank-withdraw')
            Player.Functions.AddMoney('cash', tonumber(amount), 'bank-withdraw')
            local newBankBalance = Player.Functions.GetMoney('bank')
            TriggerClientEvent('rsg-banking:client:UpdateBanking', src, newBankBalance)
        else
            lib.notify(src, {title = "Insufficient funds.", type = "error"})
        end
    elseif type == 2 then
        if currentCash >= amount then
            Player.Functions.RemoveMoney('cash', tonumber(amount), 'bank-withdraw')
            Player.Functions.AddMoney('bank', tonumber(amount), 'bank-withdraw')
            local newBankBalance = Player.Functions.GetMoney('bank')
            TriggerClientEvent('rsg-banking:client:UpdateBanking', src, newBankBalance)
        else
            lib.notify(src, {title = "Insufficient funds.", type = "error"})
        end
    end
end)

-- moneyclip made usable
RSGCore.Functions.CreateUseableItem('moneyclip', function(source, item)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)

    if not Player then return end

    local itemData = Player.Functions.GetItemBySlot(item.slot)

    if not itemData then return end

    local amount = itemData.info.money

    if Player.Functions.RemoveItem(item.name, 1, item.slot) then
        Player.Functions.AddMoney('cash', amount)
        lib.notify({ title = 'Money Clip Used', description = 'You\'ve got $'..amount..' cash from this Money Clip!', type = 'success' })
    end
end)

-- create moneyclip command
RSGCore.Commands.Add('moneyclip', 'Make Money Clip', {{ name = 'amount', help = 'How much money do you want convert?' }}, true, function(source, args)
    local src = source
    local args1 = tonumber(args[1])

    if args1 <= 0 then
        lib.notify({ title = 'Insufficient Funds', description = 'please enter the correct amount!', type = 'error' })
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

            Player.Functions.AddItem('moneyclip', 1, false, info)
            lib.notify({ title = 'Money Clip Converted', description = 'You\'ve just converted $'..args1..' cash into a Money Clip!', type = 'success' })
        end
    end
end, 'user')

-- blood moneyclip made usable
RSGCore.Functions.CreateUseableItem('bloodmoneyclip', function(source, item)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)

    if not Player then return end

    local itemData = Player.Functions.GetItemBySlot(item.slot)

    if not itemData then return end

    local amount = itemData.info.money

    if Player.Functions.RemoveItem(item.name, 1, item.slot) then
        Player.Functions.AddMoney('bloodmoney', amount)
        lib.notify({ title = 'Blood Money Clip Used', description = 'You\'ve got $'..amount..' bloodmoney from this Blood Money Clip!', type = 'success' })
    end
end)

-- create blood moneyclip command
RSGCore.Commands.Add('bloodmoneyclip', 'Make Blood Money Clip', {{ name = 'amount', help = 'How much blood money do you want convert?' }}, true, function(source, args)
    local src = source
    local args1 = tonumber(args[1])

    if args1 <= 0 then
        lib.notify({ title = 'Insufficient Funds', description = 'please enter the correct amount!', type = 'error' })
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

            Player.Functions.AddItem('bloodmoneyclip', 1, false, info)
            lib.notify({ title = 'Blood Money Clip Converted', description = 'You\'ve just converted $'..args1..' bloodmoney into a Money Clip!', type = 'success' })
        end
    end
end, 'user')

--------------------------------------------------------------------------------------------------
-- start version check
--------------------------------------------------------------------------------------------------
CheckVersion()
