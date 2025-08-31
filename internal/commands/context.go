package commands

import (
	"guess-the-song-discord/internal/quiz"

	"github.com/shkh/lastfm-go/lastfm"
)

type Context struct {
	Lm        *lastfm.Api
	quizState *quiz.State
}

func NewContext(s *quiz.State, lm *lastfm.Api) *Context {
	return &Context{
		Lm:        lm,
		quizState: s,
	}
}
