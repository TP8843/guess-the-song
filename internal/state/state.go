package state

import (
	"errors"
	"fmt"

	"github.com/bwmarrin/discordgo"
)

type State struct {
	Session *discordgo.Session
	quizzes map[string]*Quiz
}

func NewState(session *discordgo.Session) *State {
	return &State{
		Session: session,
		quizzes: make(map[string]*Quiz),
	}
}

// HasQuiz returns whether there is a state running in the guild
func (s *State) HasQuiz(guild string) bool {
	if s.quizzes == nil {
		return false
	}

	if s.quizzes[guild] == nil {
		return false
	}

	return true
}

// GetQuiz gets the state for the associated guild
func (s *State) GetQuiz(guild string) (*Quiz, error) {
	if s.quizzes == nil {
		return nil, errors.New("no quizzes database structure")
	}

	if s.quizzes[guild] == nil {
		return nil, fmt.Errorf("no state found with guild id %s", guild)
	}

	return s.quizzes[guild], nil
}
