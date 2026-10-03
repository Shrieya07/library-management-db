USE library_db;

INSERT INTO users (full_name, email, phone, role) VALUES
 ('Meera Iyer',  'meera@example.com',  '9000000001', 'librarian'),
 ('Arun Kumar',  'arun@example.com',   '9000000002', 'member'),
 ('Priya Nair',  'priya@example.com',  '9000000003', 'member'),
 ('Karthik S',   'karthik@example.com','9000000004', 'member');

INSERT INTO categories (name) VALUES ('Fiction'), ('Science'), ('Technology'), ('History');

INSERT INTO authors (name) VALUES
 ('George Orwell'), ('Carl Sagan'), ('Abraham Silberschatz'), ('Henry F. Korth'), ('S. Sudarshan');

INSERT INTO books (isbn, title, category_id, publisher, published_year) VALUES
 ('9780451524935', '1984', 1, 'Signet Classic', 1950),
 ('9780345539434', 'Cosmos', 2, 'Ballantine', 2013),
 ('9780078022159', 'Database System Concepts', 3, 'McGraw-Hill', 2019);

INSERT INTO book_authors VALUES (1,1),(2,2),(3,3),(3,4),(3,5);

INSERT INTO book_copies (book_id, barcode) VALUES
 (1,'B1-001'),(1,'B1-002'),(2,'B2-001'),(3,'B3-001'),(3,'B3-002');
