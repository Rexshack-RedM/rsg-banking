<img width="2948" height="497" alt="rsg_framework" src="https://github.com/user-attachments/assets/638791d8-296d-4817-a596-785325c1b83a" />

# 💰 rsg-banking
**Town banking with deposits, withdrawals, safe deposit boxes, money clips, and NPC clerks — for RSG Core.**

![Platform](https://img.shields.io/badge/platform-RedM-darkred)
![License](https://img.shields.io/badge/license-GPL--3.0-green)

> Fully localized bank UI per town money type (Valentine, Rhodes, Saint Denis, Blackwater, Armadillo…).  
> Includes player‑to‑player cash transfer, safe deposit stashes, and cash/blood money clips.

---

## 🛠️ Dependencies
- **rsg-core** (framework & prompts)  
- **ox_lib** (locales, dialogs, notifications)  
- **rsg-inventory** (safe deposit box & items)

**Locales included:** `en`, `fr`, `es`, `it`, `pt-br`, `el`, `ro`  
**License:** GPL‑3.0

---

## ✨ Features
- 🏦 **Per‑town bank balances** using distinct money types (e.g. `valbank`, `rhobank`, …).  
- 👨‍💼 **NPC bank clerks** with blips at configured coordinates.  
- 🕒 **Open/close hours** with “Bank Closed” message when outside hours.  
- 📦 **Safe Deposit Box** (weight/slots configurable) per character & town.  
- 💸 **Withdraw / Deposit** (optional withdraw fee).  
- 💰 **Cash on Hand display** — shows player’s current cash balance in the bank UI.  
- 💵 **Make & use Money Clips** (cash) and **Blood Money Clips** (bloodmoney).  
- 🤝 **Give Money** to a chosen PlayerID (with validation & notifications).  
- 🔔 **Discord Webhook Logging** — tracks withdrawals, deposits, transfers, and money clips with role mentions for high-value transactions.  
- 🚪 **Bank door presets** (vault/inner door states) applied on client.  
- 🌍 **Multi‑language** via `ox_lib.locale()` and NUI.

---

## ⚙️ Configuration (`config.lua`)

```lua
Config = {}

-- NPC / spawn
Config.DistanceSpawn = 20.0
Config.FadeIn = true

-- Safe deposit box
Config.StorageMaxWeight = 500000
Config.StorageMaxSlots  = 5

-- General settings
Config.Keybind    = 'J'
Config.OpenTime   = 9     -- 24h
Config.CloseTime  = 17    -- 24h
Config.AlwaysOpen = true  -- force banks open
Config.UseTarget  = false -- use rsg-core prompts if false

-- Optional fee when withdrawing (percent)
Config.WithdrawChargeRate = 0
```

### Discord Webhook Configuration (`server/discord_webhook.lua`)
```lua
Config.Discord = {
    WebhookURL = "", -- Add your Discord webhook URL here
    RoleID = "",     -- Discord role ID to mention for high-value transactions
    Enabled = true,
    TransactionThreshold = 0,    -- Minimum amount to log (0 = log all)
    RoleMentionThreshold = 1000, -- Minimum amount to trigger role mention
    Color = 16711680,            -- Embed color (decimal format)
    
    -- Track specific transaction types
    TrackWithdrawals = true,
    TrackDeposits = true,
    TrackTransfers = true,
    TrackMoneyClips = true,
}
```

### Bank locations
```lua
Config.BankLocations = {
  { name = 'Valentine Bank', bankid = 'valbank', moneytype = 'valbank', coords = vector3(-308.4189, 775.8842, 118.7017),
    npcmodel = 'S_M_M_BankClerk_01', npccoords = vector4(-308.14, 773.98, 118.7, 4.75), showblip = true, blipsprite = 'blip_proc_bank', blipscale = 0.2 },
  { name = 'Rhodes Bank',    bankid = 'rhobank', moneytype = 'rhobank', coords = vector3(1292.307, -1301.539, 77.04012),
    npcmodel = 'S_M_M_BankClerk_01', npccoords = vector4(1291.22, -1303.28, 77.04, 316.53), showblip = true, blipsprite = 'blip_proc_bank', blipscale = 0.2 },
  -- ... (Saint Denis, Blackwater, Armadillo, etc. are defined similarly)
}
```

### Bank door presets
```lua
Config.BankDoors = {
  -- saint denis, valentine ... (multiple entries)
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
```

---

## 🧭 How it works

- **Prompts or Target:** If `UseTarget = false`, rsg‑core prompts are created at each bank to open the UI and to **Give Money**.  
- **Per‑bank money type:** The UI operates on the `moneytype` configured for that bank (e.g., `valbank`).  
- **Transactions:** Server event `rsg-banking:server:transact` handles:  
  1) **Withdraw**, 2) **Deposit**, 3) **Create Money Clip** (deducts from bank and adds `money_clip` with `info.money`).  
