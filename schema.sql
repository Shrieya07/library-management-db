-- =====================================================
-- Library Management System - MySQL 8.0+ schema
-- =====================================================
DROP DATABASE IF EXISTS library_db;
CREATE DATABASE library_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE library_db;

-- ---------- Users ----------
CREATE TABLE users (
    user_id       INT AUTO_INCREMENT PRIMARY KEY,
    full_name     VARCHAR(100) NOT NULL,
    email         VARCHAR(120) NOT NULL UNIQUE,
    phone         VARCHAR(20),
    role          ENUM('member','librarian','admin') NOT NULL DEFAULT 'member',
    status        ENUM('active','suspended','closed') NOT NULL DEFAULT 'active',
    joined_on     DATE NOT NULL DEFAULT (CURRENT_DATE)
) ENGINE=InnoDB;

-- ---------- Catalog ----------
CREATE TABLE authors (
    author_id  INT AUTO_INCREMENT PRIMARY KEY,
    name       VARCHAR(100) NOT NULL
) ENGINE=InnoDB;

CREATE TABLE categories (
    category_id INT AUTO_INCREMENT PRIMARY KEY,
    name        VARCHAR(60) NOT NULL UNIQUE
) ENGINE=InnoDB;

CREATE TABLE books (
    book_id        INT AUTO_INCREMENT PRIMARY KEY,
    isbn           VARCHAR(20) NOT NULL UNIQUE,
    title          VARCHAR(200) NOT NULL,
    category_id    INT NOT NULL,
    publisher      VARCHAR(100),
    published_year SMALLINT,
    CONSTRAINT fk_books_category FOREIGN KEY (category_id)
        REFERENCES categories(category_id) ON DELETE RESTRICT,
    INDEX idx_books_title (title)
) ENGINE=InnoDB;

