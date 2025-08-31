package quiz

import (
	"errors"
	"fmt"
	"guess-the-song-discord/internal/voice"
	"log"
	"sync"

	"github.com/bwmarrin/discordgo"
)

// Quiz Handles current state for a quiz in the server
type Quiz struct {
	tracks       []LastfmTrack
	currentTrack *ResolvedTrack
	points       map[string]int // points map of discord user ids to
	roundPoints  map[string]int
	roundActive  bool  // roundActive whether a guessing is currently running for the game
	round        int   // round current round of quiz
	remaining    []int // remaining all the remaining tracks that have not been used
	Guild        string
	TextChannel  string
	VoiceChannel string
	session      *voice.Session
	mutex        sync.Mutex
}

const (
	Rounds int = 3
)

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
		roundPoints:  nil,
		roundActive:  false,
		remaining:    remaining,
		TextChannel:  textChannel,
		VoiceChannel: voiceChannel,
		session:      nil,
		mutex:        sync.Mutex{},
	}

	if s.quizzes == nil {
		return errors.New("no quizzes data structure")
	}

	if s.quizzes[guild] != nil {
		return errors.New("quiz already exists for this guild")
	}

	// Lock before adding quiz to the main store
	quiz.mutex.Lock()
	s.quizzes[guild] = quiz
	quiz.mutex.Unlock()

	var err error
	quiz.session, err = voice.JoinVoiceSession(s.Session, guild, voiceChannel)
	if err != nil {
		return fmt.Errorf("could not join vc: %v", err)
	}
	defer func() {
		err = s.EndQuiz(guild)
		if err != nil {
			log.Println(fmt.Errorf("could not end quiz: %w", err))
		}
	}()

	for quiz.round <= Rounds {
		err = quiz.chooseTrack()
		if err != nil {
			log.Println(fmt.Errorf("could not choose track: %w", err))
			break
		}

		err := quiz.RunRound()
		if err != nil {
			log.Println(fmt.Errorf("could not run round %d: %w", quiz.round, err))
			break
		}

		_, err = s.Session.ChannelMessageSendEmbed(quiz.TextChannel, &discordgo.MessageEmbed{
			Title: fmt.Sprintf("Round %d End", quiz.round),
			Fields: []*discordgo.MessageEmbedField{
				{
					Name:  "Track",
					Value: fmt.Sprintf("%s - %s (from [%s](https://last.fm/user/%s))", quiz.currentTrack.Lastfm.Name, quiz.currentTrack.Lastfm.Artist, quiz.currentTrack.Lastfm.User, quiz.currentTrack.Lastfm.User),
				},
				{
					Name:  "Links",
					Value: fmt.Sprintf("- Lastfm - %s\n- Deezer - %s", quiz.currentTrack.Lastfm.LastfmUrl, quiz.currentTrack.DeezerUrl),
				},
				{
					Name:  "Points",
					Value: "No-one (it doesn't work yet)",
				},
			},
		})
		if err != nil {
			log.Println(fmt.Errorf("could not send end of round message: %w", err))
		}

		quiz.round += 1
	}

	_, err = s.Session.ChannelMessageSendEmbed(quiz.TextChannel, &discordgo.MessageEmbed{
		Title: "Game End",
		Fields: []*discordgo.MessageEmbedField{
			{
				Name:  "Points",
				Value: "No-one (it doesn't work yet)",
			},
		},
	})
	if err != nil {
		log.Println(fmt.Errorf("could not send end of game message: %w", err))
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
	quiz.mutex.Lock()

	delete(s.quizzes, guild)

	err := quiz.session.Close()
	if err != nil {
		return fmt.Errorf("ended quiz but could not leave voice: %w", err)
	}

	return nil
}

func (q *Quiz) RunRound() error {
	q.mutex.Lock()

	if q.roundActive == true {
		return errors.New("round already active")
	}
	q.roundActive = true

	if q.currentTrack == nil {
		return errors.New("no current track")
	}

	// Reset points for the round
	q.roundPoints = make(map[string]int)

	q.mutex.Unlock()

	err := q.session.PlayFile(q.currentTrack.DeezerPreview)
	if err != nil {
		return fmt.Errorf("could not play current track: %w", err)
	}

	q.mutex.Lock()
	q.roundActive = false
	q.mutex.Unlock()

	return nil
}
