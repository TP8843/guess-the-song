package commands

import (
	"guess-the-song-discord/internal/database"
	"guess-the-song-discord/internal/state"

	"github.com/shkh/lastfm-go/lastfm"
)

type Context struct {
	Lm        *lastfm.Api
	quizState *state.State
	db        *database.Connection
}

func NewContext(s *state.State, lm *lastfm.Api, db *database.Connection) *Context {
	return &Context{
		Lm:        lm,
		quizState: s,
		db:        db,
	}
}
