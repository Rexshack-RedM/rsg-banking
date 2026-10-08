-----------------------------------------------------------------------
-- Discord webhook logging
-- Usage (server): BankLog(event, src, fields, extra)
--   event  : key in SVConfig.Webhooks.events
--   src    : player server id or nil for system messages
--   fields : { { name = 'Amount', value = '$50' }, ... }
--   extra  : { description = '...', content = '...' (plain text / mentions) }
-----------------------------------------------------------------------
local RSGCore = exports['rsg-core']:GetCoreObject()
local W = SVConfig.Webhooks

local queue, sending = {}, false
local spam = {}  -- [src] = { count, start, alerted }

local function urlFor(event)
    local e = W.events[event]
    if not W.enabled or not e or not e.enabled then return nil end
    local url = (e.url ~= '' and e.url) or W.default
    return (url and url ~= '') and url or nil
end

local function identifiers(src)
    local out = {}
    for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
        local kind, value = id:match('^(%w+):(.+)$')
        if kind and W.showIdentifiers[kind] then
            if kind == 'discord' then value = ('<@%s> (%s)'):format(value, value) end
            out[#out + 1] = ('**%s:** %s'):format(kind, value)
        end
    end
    return #out > 0 and table.concat(out, '\n') or 'n/a'
end

local function playerFields(src)
    local Player = RSGCore.Functions.GetPlayer(src)
    local ci = Player and Player.PlayerData.charinfo or {}
    return {
        { name = 'Character', value = ('%s %s'):format(ci.firstname or '?', ci.lastname or '?'), inline = true },
        { name = 'Citizen ID', value = Player and Player.PlayerData.citizenid or 'n/a', inline = true },
        { name = 'Player', value = ('%s (ID %s)'):format(GetPlayerName(src) or '?', src), inline = true },
        { name = 'Identifiers', value = identifiers(src), inline = false },
    }
end

-- Discord allows ~5 requests / 2s per webhook; send one at a time and honour 429 retry_after
local function pump()
    if sending or #queue == 0 then return end
    sending = true
    local job = table.remove(queue, 1)
    PerformHttpRequest(job.url, function(status, body)
        if status == 429 then
            local ok, data = pcall(json.decode, body or '')
            local wait = (ok and data and tonumber(data.retry_after) or 2) * 1000
            table.insert(queue, 1, job)
            SetTimeout(math.ceil(wait), function() sending = false; pump() end)
            return
        elseif status < 200 or status >= 300 then
            print(('[rsg-banking] ^1webhook failed (%s):^7 %s'):format(status, body or ''))
        end
        SetTimeout(450, function() sending = false; pump() end)
    end, 'POST', job.payload, { ['Content-Type'] = 'application/json' })
end

function BankLog(event, src, fields, extra)
    local url = urlFor(event)
    if not url then return end
    extra = extra or {}
    local e = W.events[event]

    local all = {}
    for _, f in ipairs(fields or {}) do all[#all + 1] = f end
    if src then for _, f in ipairs(playerFields(src)) do all[#all + 1] = f end end
    for _, f in ipairs(all) do
        f.value = tostring(f.value ~= nil and f.value ~= '' and f.value or 'n/a'):sub(1, 1024)
    end

    local payload = {
        username   = W.botName,
        avatar_url = W.avatar ~= '' and W.avatar or nil,
        content    = extra.content,
        allowed_mentions = { parse = { 'roles', 'users' } },
        embeds = { {
            title       = e.title,
            description = extra.description,
            color       = e.color,
            author      = { name = W.serverName },
            fields      = #all > 0 and all or nil, -- empty Lua table would encode as {} and Discord rejects it
            footer      = { text = W.footer },
            timestamp   = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        } },
    }
    queue[#queue + 1] = { url = url, payload = json.encode(payload) }
    pump()
end

local function money(n) return ('$%.2f'):format(tonumber(n) or 0) end
BankMoney = money

-- Sends the large-transaction alert when the amount is over the threshold
function BankLogLarge(kind, src, bankLabel, amount, fields)
    if (tonumber(amount) or 0) < (W.largeAmount or math.huge) then return end
    local f = { { name = 'Type', value = kind, inline = true }, { name = 'Branch', value = bankLabel, inline = true },
                { name = 'Amount', value = money(amount), inline = true } }
    for _, x in ipairs(fields or {}) do f[#f + 1] = x end
    BankLog('large', src, f, { content = W.largeMention ~= '' and W.largeMention or nil })
end

-- Counts blocked requests; alerts once per window when the threshold is passed
function BankLogBlocked(src, reason, bankId)
    local now = os.time()
    local s = spam[src]
    if not s or now - s.start > W.spamWindow then s = { count = 0, start = now, alerted = false }; spam[src] = s end
    s.count = s.count + 1
    if s.count >= W.spamThreshold and not s.alerted then
        s.alerted = true
        BankLog('suspicious', src, {
            { name = 'Reason', value = reason, inline = true },
            { name = 'Bank', value = bankId or 'n/a', inline = true },
            { name = 'Blocked Requests', value = ('%s in %ss'):format(s.count, W.spamWindow), inline = true },
        })
    end
end

-- Single event alert (e.g. bank request from far away). At most one per player per spamWindow.
local lastSuspicious = {}
function BankLogSuspicious(src, reason, bankId)
    local now = os.time()
    if lastSuspicious[src] and now - lastSuspicious[src] < W.spamWindow then return end
    lastSuspicious[src] = now
    local ped = GetPlayerPed(src)
    local c = ped ~= 0 and GetEntityCoords(ped) or vector3(0, 0, 0)
    BankLog('suspicious', src, {
        { name = 'Reason', value = reason, inline = true },
        { name = 'Bank', value = tostring(bankId), inline = true },
        { name = 'Player Coords', value = ('%.1f, %.1f, %.1f'):format(c.x, c.y, c.z), inline = false },
    })
end

AddEventHandler('playerDropped', function() spam[source], lastSuspicious[source] = nil, nil end)

-- quick test: run `bankwebhooktest` in the server console
RegisterCommand('bankwebhooktest', function(src)
    if src ~= 0 then return end
    for event in pairs(W.events) do
        BankLog(event, nil, { { name = 'Test', value = 'Webhook for "' .. event .. '" is working', inline = false } })
    end
    print('[rsg-banking] test webhooks queued')
end, true)
