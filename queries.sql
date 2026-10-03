USE library_db;

-- 1. ISSUE a book (copy 1 to user 2, issued by librarian 1, for 14 days)
CALL issue_book(1, 2, 1, 14);

-- 2. RETURN a book (loan 1)
CALL return_book(1);

-- 3. Search books with authors and availability
SELECT b.title, GROUP_CONCAT(a.name SEPARATOR ', ') AS authors,
       v.available_copies, v.total_copies
FROM books b
JOIN book_authors ba ON ba.book_id = b.book_id
JOIN authors a       ON a.author_id = ba.author_id
JOIN v_book_availability v ON v.book_id = b.book_id
WHERE b.title LIKE '%Database%'
GROUP BY b.book_id, v.available_copies, v.total_copies;

-- 4. Books currently issued to a user
SELECT l.loan_id, b.title, l.issue_date, l.due_date
FROM loans l
JOIN book_copies bc ON bc.copy_id = l.copy_id
JOIN books b        ON b.book_id = bc.book_id
WHERE l.user_id = 2 AND l.return_date IS NULL;

-- 5. Overdue books (uses view)
SELECT * FROM v_overdue_loans ORDER BY days_overdue DESC;

-- 6. Full borrowing history of a user
SELECT b.title, l.issue_date, l.due_date, l.return_date,
       COALESCE(f.amount, 0) AS fine
FROM loans l
JOIN book_copies bc ON bc.copy_id = l.copy_id
JOIN books b        ON b.book_id = bc.book_id
LEFT JOIN fines f   ON f.loan_id = l.loan_id
WHERE l.user_id = 2
ORDER BY l.issue_date DESC;

-- 7. Most borrowed books
SELECT b.title, COUNT(*) AS times_borrowed
FROM loans l
JOIN book_copies bc ON bc.copy_id = l.copy_id
JOIN books b        ON b.book_id = bc.book_id
GROUP BY b.book_id, b.title
ORDER BY times_borrowed DESC
LIMIT 10;

-- 8. Users with unpaid fines
SELECT u.full_name, SUM(f.amount) AS total_due
FROM fines f
JOIN loans l ON l.loan_id = f.loan_id
JOIN users u ON u.user_id = l.user_id
WHERE f.paid = FALSE
GROUP BY u.user_id, u.full_name;

-- 9. Pay a fine
UPDATE fines SET paid = TRUE WHERE fine_id = 1;

-- 10. Copies never issued / inventory status summary
SELECT status, COUNT(*) AS copies FROM book_copies GROUP BY status;
