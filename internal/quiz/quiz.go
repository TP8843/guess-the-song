package quiz

import (
	"errors"
	"fmt"
	"guess-the-song-discord/internal/quiz/session"
	"guess-the-song-discord/internal/quiz/tracks"
	"log"
	"sync"

	"github.com/bwmarrin/discordgo"
)

// Quiz Handles current state for a quiz in the server
type Quiz struct {
	currentTrack *tracks.ResolvedTrack
	points       map[string]int // points map of discord user ids to
	roundPoints  map[string]int
	roundActive  bool // roundActive whether a guessing is currently running for the game
	allGuessed   bool // allGuessed whether all correct guesses have been made for a round
	round        int  // round current round of quiz
	endGame      bool // endGame whether to end the game at the end of the current round

	tracks *tracks.Tracks

	session *session.Session

	mutex sync.Mutex
}

const (
	Rounds int = 3
)

func (s *State) StartQuiz(guild, textChannel, voiceChannel string, trackSlice []tracks.LastfmTrack) error {
	quizSession, err := session.StartSession(s.Session, guild, textChannel, voiceChannel)
	if err != nil {
		return fmt.Errorf("error starting quiz session: %w", err)
	}
	defer func(quizSession *session.Session) {
		err := quizSession.Close()
		if err != nil {
			log.Printf("error closing quiz session: %v", err)
		}
	}(quizSession)

	quiz := &Quiz{
		tracks:       tracks.NewTracks(trackSlice),
		currentTrack: nil,
		points:       make(map[string]int),
		round:        1,
		roundPoints:  nil,
		roundActive:  false,
		allGuessed:   false,
		session:      quizSession,
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

	for quiz.round <= Rounds {
		track, err := quiz.tracks.ChooseTrack()
		if err != nil {
			log.Println(fmt.Errorf("could not choose track: %w", err))
			break
		}

		quiz.currentTrack = track

		err = quiz.RunRound()
		if err != nil {
			log.Println(fmt.Errorf("could not run round %d: %w", quiz.round, err))
			break
		}

		for user, points := range quiz.roundPoints {
			quiz.points[user] += points
		}

		_, err = s.Session.ChannelMessageSendEmbed(quiz.session.TextChannel(), &discordgo.MessageEmbed{
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
					Value: quiz.GeneratePointsString(s.Session),
				},
			},
		})
		if err != nil {
			log.Println(fmt.Errorf("could not send end of round message: %w", err))
		}

		quiz.mutex.Lock()
		quiz.round += 1
		end := quiz.endGame
		quiz.mutex.Unlock()

		// If true, end the game at this round
		if end {
			break
		}
	}

	gameEndMessage := discordgo.MessageEmbed{
		Title: "Game End",
		Fields: []*discordgo.MessageEmbedField{
			{
				Name:  "Points",
				Value: quiz.GeneratePointsString(s.Session),
			},
		},
	}

	quiz.mutex.Lock()
	if !quiz.endGame && quiz.round <= Rounds {
		gameEndMessage.Description = "Game ended early due to missing trackSlice on Deezer"
	}
	quiz.mutex.Unlock()

	_, err = s.Session.ChannelMessageSendEmbed(quiz.session.TextChannel(), &gameEndMessage)
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

// RunRound Play a round of the quiz. Plays a track and marks the round as active
func (q *Quiz) RunRound() error {
	q.mutex.Lock()

	if q.roundActive == true {
		return errors.New("round already active")
	}
	q.roundActive = true
	q.allGuessed = false

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

// GeneratePointsString Generate a bullet point list of all players and their current points
func (q *Quiz) GeneratePointsString(s *discordgo.Session) string {
	var pointsString string
	for user, points := range q.points {
		user, err := s.User(user)
		if err != nil {
			log.Println(fmt.Errorf("could not get user: %w", err))
			continue
		}

		pointsString += fmt.Sprintf("- %s - %d points\n", user.DisplayName(), points)
	}

	return pointsString
}
