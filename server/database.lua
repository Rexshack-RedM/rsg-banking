-----------------------------------------------------------------------
-- Automatic database setup
-- Creates the banking tables on resource start if they don't exist.
-- Disable with Config.AutoDatabase = false and import
-- installation/rsg_banking.sql manually instead.
-----------------------------------------------------------------------
BankingDBReady = false

local tables = {
    {
        name = 'rsg_bank_accounts',
        sql = [[
            CREATE TABLE IF NOT EXISTS `rsg_bank_accounts` (
                `id` INT(11) NOT NULL AUTO_INCREMENT,
                `citizenid` VARCHAR(50) NOT NULL,
                `bank` VARCHAR(50) NOT NULL,
                `balance` DECIMAL(12,2) NOT NULL DEFAULT 0.00,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                UNIQUE KEY `citizen_bank` (`citizenid`, `bank`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]
    },
    {
        name = 'rsg_bank_transactions',
        sql = [[
            CREATE TABLE IF NOT EXISTS `rsg_bank_transactions` (
                `id` INT(11) NOT NULL AUTO_INCREMENT,
                `citizenid` VARCHAR(50) NOT NULL,
                `bank` VARCHAR(50) NOT NULL,
                `type` VARCHAR(20) NOT NULL,
                `amount` DECIMAL(12,2) NOT NULL,
                `note` VARCHAR(255) DEFAULT NULL,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                KEY `citizen_bank_idx` (`citizenid`, `bank`),
                KEY `created_idx` (`created_at`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]
    },
    {
        name = 'rsg_bank_home',
        sql = [[
            CREATE TABLE IF NOT EXISTS `rsg_bank_home` (
                `citizenid` VARCHAR(50) NOT NULL,
                `bank` VARCHAR(50) NOT NULL,
                PRIMARY KEY (`citizenid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]
    },
    {
        name = 'rsg_bank_meta',
        sql = [[
            CREATE TABLE IF NOT EXISTS `rsg_bank_meta` (
                `k` VARCHAR(50) NOT NULL,
                `v` VARCHAR(255) DEFAULT NULL,
                PRIMARY KEY (`k`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]
    },
    {
        name = 'rsg_bank_loans',
        sql = [[
            CREATE TABLE IF NOT EXISTS `rsg_bank_loans` (
                `id` INT(11) NOT NULL AUTO_INCREMENT,
                `citizenid` VARCHAR(50) NOT NULL,
                `bank` VARCHAR(50) NOT NULL,
                `principal` DECIMAL(12,2) NOT NULL,
                `owed` DECIMAL(12,2) NOT NULL,
                `due_at` TIMESTAMP NOT NULL,
                `late` TINYINT(1) NOT NULL DEFAULT 0,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                UNIQUE KEY `citizen_bank` (`citizenid`, `bank`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]
    },
    {
        name = 'rsg_bank_lockboxes',
        sql = [[
            CREATE TABLE IF NOT EXISTS `rsg_bank_lockboxes` (
                `citizenid` VARCHAR(50) NOT NULL,
                `bank` VARCHAR(50) NOT NULL,
                `size` VARCHAR(20) NOT NULL,
                `upgrades` INT(11) NOT NULL DEFAULT 0,
                `rent_until` TIMESTAMP NULL DEFAULT NULL,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`citizenid`, `bank`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]
    },
    {
        name = 'rsg_bank_credit',
        sql = [[
            CREATE TABLE IF NOT EXISTS `rsg_bank_credit` (
                `citizenid` VARCHAR(50) NOT NULL,
                `score` INT(11) NOT NULL,
                `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`citizenid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]
    },
    {
        name = 'rsg_bank_business_members',
        sql = [[
            CREATE TABLE IF NOT EXISTS `rsg_bank_business_members` (
                `org` VARCHAR(80) NOT NULL,
                `citizenid` VARCHAR(50) NOT NULL,
                `name` VARCHAR(100) DEFAULT NULL,
                `added_by` VARCHAR(50) DEFAULT NULL,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`org`, `citizenid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]
    },
    {
        name = 'rsg_bank_lockbox_items',
        sql = [[
            CREATE TABLE IF NOT EXISTS `rsg_bank_lockbox_items` (
                `citizenid` VARCHAR(50) NOT NULL,
                `bank` VARCHAR(50) NOT NULL,
                `item` VARCHAR(100) NOT NULL,
                `amount` INT(11) NOT NULL DEFAULT 0,
                PRIMARY KEY (`citizenid`, `bank`, `item`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]
    },
}

local function log(color, msg)
    print(('[rsg-banking]%s %s^7'):format(color, msg))
end

local function tableExists(name)
    return (MySQL.scalar.await(
        'SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?', { name }) or 0) > 0
end

local function pruneHistory()
    local days = tonumber(Config.HistoryDays) or 0
    if days <= 0 then return end
    MySQL.update('DELETE FROM rsg_bank_transactions WHERE created_at < (NOW() - INTERVAL ? DAY)', { days }, function(n)
        if n and n > 0 then log('^3', ('Pruned %s old ledger entries'):format(n)) end
    end)
end

-- add the created_at index to ledgers created by older versions (non-destructive)
local function ensureLedgerIndex()
    local has = MySQL.scalar.await(
        "SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema = DATABASE() AND table_name = 'rsg_bank_transactions' AND index_name = 'created_idx'") or 0
    if has == 0 then
        MySQL.query.await('ALTER TABLE `rsg_bank_transactions` ADD INDEX `created_idx` (`created_at`)')
        log('^2', 'Added ledger index created_idx')
    end
end

-- add columns introduced after 3.0.5 to tables created by older versions (non-destructive)
local function columnExists(tbl, col)
    return (MySQL.scalar.await(
        'SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ?', { tbl, col }) or 0) > 0
end

local function ensureColumns()
    if not columnExists('rsg_bank_lockboxes', 'rent_until') then
        MySQL.query.await('ALTER TABLE `rsg_bank_lockboxes` ADD COLUMN `rent_until` TIMESTAMP NULL DEFAULT NULL')
        log('^2', 'Added column rsg_bank_lockboxes.rent_until')
    end
end

-- keep pruning while the server stays up (every 6 hours)
local function startPruneLoop()
    CreateThread(function()
        while true do
            Wait(6 * 60 * 60 * 1000)
            pruneHistory()
        end
    end)
end

MySQL.ready(function()
    if not Config.AutoDatabase then
        local missing = {}
        for _, t in ipairs(tables) do
            if not tableExists(t.name) then missing[#missing + 1] = t.name end
        end
        if #missing == 0 and tableExists('rsg_bank_lockboxes') and not columnExists('rsg_bank_lockboxes', 'rent_until') then
            missing[#missing + 1] = 'rsg_bank_lockboxes.rent_until (import installation/update_3.1.0.sql)'
        end
        if #missing > 0 then
            BankLog('system', nil, { { name = 'Missing Tables', value = table.concat(missing, ', ') } }, { description = 'Database tables missing' })
            log('^1', ('Missing tables: %s. Import installation/rsg_banking.sql or set Config.AutoDatabase = true'):format(table.concat(missing, ', ')))
            return
        end
        BankingDBReady = true
        pruneHistory()
        startPruneLoop()
        return
    end

    local ok, err = pcall(function()
        for _, t in ipairs(tables) do
            if not tableExists(t.name) then
                MySQL.query.await(t.sql)
                log('^2', ('Created table %s'):format(t.name))
            end
        end
        ensureLedgerIndex()
        ensureColumns()
    end)

    if ok then
        BankingDBReady = true
        log('^2', 'Database ready')
        BankLog('system', nil, nil, { description = 'Resource started - database ready' })
        pruneHistory()
        startPruneLoop()
    else
        log('^1', ('Automatic database setup failed: %s'):format(err))
        log('^1', 'Import installation/rsg_banking.sql manually.')
        BankLog('system', nil, { { name = 'Error', value = tostring(err) } }, { description = 'Automatic database setup FAILED' })
    end
end)
