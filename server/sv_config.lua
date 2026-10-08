-----------------------------------------------------------------------
-- SERVER-ONLY CONFIG (never sent to clients - safe for webhook URLs)
-----------------------------------------------------------------------
SVConfig = {}

SVConfig.Webhooks = {
    enabled    = true,
    botName    = 'RSG Banking',
    avatar     = '',                 -- optional image URL for the bot avatar
    footer     = 'rsg-banking',
    serverName = 'My RedM Server',   -- shown in the embed author line

    -- Fallback URL used by any event whose own url is empty
    default = '',

    -- Per-event settings. url = '' uses the default above. enabled = false turns the event off.
    events = {
        account_opened = { enabled = true, url = '', color = 3447003,  title = 'Account Opened' },
        deposit        = { enabled = true, url = '', color = 5763719,  title = 'Deposit' },
        withdraw       = { enabled = true, url = '', color = 15105570, title = 'Withdrawal' },
        transfer       = { enabled = true, url = '', color = 10181046, title = 'Wire Transfer' },
        large          = { enabled = true, url = '', color = 15548997, title = 'Large Transaction' },
        suspicious     = { enabled = true, url = '', color = 10038562, title = 'Suspicious Activity' },
        export         = { enabled = true, url = '', color = 9807270,  title = 'Script Balance Change' },
        system         = { enabled = true, url = '', color = 2303786,  title = 'System' },
        loan           = { enabled = true, url = '', color = 15844367, title = 'Loan' },
        lockbox        = { enabled = true, url = '', color = 12745742, title = 'Vault Lockbox' },
    },

    -- Large transaction alert (sent in addition to the normal log)
    largeAmount  = 5000,             -- $ threshold for deposit / withdraw / wire
    largeMention = '',               -- e.g. '<@&123456789012345678>' to ping a role, '' = no ping

    -- Suspicious activity: repeated spam / out-of-range requests
    spamThreshold = 15,              -- blocked requests per window before alerting
    spamWindow    = 60,              -- seconds

    -- Player identifiers to include in embeds
    showIdentifiers = { license = true, discord = true, steam = false, ip = false },
}
