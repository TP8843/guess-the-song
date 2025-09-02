package round

import (
	"guess-the-song-discord/internal/quiz/tracks"
)

type Round struct {
	currentTrack *tracks.ResolvedTrack
	roundActive  bool           // roundActive whether guessing is currently taking place for a game
	roundPoints  map[string]int // roundPoints number of points won by all users in a round
	round        int            // round current round of the game
	endGame      bool           // endGame whether to end the game at the end of the round
}
