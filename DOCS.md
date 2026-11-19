# rsg-banking – Technical Docs

## File layout
| File | Purpose |
|---|---|
| `shared/config.lua` | All gameplay config (banks, hours, fees, loans, lockboxes, doors, blips) |
| `server/sv_config.lua` | Server-only webhook config (never sent to clients) |
| `server/database.lua` | Auto table creation / missing-table check, ledger pruning. Sets `BankingDBReady` |
| `server/webhooks.lua` | `BankLog`, `BankLogActive`, `BankLogLarge`, `BankLogBlocked`, `BankLogSuspicious`, `BankMoney` |
| `server/server.lua` | Core helpers (`Bank` table), account/deposit/withdraw/wire/home callbacks, balance exports |
| `server/lock.lua` | Branch lock state, exports, `getLocks` callback, expiry thread |
| `server/loans.lua` | Loan callbacks, credit score, overdue penalty, auto-collection and default handling |
| `server/lockbox.lua` | Lockbox rent/upgrade/store/take/payRent callbacks, rent processing loop, lockbox export |
| `server/homebank.lua` | Home branch, RSG-Core `bank` money forwarding, one-off legacy money migration |
| `server/sendmoney.lua` | Recipient lookup and send-to-citizen callback |
| `server/interest.lua` | Daily interest payout, `bankinterestnow` command |
| `server/business.lua` | Job/gang accounts and withdrawal list callbacks |
| `server/telegram.lua` | rsg-telegram receipts, large alerts, statement callback |
| `client/client.lua` | Prompts, blips, doors, closing-time handling, NUI bridge |
| `html/*` | NUI (vanilla JS, custom dropdowns, draggable panel) |

## Request flow
1. Prompt → `rsg-banking:client:open` → callback `rsg-banking:server:getData`.
2. Every NUI action → `nuiAction` → rsg-core callback with the current bank id first.
3. Server `Bank.guarded(src, bankId, fn)` checks, in order: DB ready, per-player lock, rate limit (`Config.Cooldown`, notifies `sv_slow_down`), server-side distance (`Config.ServerMaxDistance`), opening hours (rsg-weather clock), player exists.
4. The handler runs inside `pcall`; refreshed data is always returned so the UI re-renders.

## Security model
- Client never sends a bank id it can choose freely: the server re-checks distance to that bank's coords.
- Amounts: `validAmount` (number, finite, ≥ 0.01, ≤ `MaxTransaction`, rounded to cents). Lockbox qty: integer 1–100000.
- Lockbox deposits write the DB first and take the item second (rolled back on failure); withdrawals reserve the DB row first, then give the item.
- Paychecks forwarded from core `bank` money are returned if the branch credit fails; withdrawals check the cash payout and refund the vault on failure.
- Balance changes are atomic SQL (`balance >= ?` guard on debit); every multi-step operation refunds on failure.
- Lockbox items must be whitelisted in `Config.Lockbox.items` **and** exist in `RSGCore.Shared.Items`.
- Send money: sender debited first, recipient credited via home branch with rollback; fee, per-transfer max and a 24 h limit are all server-side; the recipient is looked up by citizen ID only (throttled, must be at a bank).
- Business accounts: authorisation is re-read from the player's live job/gang on every call; only the boss manages the list or opens the account; per-withdrawal limits apply.
- Interest runs in one SQL transaction and records `last_interest` before paying, so a crash cannot pay twice.
- Branch locks are server state, capped by `Config.Lock.maxSeconds`; lock events can only be triggered from the server (`AddEventHandler`).
- Lockbox rent and defaults use the database clock; seizing and eviction clear DB rows before notifying.
- Loan repayments race-guarded against auto-collection (`owed >= ?`).

## Database tables
`rsg_bank_accounts`, `rsg_bank_transactions`, `rsg_bank_home`, `rsg_bank_meta`, `rsg_bank_loans`, `rsg_bank_lockboxes`, `rsg_bank_lockbox_items`, `rsg_bank_credit`, `rsg_bank_business_members`. `rsg_bank_lockboxes` has a `rent_until` column; when upgrading with `AutoDatabase = false` import `installation/update_3.1.0.sql`.
Created automatically when `Config.AutoDatabase = true`; otherwise import `installation/rsg_banking.sql`. `rsg_bank_transactions` has a `created_idx` (`created_at`) index; existing tables get it added automatically. Old ledger rows are pruned at start and every 6 hours (`Config.HistoryDays`).

