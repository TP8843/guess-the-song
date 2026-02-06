package commands

import (
	"guess-the-song-discord/internal/state"

	"github.com/shkh/lastfm-go/lastfm"
)

type Context struct {
	Lm        *lastfm.Api
	quizState *state.State
}

func NewContext(s *state.State, lm *lastfm.Api) *Context {
	return &Context{
		Lm:        lm,
		quizState: s,
	}
}
