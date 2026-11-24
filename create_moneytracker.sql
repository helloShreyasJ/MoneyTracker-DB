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
    email VARCHAR(255) UNIQUE NOT NULL,
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
    type ENUM('Cash', 'Debit Card', 'Savings') NOT NULL,
    user_id INT NOT NULL,
    FOREIGN KEY (user_id)
        REFERENCES users (id)
);

CREATE INDEX accounts_user_idx ON accounts (user_id);

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

CREATE INDEX transactions_date_idx ON transactions (transaction_date);
CREATE INDEX transactions_account_idx ON transactions (account_id);
CREATE INDEX transactions_category_idx ON transactions (category_id);

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

	IF NEW.amount <= 0 THEN
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

-- transaction_after_update: correct account balance after existing transaction updated
DELIMITER //
CREATE TRIGGER transaction_after_update
AFTER UPDATE ON transactions
FOR EACH ROW
BEGIN
	DECLARE lv_old_type VARCHAR(10);
	DECLARE lv_new_type VARCHAR(10);

	SELECT category_type INTO lv_old_type
	FROM categories WHERE id = OLD.category_id;

	SELECT category_type INTO lv_new_type
	FROM categories WHERE id = NEW.category_id;

	 UPDATE accounts
	SET balance = CASE
		WHEN lv_old_type = 'Income'  THEN balance - OLD.amount
		WHEN lv_old_type = 'Expense' THEN balance + OLD.amount
	END,
	last_updated = NOW()
	WHERE id = OLD.account_id;

	UPDATE accounts
	SET balance = CASE
			WHEN lv_new_type = 'Income'  THEN balance + NEW.amount
			WHEN lv_new_type = 'Expense' THEN balance - NEW.amount
		END,
		last_updated = NOW()
	WHERE id = NEW.account_id;
END //
DELIMITER ;

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

-- sp_get_transaction_between: get transactions made by account between range of 2 dates
DELIMITER //
CREATE PROCEDURE sp_get_transaction_between(
    IN p_start_date DATE,
    IN p_end_date DATE,
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

-- sp_get_transactions_on_date(): get transactions made by account on date
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

-- sp_transfer() transfer funds between accounts
DELIMITER //
CREATE PROCEDURE sp_transfer (
	IN p_from_account INT,
    IN p_to_account INT,
    IN p_amount DECIMAL (10, 2)
)
BEGIN
	DECLARE lv_found INT;

	DECLARE EXIT HANDLER FOR SQLEXCEPTION
	BEGIN
		ROLLBACK;
		RESIGNAL;
	END;
    
     IF  p_from_account IS NULL OR p_to_account IS NULL THEN
		SIGNAL SQLSTATE '45000'
			SET MESSAGE_TEXT = 'Accounts cannot be null';
    END IF;
    
    IF  p_from_account = p_to_account THEN
		SIGNAL SQLSTATE '45000'
			SET MESSAGE_TEXT = 'Cannot transfer to the same account';
    END IF;
    
    IF  p_amount <= 0 THEN
		SIGNAL SQLSTATE '45000'
			SET MESSAGE_TEXT = 'Transfer amount must be positive';
    END IF;
        
	START TRANSACTION;
		SELECT COUNT(*) INTO lv_found
        FROM accounts
        WHERE id = p_from_account OR id = p_to_account
        FOR UPDATE;
        
        IF lv_found <> 2 THEN
			SIGNAL SQLSTATE '45000'
				SET MESSAGE_TEXT = 'Source or destination account does not exist';
		END IF;
    
		UPDATE accounts
        SET balance = balance - p_amount, last_updated = NOW()
        WHERE id = p_from_account;
        UPDATE accounts
        SET balance = balance + p_amount, last_updated = NOW()
        WHERE id = p_to_account;
    COMMIT;    
END //
DELIMITER ;

-- fn_count_transactions_on_date: function to show count of transactions made by account on date
DELIMITER //
CREATE FUNCTION fn_count_transactions_on_date(in_account_id INT, in_date DATE)
RETURNS INT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
	DECLARE lv_count INT;

	SELECT COUNT(*) INTO lv_count
	FROM transactions
	WHERE account_id = in_account_id AND transaction_date = in_date;
    
    RETURN lv_count;
END //
DELIMITER ;



