package round

import (
	"errors"
	"fmt"
	"guess-the-song-discord/internal/quiz/session"
	"guess-the-song-discord/internal/quiz/tracks"
	"sync"
)

const (
	Ready = iota
	Running
	Complete
)

type Round struct {
	currentTrack *tracks.ResolvedTrack
	allGuessed   bool
	roundPoints  map[string]int // roundPoints number of points won by all users in a round
	endGame      bool           // endGame whether to end the game at the end of the round

	state byte

	session *session.Session
	mutex   sync.Mutex
}

func NewRound(session *session.Session, currentTrack *tracks.ResolvedTrack) *Round {
	return &Round{
		currentTrack: currentTrack,
		allGuessed:   false,
		roundPoints:  make(map[string]int),
		endGame:      false,

		state: Ready,

		session: session,
	}
}

func (round *Round) Run() error {
	round.mutex.Lock()
	defer round.mutex.Unlock()

	if round.currentTrack == nil {
		return errors.New("round has no current track")
	}

	if round.state != Ready {
		return errors.New("round not ready")
	}

	round.state = Running
	round.mutex.Unlock()

	err := round.session.PlayFile(round.currentTrack.DeezerPreview)
	if err != nil {
		return fmt.Errorf("could not play current track: %w", err)
	}

	round.mutex.Lock()
	round.state = Complete
	return nil
}

// Points gets the points for the round. Only works at the end of the round
func (round *Round) Points() (map[string]int, error) {
	round.mutex.Lock()
	defer round.mutex.Unlock()

	// Only return if round finished
	if round.state != Complete {
		return nil, errors.New("round not complete")
	}

	points := round.roundPoints

	return points, nil
}

// EndGameAfterRound when run, game ends after this current round
func (round *Round) EndGameAfterRound() {
	round.mutex.Lock()
	round.endGame = true
	round.mutex.Unlock()
}

func (round *Round) GetEndGame() bool {
	round.mutex.Lock()
	defer round.mutex.Unlock()
	return round.endGame
}

func (round *Round) GetCurrentTrack() *tracks.ResolvedTrack {
	round.mutex.Lock()
	defer round.mutex.Unlock()
	return round.currentTrack
}
