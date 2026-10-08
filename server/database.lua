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
                KEY `citizen_bank_idx` (`citizenid`, `bank`)
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

MySQL.ready(function()
    if not Config.AutoDatabase then
        local missing = {}
        for _, t in ipairs(tables) do
            if not tableExists(t.name) then missing[#missing + 1] = t.name end
        end
        if #missing > 0 then
            BankLog('system', nil, { { name = 'Missing Tables', value = table.concat(missing, ', ') } }, { description = 'Database tables missing' })
            log('^1', ('Missing tables: %s. Import installation/rsg_banking.sql or set Config.AutoDatabase = true'):format(table.concat(missing, ', ')))
            return
        end
        BankingDBReady = true
        pruneHistory()
        return
    end

    local ok, err = pcall(function()
        for _, t in ipairs(tables) do
            if not tableExists(t.name) then
                MySQL.query.await(t.sql)
                log('^2', ('Created table %s'):format(t.name))
            end
        end
    end)

    if ok then
        BankingDBReady = true
        log('^2', 'Database ready')
        BankLog('system', nil, nil, { description = 'Resource started - database ready' })
        pruneHistory()
    else
        log('^1', ('Automatic database setup failed: %s'):format(err))
        log('^1', 'Import installation/rsg_banking.sql manually.')
        BankLog('system', nil, { { name = 'Error', value = tostring(err) } }, { description = 'Automatic database setup FAILED' })
    end
end)