## Server callbacks
| Name | Args (after bankId) |
|---|---|
| `rsg-banking:server:getData` | – |
| `rsg-banking:server:openAccount` | – |
| `rsg-banking:server:setHome` | – |
| `rsg-banking:server:deposit` / `withdraw` | amount |
| `rsg-banking:server:transfer` | targetBankId, amount |
| `rsg-banking:server:takeLoan` | amount |
| `rsg-banking:server:repayLoan` | amount, method (`bank`/`cash`) |
| `rsg-banking:server:buyLockbox` | size |
| `rsg-banking:server:upgradeLockbox` | – |
| `rsg-banking:server:lockboxDeposit` / `lockboxWithdraw` | item, qty |
| `rsg-banking:server:payRent` | – |
| `rsg-banking:server:lookupRecipient` | citizenId |
| `rsg-banking:server:sendMoney` | citizenId, amount |
| `rsg-banking:server:sendStatement` | – |
| `rsg-banking:server:bizOpen` | orgKey |
| `rsg-banking:server:bizDeposit` / `bizWithdraw` | orgKey, amount |
| `rsg-banking:server:bizAddMember` / `bizRemoveMember` | orgKey, citizenId |
| `rsg-banking:server:getLocks` | – (no bankId) |

## Events
- `rsg-banking:client:open` (client, bankId) – open a branch menu (other resources may trigger it).
- Client: closes the menu on `RSGCore:Client:OnPlayerUnload`, on death, when walking away, or at closing time.
- Listens to `RSGCore:Server:OnMoneyChange` (forwards core `bank` adds to the home branch) and `RSGCore:Server:PlayerLoaded` (sweeps legacy money).

- Server events: `rsg-banking:server:lockBranch(bankId, seconds, reason)` / `unlockBranch(bankId)` (server-side only), `rsg-banking:server:loanDefaulted(citizenid, bankId, owed, seized)`, `rsg-banking:server:lockboxEvicted(citizenid, bankId, items)`.
- Client: `rsg-banking:client:branchLock(bankId, locked)` broadcasts lock state.

## Exports
See the README "Server exports" section.

## Locales
`locales/*.json` (en, de, el, es, fr, ja, nl, pl, pt-br, ro, ru). Prefixes: `cl_` client, `sv_` server notify, `tx_` ledger notes, `tg_` telegram text, `ui_` NUI (all `ui_*` keys are sent to the NUI on first open).

## Console
- `bankinterestnow` – pays savings interest immediately (console only).
- `bankwebhooktest` – sends a test embed for every webhook event (console only).

<!-- BEGIN AUTO-REFERENCE (generated from the code; re-run the generator instead of editing by hand) -->

## Technical reference

Generated from the source of **rsg-banking 3.1.0**. Names, arguments and defaults below are read straight from the code.

### Dependencies

`rsg-core`, `rsg-inventory`, `oxmysql`

### Database

Tables: `rsg_bank_accounts`, `rsg_bank_transactions`, `rsg_bank_home`, `rsg_bank_meta`, `rsg_bank_loans`, `rsg_bank_lockboxes`, `rsg_bank_credit`, `rsg_bank_business_members`, `rsg_bank_lockbox_items`.

Tables are created automatically on start while `Config.AutoDatabase = true` (default). Nothing is ever dropped or overwritten.
For a manual install set `Config.AutoDatabase = false` and import `installation/rsg_banking.sql` / `installation/update_3.1.0.sql` once.

```lua
-- shared/config.lua
Config.AutoDatabase = true -- false = import the SQL file yourself
```

### Configuration

