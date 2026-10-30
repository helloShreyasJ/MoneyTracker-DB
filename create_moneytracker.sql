SET default_storage_engine = InnoDB; -- default storage engine InnoDB to 

DROP DATABASE IF EXISTS MoneyTracker;

CREATE DATABASE MoneyTracker
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

USE MoneyTracker;
SELECT DATABASE();
SHOW TABLES;

DROP TABLE IF EXISTS users;

set auto_increment_offset=1;
set auto_increment_increment=1;

CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT NOT NULL PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    password VARCHAR(225) NOT NULL
);

DROP TABLE IF EXISTS accounts;

CREATE TABLE IF NOT EXISTS accounts (
    id INT AUTO_INCREMENT NOT NULL PRIMARY KEY,
    balance DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    last_updated TIMESTAMP NOT NULL
        DEFAULT CURRENT_TIMESTAMP,
    type ENUM('Cash', 'Credit Card') NOT NULL,
    user_id INT NOT NULL,
    FOREIGN KEY (user_id)
        REFERENCES users (id)
);

DROP TABLE IF EXISTS categories;

CREATE TABLE IF NOT EXISTS categories(
    id INT AUTO_INCREMENT NOT NULL PRIMARY KEY,
    name VARCHAR(50) UNIQUE NOT NULL,
    category_type ENUM ('Expense', 'Income') NOT NULL
);

DROP TABLE IF EXISTS transactions;

CREATE TABLE IF NOT EXISTS transactions(
    id INT AUTO_INCREMENT NOT NULL PRIMARY KEY,
    amount DECIMAL(10, 2) NOT NULL,
        CONSTRAINT check_amount_positive CHECK (amount > 0),
    description VARCHAR(255),
    transaction_date DATE NOT NULL,
    category_id INT NOT NULL,
    account_id INT NOT NULL,
    FOREIGN KEY (account_id)
        REFERENCES accounts (id),
    FOREIGN KEY (category_id)
        REFERENCES categories (id)
);