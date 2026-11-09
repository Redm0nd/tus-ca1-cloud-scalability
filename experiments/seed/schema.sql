CREATE DATABASE IF NOT EXISTS servicedb;
USE servicedb;

DROP TABLE IF EXISTS product;
DROP TABLE IF EXISTS coupon;

CREATE TABLE coupon (
  id        BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  code      VARCHAR(255) NOT NULL UNIQUE,
  discount  DECIMAL(8,3) NOT NULL,
  exp_date  VARCHAR(255)
);

CREATE TABLE product (
  id          BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  name        VARCHAR(255),
  description VARCHAR(255),
  price       DECIMAL(8,3),
  coupon_code VARCHAR(255)
);

INSERT INTO coupon (code, discount, exp_date) VALUES
  ('SAVE10',      10.000, '2030-12-31'),
  ('SAVE20',      20.000, '2030-12-31'),
  ('BLACKFRIDAY',  5.000, '2030-12-31');
