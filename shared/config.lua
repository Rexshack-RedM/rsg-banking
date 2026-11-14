Config = {}

Config.AutoDatabase     = true         -- create tables automatically on start (false = import installation/rsg_banking.sql)
Config.OpenKey          = 'J'          -- RSGCore.Shared.Keybinds key
Config.ServerMaxDistance = 5.0        -- max distance from the bank for any transaction (server checked)
Config.Cooldown         = 500          -- ms between bank requests per player (anti-spam)

-- While NUI is open, block game controls but allow push-to-talk.
Config.AllowPushToTalkWhileOpen = true
Config.PushToTalkControls = {
    0x4BC9DABB, -- INPUT_PUSH_TO_TALK
}
Config.MaxTransaction   = 100000       -- per single deposit/withdraw/transfer
Config.HistoryLimit     = 15           -- transactions shown in the ledger
Config.HistoryDays      = 30           -- delete ledger entries older than this on start (0 = keep forever)

-- Accounts must be opened at each branch before it can be used
Config.AccountOpenFee   = 5            -- cash fee to open an account (0 = free)

-- Opening hours (in-game clock). Set Config.UseHours = false for 24/7 banks
Config.UseHours  = true
Config.OpenHour  = 7
Config.CloseHour = 21

-- Closing time: stop players getting locked inside
Config.Closing = {
    warnHours    = 1,      -- in-game hours before closing to warn players inside (0 = off)
    insideRadius = 15.0,   -- distance from a bank's coords that counts as "inside" (must also be in an interior)
    graceSeconds = 120,    -- real seconds a player may stay inside after closing before being escorted out
    escort       = true,   -- teleport lingering players to the bank's `exit` (only banks with an exit set)
}
-- Add `exit = vector4(x, y, z, heading)` to a bank below (a spot on the street outside its front door)
-- to enable escorting for that bank. Banks without an exit just keep their doors usable from inside.

-- Home branch: paychecks (and anything paid into RSG-Core 'bank' money) go here.
-- The first account a player opens becomes their home; they can change it at any counter.
Config.DefaultHomeBank  = 'valentine'  -- used by the migration for players with no accounts yet
Config.ForwardCoreBank  = true         -- move money other scripts add to RSG-Core 'bank' into the home branch
Config.MigrateCoreMoney = true         -- one-off: move old bank/valbank/rhobank/blkbank/armbank money into branches

-- Wiring money between branches
Config.TransferFeePercent = 5          -- % fee charged on branch-to-branch wires
Config.TransferMinFee     = 1          -- minimum fee in $

-- Loans: borrow money from a branch. The loan is paid into that branch account
-- and must be repaid (from the branch vault or cash) at the same branch.
Config.Loans = {
    enabled         = true,
    minAmount       = 50,
    maxAmount       = 2000,      -- largest single loan
    interestPercent = 10,        -- flat interest added when the loan is taken ($1000 -> owe $1100)
    termDays        = 7,         -- real days to repay
    maxActive       = 1,         -- loans a player may have open across ALL branches
    minAccountHours = 0,         -- account must be at least this many real hours old (0 = off)
    latePenaltyPercent = 10,     -- added once when the loan goes overdue
    autoCollect     = true,      -- overdue loans are collected from the player's branch balances automatically
    checkInterval   = 10,        -- minutes between overdue checks
    -- A loan that stays unpaid this long after its due date is written off (a "default")
    default = {
        enabled      = true,
        afterDays    = 3,        -- real days after the due date
        seizeLockbox = true,     -- the lockbox contents at that branch are seized as collateral
    },
}

-- Credit score: repaying loans builds it, going late or defaulting damages it.
-- The highest tier a player's score reaches sets their loan terms. Below the lowest tier they can't borrow.
Config.Credit = {
    enabled    = true,
    startScore = 600,
    minScore   = 300,
    maxScore   = 850,
    repaidOnTime = 15,           -- loan fully repaid before it went overdue
    wentLate     = -40,          -- loan became overdue
    defaulted    = -100,         -- loan written off
    tiers = {
        { min = 700, interestAdjust = -2, maxMult = 1.5 },   -- interest +/- points on Config.Loans.interestPercent, x loan limit
        { min = 550, interestAdjust = 0,  maxMult = 1.0 },
        { min = 450, interestAdjust = 4,  maxMult = 0.5 },
    },
}

-- Savings interest: paid on every personal branch balance once per interval (real hours).
-- Only the first `maxBalance` of an account earns interest, and only accounts holding at least `minBalance`.
-- Shared (business) accounts never earn interest. If the server was offline it pays once, never for missed periods.
Config.Interest = {
    enabled       = true,
    percentPerDay = 0.2,         -- % of the (capped) balance per interval
    minBalance    = 100,
    maxBalance    = 10000,
    intervalHours = 24,
}

-- Send money to another citizen: arrives in their home branch (works while they are offline)
Config.Send = {
    enabled      = true,
    feePercent   = 2,
    minFee       = 1,
    maxAmount    = 5000,         -- per transfer
    dailyLimit   = 10000,        -- total sent (incl. fees) per rolling 24h (0 = no limit)
}

-- Business accounts: one shared account per job / gang per branch. The boss opens it and decides who may withdraw.
Config.Business = {
    enabled       = true,
    allowJobs     = true,
    allowGangs    = true,
    openFee       = 50,          -- cash
    bossOnlyOpen  = true,
    maxMembers    = 10,          -- extra people (besides the boss) allowed to withdraw
    memberLimit   = 1000,        -- most a non-boss member can withdraw at once (0 = no limit)
    excluded      = { unemployed = true, none = true },   -- job / gang names that can't have accounts
}

