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


