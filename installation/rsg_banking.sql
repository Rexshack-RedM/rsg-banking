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
    KEY `citizen_bank_idx` (`citizenid`, `bank`),
    KEY `created_idx` (`created_at`)
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

CREATE TABLE IF NOT EXISTS `rsg_bank_lockboxes` (
    `citizenid` VARCHAR(50) NOT NULL,
    `bank` VARCHAR(50) NOT NULL,
    `size` VARCHAR(20) NOT NULL,
    `upgrades` INT(11) NOT NULL DEFAULT 0,
    `rent_until` TIMESTAMP NULL DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`citizenid`, `bank`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `rsg_bank_lockbox_items` (
    `citizenid` VARCHAR(50) NOT NULL,
    `bank` VARCHAR(50) NOT NULL,
    `item` VARCHAR(100) NOT NULL,
    `amount` INT(11) NOT NULL DEFAULT 0,
    PRIMARY KEY (`citizenid`, `bank`, `item`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `rsg_bank_credit` (
    `citizenid` VARCHAR(50) NOT NULL,
    `score` INT(11) NOT NULL,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `rsg_bank_business_members` (
    `org` VARCHAR(80) NOT NULL,
    `citizenid` VARCHAR(50) NOT NULL,
    `name` VARCHAR(100) DEFAULT NULL,
    `added_by` VARCHAR(50) DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`org`, `citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