-- Many-to-many: a book can have several authors
CREATE TABLE book_authors (
    book_id   INT NOT NULL,
    author_id INT NOT NULL,
    PRIMARY KEY (book_id, author_id),
    FOREIGN KEY (book_id)   REFERENCES books(book_id)     ON DELETE CASCADE,
    FOREIGN KEY (author_id) REFERENCES authors(author_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- Physical copies of a book (one book -> many copies)
CREATE TABLE book_copies (
    copy_id    INT AUTO_INCREMENT PRIMARY KEY,
    book_id    INT NOT NULL,
    barcode    VARCHAR(30) NOT NULL UNIQUE,
    status     ENUM('available','issued','lost','maintenance') NOT NULL DEFAULT 'available',
    FOREIGN KEY (book_id) REFERENCES books(book_id) ON DELETE CASCADE,
    INDEX idx_copies_status (book_id, status)
) ENGINE=InnoDB;

-- ---------- Transactions ----------
CREATE TABLE loans (
    loan_id      INT AUTO_INCREMENT PRIMARY KEY,
    copy_id      INT NOT NULL,
    user_id      INT NOT NULL,
    issued_by    INT NULL,                       -- librarian who issued it
    issue_date   DATE NOT NULL,
    due_date     DATE NOT NULL,
    return_date  DATE NULL,
    CONSTRAINT chk_due_after_issue CHECK (due_date >= issue_date),
    CONSTRAINT chk_return_after_issue CHECK (return_date IS NULL OR return_date >= issue_date),
    FOREIGN KEY (copy_id)   REFERENCES book_copies(copy_id),
    FOREIGN KEY (user_id)   REFERENCES users(user_id),
    FOREIGN KEY (issued_by) REFERENCES users(user_id),
    INDEX idx_loans_user (user_id, return_date),
    INDEX idx_loans_due (return_date, due_date)
) ENGINE=InnoDB;

CREATE TABLE fines (
    fine_id    INT AUTO_INCREMENT PRIMARY KEY,
    loan_id    INT NOT NULL UNIQUE,
    amount     DECIMAL(8,2) NOT NULL CHECK (amount >= 0),
    paid       BOOLEAN NOT NULL DEFAULT FALSE,
    created_on DATE NOT NULL DEFAULT (CURRENT_DATE),
    FOREIGN KEY (loan_id) REFERENCES loans(loan_id)
) ENGINE=InnoDB;

CREATE TABLE reservations (
    reservation_id INT AUTO_INCREMENT PRIMARY KEY,
    book_id        INT NOT NULL,
    user_id        INT NOT NULL,
    reserved_on    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status         ENUM('waiting','fulfilled','cancelled') NOT NULL DEFAULT 'waiting',
    FOREIGN KEY (book_id) REFERENCES books(book_id),
    FOREIGN KEY (user_id) REFERENCES users(user_id)
) ENGINE=InnoDB;

-- ---------- Views ----------
CREATE VIEW v_book_availability AS
SELECT b.book_id, b.title, b.isbn,
       COUNT(c.copy_id)                         AS total_copies,
       SUM(c.status = 'available')              AS available_copies
FROM books b
LEFT JOIN book_copies c ON c.book_id = b.book_id
GROUP BY b.book_id, b.title, b.isbn;

CREATE VIEW v_overdue_loans AS
SELECT l.loan_id, u.full_name, u.email, b.title, bc.barcode,
       l.issue_date, l.due_date,
       DATEDIFF(CURRENT_DATE, l.due_date) AS days_overdue
FROM loans l
JOIN users u        ON u.user_id = l.user_id
JOIN book_copies bc ON bc.copy_id = l.copy_id
JOIN books b        ON b.book_id = bc.book_id
WHERE l.return_date IS NULL AND l.due_date < CURRENT_DATE;

-- ---------- Stored procedures ----------
DELIMITER //

-- Issue a copy to a user (max 5 active loans, no unpaid fines)
CREATE PROCEDURE issue_book(
    IN p_copy_id INT, IN p_user_id INT, IN p_librarian_id INT, IN p_days INT)
BEGIN
    DECLARE v_status VARCHAR(20);
    DECLARE v_user_status VARCHAR(20);
    DECLARE v_active INT;
    DECLARE v_unpaid INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN ROLLBACK; RESIGNAL; END;

    START TRANSACTION;

    SELECT status INTO v_status FROM book_copies WHERE copy_id = p_copy_id FOR UPDATE;
    SELECT status INTO v_user_status FROM users WHERE user_id = p_user_id;

    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Copy does not exist';
    ELSEIF v_status <> 'available' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Copy is not available';
    ELSEIF v_user_status IS NULL OR v_user_status <> 'active' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'User is not active';
    END IF;

    SELECT COUNT(*) INTO v_active FROM loans
     WHERE user_id = p_user_id AND return_date IS NULL;
    IF v_active >= 5 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Loan limit (5) reached';
    END IF;

    SELECT COUNT(*) INTO v_unpaid FROM fines f
      JOIN loans l ON l.loan_id = f.loan_id
     WHERE l.user_id = p_user_id AND f.paid = FALSE;
    IF v_unpaid > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'User has unpaid fines';
    END IF;

    INSERT INTO loans (copy_id, user_id, issued_by, issue_date, due_date)
    VALUES (p_copy_id, p_user_id, p_librarian_id, CURRENT_DATE,
            DATE_ADD(CURRENT_DATE, INTERVAL p_days DAY));

    UPDATE book_copies SET status = 'issued' WHERE copy_id = p_copy_id;

    COMMIT;
    SELECT LAST_INSERT_ID() AS loan_id;
END //

-- Return a book; creates a fine of 2.00 per overdue day
CREATE PROCEDURE return_book(IN p_loan_id INT)
BEGIN
    DECLARE v_copy INT;
    DECLARE v_due DATE;
    DECLARE v_returned DATE;
    DECLARE v_late INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN ROLLBACK; RESIGNAL; END;

    START TRANSACTION;

    SELECT copy_id, due_date, return_date INTO v_copy, v_due, v_returned
      FROM loans WHERE loan_id = p_loan_id FOR UPDATE;

    IF v_copy IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Loan does not exist';
    ELSEIF v_returned IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Book already returned';
    END IF;

    UPDATE loans SET return_date = CURRENT_DATE WHERE loan_id = p_loan_id;
    UPDATE book_copies SET status = 'available' WHERE copy_id = v_copy;

    SET v_late = GREATEST(DATEDIFF(CURRENT_DATE, v_due), 0);
    IF v_late > 0 THEN
        INSERT INTO fines (loan_id, amount) VALUES (p_loan_id, v_late * 2.00);
    END IF;

    COMMIT;
    SELECT p_loan_id AS loan_id, v_late AS days_late, v_late * 2.00 AS fine_amount;
END //

DELIMITER ;
