package state

import "guess-the-song-discord/internal/state/tracks"

func (q *Quiz) ProcessGuess(textChannel, user, guess string) []*tracks.GuessElement {
	if q.round == nil {
		return make([]*tracks.GuessElement, 0)
	}

	return q.round.ProcessGuess(textChannel, user, guess)
}
