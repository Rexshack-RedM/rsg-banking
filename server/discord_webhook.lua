---------------------------------
-- Discord Webhook Configuration
---------------------------------
Config.Discord = {
    WebhookURL = "", -- Add your Discord webhook URL here
    RoleID = "", -- Add the Discord role ID to mention (e.g., "1234567890123456789")
    Enabled = true,
    TransactionThreshold = 0, -- Minimum transaction amount to log (0 = log all)
    RoleMentionThreshold = 1000, -- Minimum amount to trigger role mention
    Color = 16711680, -- Red color (decimal format)
    
    -- Track specific transaction types
    TrackWithdrawals = true,
    TrackDeposits = true,
    TrackTransfers = true,
    TrackMoneyClips = true,
}

---------------------------------
-- Discord Webhook Function
---------------------------------
local function SendDiscordWebhook(playerName, targetName, amount, transactionType)
    if not Config.Discord.Enabled or Config.Discord.WebhookURL == "" then return end
    
    -- Determine color and emoji based on transaction type
    local color = Config.Discord.Color
    local emoji = "💰"
    local title = "Transaction Alert"
    
    if transactionType == "Withdrawal" then
        color = 15158332 -- Red
        emoji = "💸"
        title = "Bank Withdrawal"
    elseif transactionType == "Deposit" then
        color = 3066993 -- Green
        emoji = "💵"
        title = "Bank Deposit"
    elseif transactionType == "Player to Player Transfer" then
        color = 3447003 -- Blue
        emoji = "🤝"
        title = "Player Transfer"
    elseif transactionType == "Money Clip Created" then
        color = 15844367 -- Gold
        emoji = "📎"
        title = "Money Clip Created"
    end
    
    -- Add alert emoji for large transactions
    if amount >= Config.Discord.RoleMentionThreshold then
        emoji = "🚨 " .. emoji
        title = "**" .. title .. " - HIGH VALUE**"
    end
    
    -- Format amount with commas
    local formattedAmount = tostring(amount):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    
    local fields = {
        {
            ["name"] = "💵 Amount",
            ["value"] = "**$" .. formattedAmount .. "**",
            ["inline"] = true
        },
        {
            ["name"] = "📊 Type",
            ["value"] = transactionType,
            ["inline"] = true
        }
    }
    
    -- Add player information based on transaction type
    if transactionType == "Player to Player Transfer" then
        table.insert(fields, {
            ["name"] = "👤 Sender",
            ["value"] = "`" .. playerName .. "`",
            ["inline"] = true
        })
        table.insert(fields, {
            ["name"] = "👤 Receiver",
            ["value"] = "`" .. targetName .. "`",
            ["inline"] = true
        })
    else
        table.insert(fields, {
            ["name"] = "👤 Player",
            ["value"] = "`" .. playerName .. "`",
            ["inline"] = false
        })
        if targetName and targetName ~= "N/A" then
            table.insert(fields, {
                ["name"] = "🏦 Account",
                ["value"] = "`" .. targetName .. "`",
                ["inline"] = false
            })
        end
    end
    
    local embed = {
        {
            ["title"] = emoji .. " " .. title,
            ["color"] = color,
            ["fields"] = fields,
            ["footer"] = {
                ["text"] = "🕒 " .. os.date("%B %d, %Y at %I:%M %p"),
            },
            ["thumbnail"] = {
                ["url"] = "" -- Optional: Replace with your server logo
            },
            ["timestamp"] = os.date("!%Y-%m-%dT%H:%M:%SZ")
        }
    }

    local content = ""
    if Config.Discord.RoleID ~= "" and amount >= Config.Discord.RoleMentionThreshold then
        content = "⚠️ <@&" .. Config.Discord.RoleID .. "> Large transaction detected!"
    end

    PerformHttpRequest(Config.Discord.WebhookURL, function(err, text, headers) end, 'POST', json.encode({
        username = "Bank Transaction Monitor",
        avatar_url = "", -- Optional: Replace with bank icon
        embeds = embed,
        content = content
    }), { ['Content-Type'] = 'application/json' })
end

return SendDiscordWebhook
