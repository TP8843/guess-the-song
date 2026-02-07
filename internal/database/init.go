package database

import (
	"database/sql"
	"fmt"

	_ "github.com/mattn/go-sqlite3"
)

type Connection struct {
	db *sql.DB
}

func NewConnection(path string) (*Connection, error) {
	conn := &Connection{}
	var err error

	conn.db, err = sql.Open("sqlite3", path)
	if err != nil {
		return nil, fmt.Errorf("failed to open database, %w", err)
	}

	err = conn.CreateUserTable()
	if err != nil {
		return nil, fmt.Errorf("failed to create user table, %w", err)
	}

	return conn, nil
}

func (conn *Connection) Close() error {
	err := conn.db.Close()
	if err != nil {
		return fmt.Errorf("failed to close connection, %w", err)
	}

	return nil
}
