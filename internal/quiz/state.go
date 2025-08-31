package quiz

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

// HasQuiz returns whether there is a quiz running in the guild
func (s *State) HasQuiz(guild string) bool {
	if s.quizzes == nil {
		return false
	}

	if s.quizzes[guild] == nil {
		return false
	}

	return true
}

// GetQuiz gets the quiz for the associated guild
func (s *State) GetQuiz(guild string) (*Quiz, error) {
	if s.quizzes == nil {
		return nil, errors.New("no quizzes data structure")
	}

	if s.quizzes[guild] == nil {
		return nil, fmt.Errorf("no quiz found with guild id %s", guild)
	}

	return s.quizzes[guild], nil
}
