-- SQLite Initial Migration
-- Users table
CREATE TABLE users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    email TEXT UNIQUE NOT NULL,
    username TEXT UNIQUE NOT NULL,
    display_name TEXT,
    bio TEXT,
    password_hash TEXT NOT NULL,
    avatar_path TEXT,
    created_at DATETIME DEFAULT (datetime('now'))
);
