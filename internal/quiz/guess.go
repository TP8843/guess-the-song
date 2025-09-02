package quiz

import "guess-the-song-discord/internal/quiz/tracks"

func (q *Quiz) ProcessGuess(textChannel, user, guess string) *tracks.GuessElement {
	return q.round.ProcessGuess(textChannel, user, guess)
}
