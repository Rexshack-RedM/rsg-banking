# rsg-banking – Technical Docs

## File layout
| File | Purpose |
|---|---|
| `shared/config.lua` | All gameplay config (banks, hours, fees, loans, lockboxes, doors, blips) |
| `server/sv_config.lua` | Server-only webhook config (never sent to clients) |
| `server/database.lua` | Auto table creation / missing-table check, ledger pruning. Sets `BankingDBReady` |
| `server/webhooks.lua` | `BankLog`, `BankLogActive`, `BankLogLarge`, `BankLogBlocked`, `BankLogSuspicious`, `BankMoney` |
| `server/server.lua` | Core helpers (`Bank` table), account/deposit/withdraw/wire/home callbacks, balance exports |
| `server/loans.lua` | Loan callbacks, overdue penalty + auto-collection loop, loan exports |
| `server/lockbox.lua` | Lockbox rent/upgrade/store/take callbacks, lockbox export |
| `server/homebank.lua` | Home branch, RSG-Core `bank` money forwarding, one-off legacy money migration |
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
- Balance changes are atomic SQL (`balance >= ?` guard on debit); every multi-step operation refunds on failure.
- Lockbox items must be whitelisted in `Config.Lockbox.items` **and** exist in `RSGCore.Shared.Items`.
- Loan repayments race-guarded against auto-collection (`owed >= ?`).

## Database tables
`rsg_bank_accounts`, `rsg_bank_transactions`, `rsg_bank_home`, `rsg_bank_meta`, `rsg_bank_loans`, `rsg_bank_lockboxes`, `rsg_bank_lockbox_items`.
Created automatically when `Config.AutoDatabase = true`; otherwise import `installation/rsg_banking.sql`.

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

## Events
- `rsg-banking:client:open` (client, bankId) – open a branch menu (other resources may trigger it).
- Listens to `RSGCore:Server:OnMoneyChange` (forwards core `bank` adds to the home branch) and `RSGCore:Server:PlayerLoaded` (sweeps legacy money).

## Exports
See the README "Server exports" section.

## Locales
`locales/*.json` (en, de, el, es, fr, ja, nl, pl, pt-br, ro). Prefixes: `cl_` client, `sv_` server notify, `tx_` ledger notes, `ui_` NUI (all `ui_*` keys are sent to the NUI on first open).

## Console
- `bankwebhooktest` – sends a test embed for every webhook event (console only).
