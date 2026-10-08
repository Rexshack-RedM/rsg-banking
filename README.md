# rsg-banking

Branch banking for RSG-Core (RedM). Every town bank is its own institution: money deposited in Valentine can only be withdrawn in Valentine, unless it is wired to another branch for a fee.

## Features
- Six branches: Valentine, Rhodes, Saint Denis, Blackwater, Armadillo, Strawberry (configurable)
- Players open an account at each branch before using it (optional cash fee)
- Deposit, withdraw, wire between your own branches (percentage fee with minimum)
- Branch overview and per-branch ledger
- Opening hours: map blips turn green/red, main doors unlock/lock, menu closes at closing time
- Automatic database setup (or manual SQL)
- Draggable UI that remembers its position (double-click the header to re-centre)
- Server-side validation: distance check, amount limits, per-player lock and rate limit, atomic balance updates with refunds on failure

## Requirements
- rsg-core
- ox_lib
- oxmysql
- OneSync (used for the server-side distance check)

## Installation
1. Drop `rsg-banking` into your resources folder.
2. Add `ensure rsg-banking` to server.cfg **after** rsg-core, ox_lib and oxmysql.
3. Database (choose one):
   - **Automatic (default):** `Config.AutoDatabase = true`. Tables are created on first start.
   - **Manual:** set `Config.AutoDatabase = false` and import `installation/rsg_banking.sql`.
4. Walk to each counter in-game and check the coordinates in `shared/config.lua`.
5. If any bank doors are also configured in rsg-doorlock, remove them from one of the two scripts.

## Configuration (`shared/config.lua`)
| Option | Description |
|---|---|
| `AutoDatabase` | Create tables automatically on start |
| `OpenKey` | Prompt key (RSGCore keybind name) |
| `ServerMaxDistance` | Max distance from the bank for any action |
| `Cooldown` | ms between bank requests per player |
| `MaxTransaction` | Max amount per deposit / withdraw / wire |
| `HistoryLimit` / `HistoryDays` | Ledger rows shown / days kept |
| `AccountOpenFee` | Cash fee to open an account (0 = free) |
| `UseHours`, `OpenHour`, `CloseHour` | Opening hours (in-game clock) |
| `TransferFeePercent`, `TransferMinFee` | Wire fees |
| `Blip` | Sprite, scale, open/closed colours, update interval |
| `Banks` | Branch ids, labels and counter coordinates |
| `BankDoors` | Door hashes; `state = 0` follows opening hours, `1` always locked |

## Closing time
- Players inside a bank get a warning `Closing.warnHours` before closing.
- At closing, the main doors stay unlocked **for players still inside** (door states are per-client), so they can walk out. Everyone outside sees them locked. Doors lock for that player once they leave.
- Optional escort: add `exit = vector4(x, y, z, heading)` to a bank in `Config.Banks`. A player still inside `Closing.graceSeconds` after closing is faded out and placed at that spot.

## Server exports
```lua
exports['rsg-banking']:HasAccount(citizenid, bankId)                -- bool
exports['rsg-banking']:GetBranchBalance(citizenid, bankId)          -- number
exports['rsg-banking']:GetTotalBalance(citizenid)                   -- number (all branches)
exports['rsg-banking']:AddBranchMoney(citizenid, bankId, amount, note)    -- bool (false if no account)
exports['rsg-banking']:RemoveBranchMoney(citizenid, bankId, amount, note) -- bool (false if insufficient)
```

## Notes
- Branch balances are separate from RSG-Core's built-in `bank` money.
- Opening hours use each player's game clock, so they are enforced in the client UI, not on the server.

## Discord webhooks
All webhook settings live in `server/sv_config.lua`, which is **server-only** and never sent to players, so your URLs stay private.

1. In Discord: Channel settings → Integrations → Webhooks → New Webhook → Copy URL.
2. Paste it into `SVConfig.Webhooks.default` to send everything to one channel, or into an event's own `url` to split logs across channels.
3. Restart the resource and run `bankwebhooktest` in the server console to send a test message for every event.

| Event | Sent when |
|---|---|
| `account_opened` | A player opens an account (branch, fee) |
| `deposit` / `withdraw` | Cash moved in or out (amount, new balance) |
| `transfer` | Wire between branches (from, to, amount, fee, total) |
| `large` | Any deposit, withdrawal or wire at or above `largeAmount`; can ping a role via `largeMention` |
| `suspicious` | Transaction attempted away from a bank, or repeated blocked/spammed requests (`spamThreshold` per `spamWindow`) |
| `export` | Another resource changed a balance via `AddBranchMoney` / `RemoveBranchMoney` (shows which resource) |
| `system` | Resource start, database setup failures, missing tables |

Every player embed includes character name, citizen ID, server ID and the identifiers enabled in `showIdentifiers` (license and Discord by default; Steam and IP are off).
Messages are queued and sent one at a time, and Discord rate-limit responses are retried automatically.

## Languages
All player-facing text (notifications, prompts and the whole UI) comes from `locales/*.json`.
Included: `en`, `de`, `el`, `es`, `fr`, `ja`, `nl`, `pl`, `pt-br`, `ro`.
Set the language in server.cfg with ox_lib's convar, e.g. `setr ox:locale "de"`.
Discord webhook logs and console messages stay in English for staff.
