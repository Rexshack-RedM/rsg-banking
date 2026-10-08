CREATE TABLE IF NOT EXISTS `rsg_bank_accounts` (
    `id` INT(11) NOT NULL AUTO_INCREMENT,
    `citizenid` VARCHAR(50) NOT NULL,
    `bank` VARCHAR(50) NOT NULL,
    `balance` DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `citizen_bank` (`citizenid`, `bank`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

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

CREATE TABLE IF NOT EXISTS `rsg_bank_home` (
    `citizenid` VARCHAR(50) NOT NULL,
    `bank` VARCHAR(50) NOT NULL,
    PRIMARY KEY (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `rsg_bank_meta` (
    `k` VARCHAR(50) NOT NULL,
    `v` VARCHAR(255) DEFAULT NULL,
    PRIMARY KEY (`k`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
