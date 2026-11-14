-- Manual upgrade from 3.0.x to 3.1.0 (only needed when Config.AutoDatabase = false)
-- Run each statement once. Fresh installs use rsg_banking.sql instead.

ALTER TABLE `rsg_bank_transactions` ADD INDEX `created_idx` (`created_at`);   -- skip if it already exists
ALTER TABLE `rsg_bank_lockboxes` ADD COLUMN `rent_until` TIMESTAMP NULL DEFAULT NULL;

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
