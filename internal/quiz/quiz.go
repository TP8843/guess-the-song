package quiz

import (
	"errors"
	"fmt"
	"guess-the-song-discord/internal/voice"
	"log"
	"time"
)

// Quiz Handles current state for a quiz in the server
type Quiz struct {
	tracks       []LastfmTrack
	currentTrack *ResolvedTrack
	points       map[string]int // points map of discord user ids to
	round        int            // round current round of quiz
	remaining    []int          // remaining all the remaining tracks that have not been used
	Guild        string
	TextChannel  string
	VoiceChannel string
	session      *voice.Session
}

func (s *State) StartQuiz(guild, textChannel, voiceChannel string, tracks []LastfmTrack) error {
	remaining := make([]int, len(tracks))
	for i := range remaining {
		remaining[i] = i
	}

	quiz := &Quiz{
		Guild:        guild,
		tracks:       tracks,
		currentTrack: nil,
		points:       make(map[string]int),
		round:        1,
		remaining:    remaining,
		TextChannel:  textChannel,
		VoiceChannel: voiceChannel,
		session:      nil,
	}

	if s.quizzes == nil {
		return errors.New("no quizzes data structure")
	}

	if s.quizzes[guild] != nil {
		return errors.New("quiz already exists for this guild")
	}

	s.quizzes[guild] = quiz

	var err error
	quiz.session, err = voice.JoinVoiceSession(s.Session, guild, voiceChannel)
	if err != nil {
		return fmt.Errorf("could not join vc: %v", err)
	}

	err = quiz.chooseTrack()
	if err != nil {
		return fmt.Errorf("could not choose track: %w", err)
	}

	time.Sleep(1 * time.Second)

	err = quiz.session.PlayFile(quiz.currentTrack.DeezerPreview)

	err = s.EndQuiz(guild)
	if err != nil {
		log.Println(fmt.Errorf("could not end quiz: %w", err))
	}

	return nil
}

func (s *State) EndQuiz(guild string) error {
	if s.quizzes == nil {
		return errors.New("no quizzes data structure")
	}

	if s.quizzes[guild] == nil {
		return fmt.Errorf("no quiz found with guild id %s", guild)
	}

	quiz := s.quizzes[guild]

	delete(s.quizzes, guild)

	err := quiz.session.Close()
	if err != nil {
		return fmt.Errorf("ended quiz but could not leave voice: %w", err)
	}

	return nil
}
