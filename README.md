# rsg-banking

Branch banking for RSG-Core (RedM). Every town bank is its own institution: money deposited in Valentine can only be withdrawn in Valentine, unless it is wired to another branch for a fee.

## Features
- Six branches: Valentine, Rhodes, Saint Denis, Blackwater, Armadillo, Strawberry (configurable)
- Players open an account at each branch before using it (optional cash fee)
- Deposit, withdraw, wire between your own branches (percentage fee with minimum)
- Branch overview and per-branch ledger
- **Loans**: borrow from a branch, repay from the vault or in cash, late penalty and automatic collection when overdue
- **Vault lockboxes**: rent a small / medium / large safe-deposit box per branch for whitelisted items (e.g. gold bars); the small box can be enlarged for a fee
- **Credit score and loan defaults**: on-time repayment raises your score, late payment and default lower it; low scores pay higher interest or are refused. Unpaid loans default after a grace period and the bank seizes the lockbox at that branch
- **Send money to another citizen** by citizen ID (fee, per-transfer max, daily limit). It lands in the recipient's home branch, online or offline
- **Savings interest**: daily interest on personal branch balances (with a minimum balance and a payout cap)
- **Telegram integration** (rsg-telegram): receipts for received money, alerts for large deposits/withdrawals, and an exportable statement
- **Business and gang accounts**: shared branch accounts for a job or gang, with a boss-managed list of people allowed to withdraw
- **Bank robbery hook**: lock any branch with an export/event for a set time (menu closes, blip turns closed)
- **Lockbox rent**: lockboxes cost rent per period, auto-paid from your vault, with eviction of unpaid boxes
- Opening hours: map blips turn green/red, main doors unlock/lock, menu closes at closing time
- Automatic database setup (or manual SQL)
- Draggable UI that remembers its position (double-click the header to re-centre)
- Server-side validation: distance check, opening hours (via rsg-weather), amount limits, per-player lock and rate limit, atomic balance updates with refunds on failure
- No ox_lib: notifications, callbacks and locales all come from rsg-core

## Requirements
- rsg-core (3.0.3+)
- rsg-inventory
- oxmysql
- rsg-telegram (optional: statements, receipts and large-transaction alerts; the bank writes to its telegram table directly)
- rsg-weather (optional: used for the server-side opening hours check; without it hours are client-side only)
- OneSync (used for the server-side distance check)

## Installation
1. Drop `rsg-banking` into your resources folder.
2. Add `ensure rsg-banking` to server.cfg **after** rsg-core, rsg-inventory and oxmysql.
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
| `Loans` | Loan limits, interest, term, late penalty, auto-collection (see below) |
| `Lockbox` | Lockbox sizes, prices, rent, upgrade, payment method and allowed items (see below) |
| `Credit` | Credit score start/limits, score changes and tiers (see below) |
| `Interest` | Savings interest rate, minimum balance, payout cap, interval |
| `Send` | Send-to-citizen fee, max per transfer, daily limit |
| `Business` | Job/gang account fee, boss-only opening, member limits |
| `Telegram` | Receipts, large-transaction alerts, statement lines and cooldown |
| `Lock` | Branch lock switch and maximum lock time |

## Loans (`Config.Loans`)
- A player borrows at the counter they are standing at; the money is paid into that branch account.
- Interest is flat and added up front (`interestPercent`). The loan must be repaid at the **same branch** within `termDays` real days, from that branch vault or in cash. Part payments are allowed.
- `maxActive` limits open loans across all branches (default 1). `minAccountHours` can require the account to be a certain age first.
- Overdue loans get a one-off `latePenaltyPercent` charge. With `autoCollect = true` the bank then takes what it can from the player's branch balances (loan branch first) every `checkInterval` minutes, online or offline.
- Loan money that has been withdrawn as cash cannot be auto-collected; only branch balances are.

