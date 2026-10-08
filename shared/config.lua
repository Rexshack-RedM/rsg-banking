Config = {}

Config.AutoDatabase     = true         -- create tables automatically on start (false = import installation/rsg_banking.sql)
Config.OpenKey          = 'J'          -- RSGCore.Shared.Keybinds key
Config.ServerMaxDistance = 5.0        -- max distance from the bank for any transaction (server checked)
Config.Cooldown         = 500          -- ms between bank requests per player (anti-spam)
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
