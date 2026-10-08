# rsg-banking installation

1. Put `rsg-banking` in your resources folder and add `ensure rsg-banking` to server.cfg (after rsg-core, ox_lib and oxmysql).
2. Database (choose one):
   - Automatic (default): `Config.AutoDatabase = true` in `shared/config.lua`. Tables are created on first start.
   - Manual: set `Config.AutoDatabase = false` and import `installation/rsg_banking.sql` into your database.
3. Check the bank coordinates in `shared/config.lua` match your counters in-game.