## Vault lockboxes (`Config.Lockbox`)
- One lockbox per player per branch. Each size has a `rent` per `Config.Lockbox.rent.periodDays`; the vault at that branch pays automatically, otherwise rent becomes overdue (deposits and upgrades are blocked) and the box is cleared after `graceDays`. Players can prepay up to `maxPrepayPeriods`. Existing boxes get a fresh period when you update.
- One lockbox per player per branch. Capacity is a total item count (25 = 25 gold bars).
- `sizes` sets the label, capacity and price of `small`, `medium` and `large`.
- `upgrade` lets the **small** box grow by `step` slots for `price` each, up to `maxSteps` times.
- `payWith = 'bank'` charges the branch vault (shown in the ledger); `'cash'` charges cash.
- Only items listed in `items` can be stored, and they must exist in RSG-Core's shared items:
  ```lua
  items = {
      resource_gold_bar   = true,
      resource_silver_bar = true,
  },
  ```
- Items are stored by name and count, so item metadata (durability, serials, etc.) is not kept. Only whitelist plain stackable items.
- Removing an item from the whitelist stops new deposits, but players can still take out what they already stored.
- Item images load from `imagePath` (rsg-inventory's image folder by default).

## Loan defaults and credit score
- `Config.Loans.default = { enabled, afterDays, seizeLockbox }`: a loan still unpaid `afterDays` after it became overdue (and after auto-collection) defaults. The loan is written off, the lockbox at that branch is seized (if `seizeLockbox`) and the player is notified.
- `Config.Credit`: everyone starts at `start` (600) within `min`-`max` (300-850). Repaying in full on time adds `repaidOnTime`, going late subtracts `wentLate`, defaulting subtracts `defaulted`. `tiers` set the interest adjustment and the maximum loan multiplier by score; a score under the lowest tier is refused credit.
- Bounty-hunter hook: listen for the event `rsg-banking:server:loanDefaulted` (see below) and add a bounty in your own bounty resource.

## Send money (`Config.Send`)
- Enter the recipient's citizen ID in the Wire tab. The sender pays `feePercent` (min `minFee`); the amount is capped by `max` per transfer and `daily` per 24 h.
- The recipient must have a home branch. The money is paid there even while they are offline, with a ledger entry and (optionally) a telegram receipt.

## Savings interest (`Config.Interest`)
- Every 24 hours personal branch balances at or above `minBalance` earn `percentPerDay`%, capped at `maxBalance` of balance per account. Business accounts do not earn interest.
- Paid in one SQL transaction with ledger entries. Force a payout from the server console with `bankinterestnow`.

## Business and gang accounts (`Config.Business`)
- The **Business** tab lists your current job and gang. The boss opens the account at a branch (`openFee`); everyone in the org can deposit.
- The boss maintains a withdrawal list (up to `maxMembers`, each limited to `memberLimit` per withdrawal). Authorisation is re-checked against the player's current job/gang on every action, so losing the job removes access immediately.
- Org accounts are stored in `rsg_bank_accounts` with the key `job:<name>` or `gang:<name>` as the citizen ID, so the balance exports work with them too.
- Other authorised members get a telegram alert on large movements.

## Telegram (`Config.Telegram`)
Needs rsg-telegram. Receipts for money sent to you, large movement alerts (`largeAmount`) and a **Send statement** button that mails your latest ledger lines (`statementLines`, cooldown `statementCooldown` s). Without rsg-telegram these features hide themselves.

## Bank robbery hook (`Config.Lock`)
```lua
exports['rsg-banking']:LockBranch('valentine', 600, 'robbery')   -- seconds, capped by Config.Lock.maxSeconds
exports['rsg-banking']:UnlockBranch('valentine')
exports['rsg-banking']:IsBranchLocked('valentine')               -- bool
```
A locked branch refuses every action, closes any open menu there and shows the blip as closed. Locks expire by themselves.

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
exports['rsg-banking']:GetHomeBranch(citizenid)                     -- bankId or nil
exports['rsg-banking']:AddHomeMoney(citizenid, amount, note)        -- bankId or false (pays into the home branch)
exports['rsg-banking']:GetLoans(citizenid)                          -- { { bank, principal, owed, late, due }, ... }
exports['rsg-banking']:HasActiveLoan(citizenid)                     -- bool
exports['rsg-banking']:GetLockboxItems(citizenid, bankId)           -- { [item] = amount }
exports['rsg-banking']:GetCreditScore(citizenid)                    -- number
exports['rsg-banking']:LockBranch(bankId, seconds, reason)          -- lock a branch (robbery)
exports['rsg-banking']:UnlockBranch(bankId)
exports['rsg-banking']:IsBranchLocked(bankId)                       -- bool
```

Server events other resources can listen to (server-side only):
```lua
AddEventHandler('rsg-banking:server:loanDefaulted', function(citizenid, bankId, owed, seizedItems) end)
AddEventHandler('rsg-banking:server:lockboxEvicted', function(citizenid, bankId, items) end)
```
Business accounts use the same balance exports with the key `job:<name>` / `gang:<name>`.

## Notes
- Branch balances are separate from RSG-Core's built-in `bank` money.
- The ledger table gets a `created_at` index automatically; `Config.HistoryDays` pruning runs at start and every 6 hours.
- Opening hours are checked in the client UI and again on the server against rsg-weather's clock, so a modified client can't bank after closing.

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
| `suspicious` | Transaction attempted away from a bank (max one alert per player per `spamWindow`), or repeated blocked/spammed requests (`spamThreshold` per `spamWindow`) |
| `export` | Another resource changed a balance via `AddBranchMoney` / `RemoveBranchMoney` (shows which resource) |
| `loan` | Loan taken, payment, cleared, overdue, auto-collected |
| `send` | Citizen-to-citizen transfer |
| `interest` | Interest payout run |
| `business` | Org account opened, deposit, withdrawal, member change |
| `lockbox` | Lockbox rented, enlarged, items stored / withdrawn |
| `system` | Resource start, database setup failures, missing tables |

Every player embed includes character name, citizen ID, server ID and the identifiers enabled in `showIdentifiers` (license and Discord by default; Steam and IP are off).
Messages are queued and sent one at a time, and Discord rate-limit responses are retried automatically.

## Languages
All player-facing text (notifications, prompts and the whole UI) comes from `locales/*.json`.
Included: `en`, `de`, `el`, `es`, `fr`, `ja`, `nl`, `pl`, `pt-br`, `ro`.
Set the language in server.cfg with rsg-core's convar, e.g. `setr rsg:locale "de"` (falls back to `ox:locale`, then `en`).
Discord webhook logs and console messages stay in English for staff.

## Changelog
### 3.1.0
- New: loan defaults with credit score, lockbox seizure and a bounty-hunter event
- New: send money to another citizen by ID (fee, limits, offline delivery)
- New: daily savings interest
- New: rsg-telegram receipts, large-transaction alerts and exportable statement
- New: business and gang shared accounts with a boss-managed withdrawal list
- New: branch lock exports and event for robbery scripts
- New: lockbox rent with auto-pay and eviction
- New tables `rsg_bank_credit`, `rsg_bank_business_members` and column `rsg_bank_lockboxes.rent_until` (automatic, or import `installation/update_3.1.0.sql` when `AutoDatabase = false`)
- All 10 locales updated and fully translated, including strings that were still English
### 3.0.6
- Fix: depositing into a lockbox now saves to the database before taking the item, so a database error can no longer destroy items (rolled back if the item can't be removed)
- Fix: a paycheck forwarded to the home branch is returned to RSG-Core bank money if the branch credit fails
- Fix: withdrawals check that the cash was actually paid out, otherwise the vault is credited back
- Fix: ledger notes from other resources are trimmed to 255 characters; `AddBranchMoney` / `RemoveBranchMoney` reject non-string ids
- UX: the bank menu also closes if the player dies or logs out; closing-time escort can no longer hang on a stuck screen fade
- UX/Config: lockbox sizes are read from `Config.Lockbox.sizes` (smallest first), so extra sizes you add appear in the menu
- Perf: new `created_at` index on the ledger (added automatically to existing tables) and the ledger is pruned every 6 hours, not just at start
- Cleanup: removed the unused `Bank.getBalance` helper

### 3.0.5
- Fix: Discord logs no longer ping the player on every transaction (only `largeMention` roles can be pinged)
- Fix: loan repayment only accepts `bank` or `cash` as the payment method
- Fix: `HasAccount` export returns false for unknown branch ids
- UX: clicking too fast now shows a "slow down" notice instead of silently doing nothing
- UX: amount fields clear after a successful deposit, withdrawal, wire or loan action
- Perf: deposit/withdraw skip the extra balance query when their webhook is disabled
- Cleanup: removed unused parameters and duplicated values

See `DOCS.md` for the technical reference.

## Support
Support the Project : https://rexshack.tebex.store/