- **Money Clips:** `money_clip` (and blood variant) are usable items; on use, the contained amount is paid out and the item is removed.  
- **Give Money:** Client shows an input (PlayerID + amount) → server validates and transfers cash.  
- **Safe Deposit:** Opens a stash named `safedeposit_<citizenid><town>` with your configured capacity.

---

## 🧺 Inventory items

```lua
money_clip       = { name = 'money_clip',       label = 'Money Clip',        weight = 50,  type = 'item', image = 'money_clip.png',       unique = true,  useable = true, decay = 0, delete = true, shouldClose = true, description = 'A clip of cash; contains a stored amount.' },
blood_money_clip = { name = 'blood_money_clip', label = 'Blood Money Clip',  weight = 50,  type = 'item', image = 'blood_money_clip.png', unique = true,  useable = true, decay = 0, delete = true, shouldClose = true, description = 'A clip of blood money; contains a stored amount.' },
```

> The amount is stored in `item.info.money` when created by the bank UI.

---

## 🔔 Discord Webhook Setup

1. Create a webhook in your Discord server:
   - Go to **Server Settings** > **Integrations** > **Webhooks**
   - Click **New Webhook** and copy the webhook URL

2. Edit `server/discord_webhook.lua`:
   ```lua
   Config.Discord = {
       WebhookURL = "https://discord.com/api/webhooks/YOUR_WEBHOOK_URL",
       RoleID = "1234567890123456789", -- Optional: Role to mention for high-value transactions
       Enabled = true,
       TransactionThreshold = 0,    -- Set to minimum $ to log (0 = all)
       RoleMentionThreshold = 1000, -- $ amount to trigger role ping
   }
   ```

3. **Transaction Types Tracked:**
   - 💸 **Withdrawals** (red embed)
   - 💵 **Deposits** (green embed)
   - 🤝 **Player-to-Player Transfers** (blue embed)
   - 📎 **Money Clip Creation** (gold embed)

4. Each webhook includes:
   - Player name(s)
   - Transaction amount (formatted with commas)
   - Transaction type
   - Timestamp
   - 🚨 **High-value alert** with role mention when amount exceeds `RoleMentionThreshold`

---

## 📋 Installation
1. Add `rsg-banking` to `resources/[rsg]`.  
2. Ensure `rsg-core`, `ox_lib`, and `rsg-inventory` are installed.  
3. (Optional) Add item images to your inventory UI (`money_clip.png`, `blood_money_clip.png`).  
4. In `server.cfg`:
   ```cfg
   ensure ox_lib
   ensure rsg-core
   ensure rsg-inventory
   ensure rsg-banking
   ```
5. Restart the server.

---

## 🌍 Locales
```json
{
  "cl_lang_1": "Open Bank",
  "cl_lang_2": "Bank Closed",
  "cl_lang_5": "Give Money",
  "cl_lang_8": "Give cash to PlayerID:",
  "cl_lang_9": "Amount to give",
  "sv_lang": "Safe Deposit Box",
  "sv_lang_3": "Money Clip Used",
  "sv_lang_4": "You've got $",
  "sv_lang_6": "Make Money Clip",
  "sv_lang_9": "Converted",
  "sv_lang_12": "You took out",
  "sv_lang_14": "Make Blood Money Clip",
  "sv_lang_16": "Blood Money Clip Converted",
  "ui_bank_account": "Bank Account",
  "ui_banking": "Banking",
  "ui_cash_on_hand": "Cash on Hand",
  "ui_withdraw": "Withdraw",
  "ui_deposit": "Deposit"
}
```

---

## 💎 Credits
- **Sinatra#0101** — original resource  
- **${boss}** — target "give player money" feature
- **RSG / Rexshack-RedM** — framework integration & localization support  
- **Community translators** — multi-language support
- License: GPL‑3.0
