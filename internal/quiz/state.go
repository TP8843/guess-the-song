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

func (s *State) GetQuiz(textChannel string) (*Quiz, error) {
	if s.quizzes == nil {
		return nil, errors.New("no quizzes data structure")
	}

	if s.quizzes[textChannel] == nil {
		return nil, fmt.Errorf("no quiz found with text channel id %s", textChannel)
	}

	return s.quizzes[textChannel], nil
}
