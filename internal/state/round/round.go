package round

import (
	"errors"
	"fmt"
	"guess-the-song-discord/internal/state/session"
	"guess-the-song-discord/internal/state/tracks"
	"sync"
)

const (
	Ready = iota
	Running
	Complete
)

type Round struct {
	currentTrack *tracks.ResolvedTrack
	guessTotal   int            // guessTotal total number of correct guesses for round
	roundPoints  map[string]int // roundPoints number of points won by all users in a round

	state byte

	session *session.Session
	mutex   sync.Mutex
}

func NewRound(session *session.Session, currentTrack *tracks.ResolvedTrack) *Round {
	return &Round{
		currentTrack: currentTrack,
		roundPoints:  make(map[string]int),
		mutex:        sync.Mutex{},

		state:      Ready,
		guessTotal: 0,

		session: session,
	}
}

func (round *Round) Run() error {
	round.mutex.Lock()

	if round.currentTrack == nil {
		round.mutex.Unlock()
		return errors.New("round has no current track")
	}

	if round.state != Ready {
		round.mutex.Unlock()
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

	round.mutex.Unlock()
	return nil
}

// Points Gets the points for the round. Only works at the end of the round
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

// GetCurrentTrack Gets the currently playing track for the round
func (round *Round) GetCurrentTrack() *tracks.ResolvedTrack {
	round.mutex.Lock()
	defer round.mutex.Unlock()
	return round.currentTrack
}

func (round *Round) EndGame() {
	round.mutex.Lock()
	defer round.mutex.Unlock()
	round.session.Stop()
}
