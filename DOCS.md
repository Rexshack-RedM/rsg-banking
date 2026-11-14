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
`locales/*.json` (en, de, el, es, fr, ja, nl, pl, pt-br, ro). Prefixes: `cl_` client, `sv_` server notify, `tx_` ledger notes, `tg_` telegram text, `ui_` NUI (all `ui_*` keys are sent to the NUI on first open).

## Console
- `bankinterestnow` – pays savings interest immediately (console only).
- `bankwebhooktest` – sends a test embed for every webhook event (console only).