| Option | Default | Notes |
|---|---|---|
| `Config.AutoDatabase` | `true` | create tables automatically on start (false = import installation/rsg_banking.sql) |
| `Config.OpenKey` | `'J'` | RSGCore.Shared.Keybinds key |
| `Config.ServerMaxDistance` | `5.0` | max distance from the bank for any transaction (server checked) |
| `Config.Cooldown` | `500` | ms between bank requests per player (anti-spam) |
| `Config.AllowPushToTalkWhileOpen` | `true` | While NUI is open, block game controls but allow push-to-talk. |
| `Config.PushToTalkControls` | `table` |  |
| `Config.MaxTransaction` | `100000` | per single deposit/withdraw/transfer |
| `Config.HistoryLimit` | `15` | transactions shown in the ledger |
| `Config.HistoryDays` | `30` | delete ledger entries older than this on start (0 = keep forever) |
| `Config.AccountOpenFee` | `5` | cash fee to open an account (0 = free) |
| `Config.UseHours` | `true` | Opening hours (in-game clock). Set Config.UseHours = false for 24/7 banks |
| `Config.OpenHour` | `7` |  |
| `Config.CloseHour` | `21` |  |
| `Config.Closing` | `table` | Closing time: stop players getting locked inside |
| `Config.DefaultHomeBank` | `'valentine'` | used by the migration for players with no accounts yet |
| `Config.ForwardCoreBank` | `true` | move money other scripts add to RSG-Core 'bank' into the home branch |
| `Config.MigrateCoreMoney` | `true` | one-off: move old bank/valbank/rhobank/blkbank/armbank money into branches |
| `Config.TransferFeePercent` | `5` | % fee charged on branch-to-branch wires |
| `Config.TransferMinFee` | `1` | minimum fee in $ |
| `Config.Loans` | `table` | and must be repaid (from the branch vault or cash) at the same branch. |
| `Config.Credit` | `table` | The highest tier a player's score reaches sets their loan terms. Below the lowest tier they can't borrow. |
| `Config.Interest` | `table` | Shared (business) accounts never earn interest. If the server was offline it pays once, never for missed perio |
| `Config.Send` | `table` | Send money to another citizen: arrives in their home branch (works while they are offline) |
| `Config.Business` | `table` | Business accounts: one shared account per job / gang per branch. The boss opens it and decides who may withdra |
| `Config.Telegram` | `table` | Telegrams (needs rsg-telegram). Receipts are written straight into its inbox. |
| `Config.Lock` | `table` | to shut a branch's services while it is being robbed. A lock always expires after `maxSeconds`. |
| `Config.Lockbox` | `table` | Capacity is total item count (e.g. 25 = 25 gold bars). |
| `Config.Blip` | `table` | Blip |
| `Config.Banks` | `table` | Each bank is its own institution: money deposited here stays here. |
| `Config.BankDoors` | `table` | state = 1 -> always locked (vaults, back rooms) |

### Exports

**Server**

| Export | Arguments | File |
|---|---|---|
| `GetHomeBranch` | `` | `server/homebank.lua` |
| `AddHomeMoney` | `` | `server/homebank.lua` |
| `SweepCoreBank` | `` | `server/homebank.lua` |
| `GetLoans` | `citizenid` | `server/loans.lua` |
| `GetCreditScore` | `citizenid` | `server/loans.lua` |
| `HasActiveLoan` | `citizenid` | `server/loans.lua` |
| `LockBranch` | `` | `server/lock.lua` |
| `UnlockBranch` | `` | `server/lock.lua` |
| `IsBranchLocked` | `` | `server/lock.lua` |
| `GetLockboxItems` | `citizenid, bankId` | `server/lockbox.lua` |
| `HasAccount` | `citizenid, bankId` | `server/server.lua` |
| `GetBranchBalance` | `citizenid, bankId` | `server/server.lua` |
| `GetTotalBalance` | `citizenid` | `server/server.lua` |
| `AddBranchMoney` | `citizenid, bankId, amount, note` | `server/server.lua` |
| `RemoveBranchMoney` | `citizenid, bankId, amount, note` | `server/server.lua` |

```lua
-- example
local result = exports['rsg-banking']:GetHomeBranch()
```

### Events

Server events can be fired by any client, so every handler re-validates the player, the arguments and any permission, distance or cooldown on the server. Never add a reward to a handler without those checks.

| Event | Side | Arguments | File |
|---|---|---|---|
| `rsg-banking:client:open` | client | `bankId` | `client/client.lua` |
| `rsg-banking:client:branchLock` | client | `bankId, locked` | `client/client.lua` |
| `RSGCore:Client:OnPlayerUnload` | client | `` | `client/client.lua` |

```lua
-- from a server script
TriggerClientEvent('rsg-banking:client:open', source, bankId)
```

### Commands

| Command | Notes | File |
|---|---|---|
| `/bankinterestnow` |  | `server/interest.lua` |
| `/bankwebhooktest` |  | `server/webhooks.lua` |

### Locales

Language files in `locales/`: `de`, `el`, `en`, `es`, `fr`, `ja`, `nl`, `pl`, `pt-br`, `ro`, `ru`. Set the language with `setr rsg:locale "en"`.

<!-- END AUTO-REFERENCE -->
