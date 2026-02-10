package state

import (
	"errors"
	"fmt"
	"guess-the-song-discord/internal/state/round"
	"guess-the-song-discord/internal/state/session"
	"guess-the-song-discord/internal/state/tracks"
	"log"
	"sync"
	"time"

	"github.com/bwmarrin/discordgo"
)

// Quiz Handles current state for a state in the server
type Quiz struct {
	points map[string]int // points map of discord user ids to

	round       *round.Round
	roundNumber int // roundNumber current round number of state

	endGame chan bool // endGame whether the state should be ended

	tracks *tracks.Tracks

	session *session.Session

	mutex sync.Mutex
}

func (s *State) StartQuiz(guild, textChannel, voiceChannel string, trackSlice []tracks.LastfmTrack, rounds int) error {
	// Sanity checks
	if s.quizzes == nil {
		return errors.New("no quizzes database structure")
	}
	if s.quizzes[guild] != nil {
		return errors.New("state already exists for this guild")
	}

	quizSession, err := session.StartSession(s.Session, guild, textChannel, voiceChannel)
	if err != nil {
		return fmt.Errorf("error starting state session: %w", err)
	}
	defer func(quizSession *session.Session) {
		err := s.endQuiz(guild)
		if err != nil {
			log.Printf("error closing state session: %v", err)
		}
	}(quizSession)

	quiz := &Quiz{
		tracks:      tracks.NewTracks(trackSlice),
		points:      make(map[string]int),
		endGame:     make(chan bool, 1),
		roundNumber: 1,
		session:     quizSession,
		mutex:       sync.Mutex{},
	}

	// Lock before adding state to the main store
	quiz.mutex.Lock()
	s.quizzes[guild] = quiz
	quiz.mutex.Unlock()

	endEarly := false

outer:
	for quiz.roundNumber <= rounds {
		track, err := quiz.tracks.ChooseTrack()
		if err != nil {
			log.Println(fmt.Errorf("could not choose track: %w", err))
			break
		}

		quiz.round = round.NewRound(quiz.session, track)

		select {
		case <-quiz.endGame:
			endEarly = true
			break outer
		case <-time.After(3 * time.Second):
			break
		}

		err = quiz.round.Run()
		if err != nil {
			log.Println(fmt.Errorf("could not run round %d: %w", quiz.roundNumber, err))
			break
		}

		roundPoints, err := quiz.round.Points()
		if err != nil {
			log.Println(fmt.Errorf("could not get points for round %d: %w", quiz.roundNumber, err))
		}
		for user, points := range roundPoints {
			quiz.points[user] += points
		}

		_, err = s.Session.ChannelMessageSendEmbed(quiz.session.TextChannel(), quiz.GenerateRoundEmbed(s.Session))
		if err != nil {
			log.Println(fmt.Errorf("could not send end of round message: %w", err))
		}

		select {
		case <-quiz.endGame:
			endEarly = true
			break outer
		default:
		}

		quiz.roundNumber += 1
	}

	gameEndMessage := discordgo.MessageEmbed{
		Title: "Game End",
		Fields: []*discordgo.MessageEmbedField{
			{
				Name:  "Points",
				Value: quiz.generatePointsString(s.Session),
			},
		},
	}

	quiz.mutex.Lock()
	if !endEarly && quiz.roundNumber <= rounds {
		gameEndMessage.Description = "Game ended early due to missing trackSlice on Deezer"
	}
	quiz.mutex.Unlock()

	_, err = s.Session.ChannelMessageSendEmbed(quiz.session.TextChannel(), &gameEndMessage)
	if err != nil {
		log.Println(fmt.Errorf("could not send end of game message: %w", err))
	}

	return nil
}

func (s *State) endQuiz(guild string) error {
	if s.quizzes == nil {
		return errors.New("no quizzes database structure")
	}

	if s.quizzes[guild] == nil {
		return fmt.Errorf("no state found with guild id %s", guild)
	}

	quiz := s.quizzes[guild]
	quiz.mutex.Lock()

	delete(s.quizzes, guild)

	err := quiz.session.Close()
	if err != nil {
		return fmt.Errorf("ended state but could not leave voice: %w", err)
	}

	return nil
}

// generatePointsString Generate a bullet point list of all players and their current points
func (q *Quiz) generatePointsString(s *discordgo.Session) string {
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

// GenerateRoundEmbed Generate the embed for updated information at end of round
func (q *Quiz) GenerateRoundEmbed(s *discordgo.Session) *discordgo.MessageEmbed {
	track := q.round.GetCurrentTrack()

	return &discordgo.MessageEmbed{
		Title: fmt.Sprintf("Round %d End", q.roundNumber),
		Fields: []*discordgo.MessageEmbedField{
			{
				Name: "Track",
				Value: fmt.Sprintf("%s - %s (from [%s](https://last.fm/user/%s))\n [Last.fm](%s) [Deezer](%s)",
					track.Lastfm.Name,
					track.Lastfm.Artist,
					track.Lastfm.User,
					track.Lastfm.User,
					track.Lastfm.LastfmUrl,
					track.DeezerUrl,
				),
			},
			{
				Name:  "Points",
				Value: q.generatePointsString(s),
			},
		},
	}
}

// EndGame End the current game as soon as possible
func (q *Quiz) EndGame() {
	q.mutex.Lock()
	defer q.mutex.Unlock()
	q.endGame <- true
	if q.round != nil {
		q.round.EndGame()
	}
}
