SET default_storage_engine = InnoDB; -- use InnoDB for referential integrity checks

DROP DATABASE IF EXISTS MoneyTracker;

CREATE DATABASE MoneyTracker
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

USE MoneyTracker;
SELECT DATABASE();
SHOW TABLES;

-- USERS
set auto_increment_offset=1;
set auto_increment_increment=1;

DROP TABLE IF EXISTS users;

CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT NOT NULL PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    password_hash VARCHAR(255) NOT NULL
);

-- ACCOUNTS
DROP TABLE IF EXISTS accounts;

CREATE TABLE IF NOT EXISTS accounts (
    id INT AUTO_INCREMENT NOT NULL PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    balance DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    last_updated TIMESTAMP NOT NULL
        DEFAULT CURRENT_TIMESTAMP,
    type ENUM('Cash', 'Credit Card', 'Savings') NOT NULL,
    user_id INT NOT NULL,
    FOREIGN KEY (user_id)
        REFERENCES users (id)
);

-- CATEGORIES
DROP TABLE IF EXISTS categories;

CREATE TABLE IF NOT EXISTS categories(
    id INT AUTO_INCREMENT NOT NULL PRIMARY KEY,
    name VARCHAR(50) UNIQUE NOT NULL,
    category_type ENUM ('Expense', 'Income') NOT NULL
);

-- TRANSACTIONS
DROP TABLE IF EXISTS transactions;

CREATE TABLE IF NOT EXISTS transactions(
    id INT AUTO_INCREMENT NOT NULL PRIMARY KEY,
    amount DECIMAL(10, 2) NOT NULL,
    description VARCHAR(255),
    transaction_date DATE NOT NULL,
    category_id INT NOT NULL,
    account_id INT NOT NULL,
        FOREIGN KEY (account_id)
            REFERENCES accounts (id),
        FOREIGN KEY (category_id)
            REFERENCES categories (id)
);


-- transaction_before_insert: before insert transaction: verify transaction
DELIMITER //
CREATE TRIGGER transaction_before_insert
BEFORE INSERT ON transactions
FOR EACH ROW
BEGIN
	IF NEW.transaction_date > CURDATE() THEN
		SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Transaction date cannot be in the future';
	END IF;

	IF NEW.amount IS NULL OR NEW.amount <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Transaction amount must be greater than zero';
    END IF;
END //
DELIMITER ;

-- transaction_after_insert: update balance, update last_updated field 
DELIMITER //
CREATE TRIGGER transaction_after_insert
AFTER INSERT ON transactions
FOR EACH ROW
BEGIN
	DECLARE lv_cat_type VARCHAR(10);

	SELECT category_type INTO lv_cat_type
    FROM categories
    WHERE id = NEW.category_id;
	
	UPDATE accounts
	SET balance = CASE
		WHEN lv_cat_type = 'Income' THEN balance + NEW.amount
		WHEN lv_cat_type = 'Expense' THEN balance - NEW.amount
		ELSE balance
	END,
	last_updated = NOW()
	WHERE id = NEW.account_id;
END //
DELIMITER ;

-- todo: add update transaction trigger

-- transaction_after_delete: after delete transaction rollback impact on account
DELIMITER //
CREATE TRIGGER transaction_after_delete
AFTER DELETE ON transactions
FOR EACH ROW
BEGIN
    DECLARE lv_cat_type VARCHAR(10);

    SELECT category_type INTO lv_cat_type
    FROM categories
    WHERE id = OLD.category_id;

    UPDATE accounts
    SET balance = CASE
          WHEN lv_cat_type = 'Income'  THEN balance - OLD.amount
          WHEN lv_cat_type = 'Expense' THEN balance + OLD.amount
          ELSE balance
      END,
        last_updated = NOW()
    WHERE id = OLD.account_id;
END //
DELIMITER ;

-- sp_get_transaction_between: get transactions between range of 2 dates
DELIMITER //
CREATE PROCEDURE sp_get_transaction_between(
    IN p_start_date DATE,
    IN p_end_date   DATE,
    IN p_account_id INT
)
BEGIN
    IF p_start_date IS NULL OR p_end_date IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Start and end dates are required';
    END IF;

    IF p_start_date > p_end_date THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Start date cannot be after end date';
    END IF;

    SELECT t.id AS transaction_id,
           t.account_id,
           t.transaction_date,
           c.category_type,
           t.amount,
           CASE c.category_type
               WHEN 'Income'  THEN  t.amount
               WHEN 'Expense' THEN -t.amount
               ELSE 0
           END AS signed_amount
    FROM transactions t
    JOIN categories c
    ON c.id = t.category_id
    WHERE t.transaction_date BETWEEN p_start_date AND p_end_date 
    AND (p_account_id IS NULL OR t.account_id = p_account_id)
    ORDER BY t.transaction_date, t.id;
END //
DELIMITER ;

-- sp_get_transactions_on_date()
DELIMITER //
CREATE PROCEDURE sp_get_transactions_on_date (
    IN p_date       DATE,
    IN p_account_id INT
)
BEGIN
    IF p_date IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Date is required';
    END IF;

    SELECT t.id AS transaction_id,
           t.account_id,
           t.transaction_date,
           c.category_type,
           t.amount,
           CASE c.category_type
               WHEN 'Income'  THEN  t.amount
               WHEN 'Expense' THEN -t.amount
               ELSE 0
           END AS signed_amount
	FROM transactions t
	JOIN categories c
	ON c.id = t.category_id
	WHERE t.transaction_date = p_date AND (p_account_id IS NULL OR t.account_id = p_account_id)
	ORDER BY t.transaction_date, t.id;
END //
DELIMITER ;

-- todo: function to show count of transactions made by account on date
-- todo: function to show balance of account on date

-- todo: add secondary indexes to 

-- call sp_get_transactions_on_date('2026-10-12', 2);

-- Testing
SHOW triggers;
SHOW PROCEDURE STATUS WHERE Db = 'MoneyTracker';
SHOW FUNCTION STATUS WHERE Db = 'MoneyTracker';