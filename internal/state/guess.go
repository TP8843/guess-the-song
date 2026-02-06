package state

import "guess-the-song-discord/internal/state/tracks"

func (q *Quiz) ProcessGuess(textChannel, user, guess string) []*tracks.GuessElement {
	return q.round.ProcessGuess(textChannel, user, guess)
}
