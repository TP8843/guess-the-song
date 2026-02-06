package database

import (
	"fmt"
	"strings"
)

func (conn *Connection) CreateUserTable() error {
	sqlStmt := `
	CREATE TABLE IF NOT EXISTS users (id integer NOT NULL PRIMARY KEY, lastfm text)
	`

	_, err := conn.db.Exec(sqlStmt)
	if err != nil {
		return fmt.Errorf("failed to create users table, %w", err)
	}

	return nil
}

func (conn *Connection) LinkUser(discord int64, lastfm string) error {

	// Check for existing user: if exists, just replace lastfm
	row := conn.db.QueryRow(
		`SELECT 1 FROM TABLE ( users ) WHERE (id = ?) LIMIT 1`,
		discord,
	)
	err := row.Scan()
	// Just update user if user already exists
	if err == nil {
		_, err = conn.db.Exec(
			`UPDATE users SET lastfm = ? WHERE (id = ?)`,
			lastfm,
			discord,
		)
		if err != nil {
			return fmt.Errorf("failed to update user, %w", err)
		}

		return nil
	}

	// If user does not exist, create a new user
	_, err = conn.db.Exec(
		`INSERT INTO users (id, lastfm) VALUES (?, ?)`,
		discord,
		lastfm,
	)
	if err != nil {
		return fmt.Errorf("failed to create user, %w", err)
	}
	return nil
}

func (conn *Connection) UnlinkUser(discord int64) error {
	sqlStmt := `DELETE FROM users WHERE (id = ?)`

	_, err := conn.db.Exec(sqlStmt, discord)
	if err != nil {
		return fmt.Errorf("failed to delete user, %w", err)
	}
	return nil
}

func (conn *Connection) GetUsernames(discord []int64) ([]string, error) {
	if len(discord) == 0 {
		return []string{}, nil
	}

	args := make([]interface{}, len(discord))
	for i, id := range discord {
		args[i] = id
	}

	rows, err := conn.db.Query(
		`SELECT lastfm FROM users WHERE id IN (?`+strings.Repeat(",?", len(discord)-1)+`)`,
		args...,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to get lastfm usernames, %w", err)
	}

	usernames := make([]string, len(discord))
	index := 0

	for rows.Next() {
		err = rows.Scan(&usernames[index])
	}

	return usernames, nil
}
