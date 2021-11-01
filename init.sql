CREATE TABLE IF NOT EXISTS phonebook.phonebook(
    id INT NOT NULL AUTO_INCREMENT,
    name VARCHAR(100) NOT NULL,
    number VARCHAR(100) NOT NULL,
    PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO phonebook.phonebook (name, number)
    VALUES
        ("Ronaldo", "1234567890"),
        ("Messi", "67854"),
        ("Others", "876543554");