-- Telegrams (needs rsg-telegram). Receipts are written straight into its inbox.
Config.Telegram = {
    enabled          = true,
    senderName       = 'Bank',
    sendReceipts     = true,     -- recipient of "send money" gets a telegram
    alertLarge       = true,     -- receipt for large deposits / withdrawals / wires / transfers
    largeAmount      = 1000,
    statementLines   = 12,       -- ledger lines in a statement telegram
    statementCooldown = 60,      -- seconds between statements per player
}

-- Branch lockdown: other resources (e.g. rsg-bankrobbery) call exports['rsg-banking']:LockBranch(bankId, seconds)
-- to shut a branch's services while it is being robbed. A lock always expires after `maxSeconds`.
Config.Lock = {
    enabled    = true,
    maxSeconds = 1800,
}

-- Vault lockboxes: rent a safe-deposit box at a branch to store whitelisted items.
-- Capacity is total item count (e.g. 25 = 25 gold bars).
Config.Lockbox = {
    enabled = true,
    sizes = {
        small  = { label = 'Small Lockbox',  capacity = 25,  price = 50,  rent = 5  },   -- rent = $ per rent period
        medium = { label = 'Medium Lockbox', capacity = 50,  price = 150, rent = 12 },
        large  = { label = 'Large Lockbox',  capacity = 100, price = 300, rent = 25 },
    },
    -- Rent: taken from the branch vault each period (the price above covers the first period).
    -- If the vault can't pay, the box is locked for deposits; after graceDays the contents are forfeited.
    rent = {
        enabled          = true,
        periodDays       = 7,    -- real days per rent period
        graceDays        = 3,    -- days after the due date before an unpaid box is cleared
        maxPrepayPeriods = 4,    -- how far ahead a player may pay manually
        checkInterval    = 30,   -- minutes between rent checks
    },
    -- Only the SMALL lockbox can be enlarged, one step at a time, for an extra fee
    upgrade = {
        size     = 'small',
        step     = 10,           -- capacity added per upgrade
        price    = 40,           -- fee per upgrade
        maxSteps = 3,            -- small 25 -> 55 max
    },
    payWith = 'bank',            -- 'bank' = paid from this branch vault, 'cash' = paid in cash
    -- Items allowed in a lockbox (anything not listed is refused)
    items = {
        resource_gold_bar = true,
        -- resource_silver_bar = true,
        -- gold_nugget = true,
    },
    imagePath = 'nui://rsg-inventory/html/images/', -- where item images are loaded from
}

-- Blip
Config.Blip = {
    enabled = true,
    sprite  = -2128054417,             -- bank blip
    scale   = 0.2,
    openColor   = 'BLIP_MODIFIER_MP_COLOR_8',   -- green when open
    closedColor = 'BLIP_MODIFIER_MP_COLOR_10',  -- red when closed
    updateInterval = 10000,                     -- ms between open/closed checks
}

-- Each bank is its own institution: money deposited here stays here.
Config.Banks = {
    valentine = {
        label  = 'Valentine Bank',
        coords = vector3(-308.58, 776.07, 118.70),
    },
    rhodes = {
        label  = 'Rhodes Bank',
        coords = vector3(1292.307, -1301.539, 77.04012),
    },
    saintdenis = {
        label  = 'Saint Denis Bank',
        coords = vector3(2644.579, -1292.313, 52.24956),
    },
    blackwater = {
        label  = 'Blackwater Bank',
        coords = vector3(-813.1633, -1277.486, 43.63771),
    },
    armadillo = {
        label  = 'Armadillo Bank',
        coords = vector3(-3666.25, -2626.57, -13.59),
    },
    strawberry = {
        label  = 'Strawberry Bank',
        coords = vector3(-1752.21, -383.27, 156.53),
    },
}

-- Bank doors. state = 0 -> unlocked while the bank is open, locked when closed
-- state = 1 -> always locked (vaults, back rooms)
Config.BankDoors = {

    -- valentine ( open = 0 / locked = 1)
    { door = 2642457609, state = 0 }, -- main door
    { door = 3886827663, state = 0 }, -- main door
    { door = 1340831050, state = 1 }, -- bared right
    { door = 2343746133, state = 1 }, -- bared left
    { door = 334467483,  state = 1 }, -- inner door1
    { door = 3718620420, state = 1 }, -- inner door2
    { door = 576950805,  state = 1 }, -- valut

    -- rhodes  ( open = 0 / locked = 1)
    { door = 3317756151, state = 0 }, -- main door
    { door = 3088209306, state = 0 }, -- main door
    { door = 2058564250, state = 1 }, -- inner door1
    { door = 3142122679, state = 1 }, -- inner door2
    { door = 1634148892, state = 1 }, -- inner door3
    { door = 3483244267, state = 1 }, -- valut

    -- saint denis ( open = 0 / locked = 1)
    { door = 2158285782, state = 0 }, -- main door
    { door = 1733501235, state = 0 }, -- main door
    { door = 2089945615, state = 0 }, -- main door
    { door = 2817024187, state = 0 }, -- main door
    { door = 1830999060, state = 1 }, -- inner private door
    { door = 965922748,  state = 1 }, -- manager door
    { door = 1634115439, state = 1 }, -- manager door
    { door = 1751238140, state = 1 }, -- vault

    -- blackwater
    { door = 531022111,  state = 0 }, -- main door
    { door = 2117902999, state = 1 }, -- inner door
    { door = 2817192481, state = 1 }, -- manager door
    { door = 1462330364, state = 1 }, -- vault door

    -- armadillo
    { door = 3101287960, state = 0 }, -- main door
    { door = 3550475905, state = 1 }, -- inner door
    { door = 1329318347, state = 1 }, -- inner door
    { door = 1366165179, state = 1 }, -- back door

}
