package quiz

import "guess-the-song-discord/internal/quiz/tracks"

func (q *Quiz) ProcessGuess(textChannel, user, guess string) *tracks.GuessElement {
	q.mutex.Lock()
	var result *tracks.GuessElement

	// Only process guesses if round is currently running and guess in correct channel
	if q.roundActive == false || q.currentTrack == nil || q.session.TextChannel() != textChannel {
		q.mutex.Unlock()
		return nil
	}

	allGuessed := true

	for _, element := range q.currentTrack.GuessElements {
		if element.Guessed == false {
			if element.Value == guess {
				element.Guessed = true
				result = element
				q.roundPoints[user] += element.Points
			} else {
				allGuessed = false
			}
		}
	}
	q.mutex.Unlock()

	// Stop the round if all guesses have been made
	if !q.allGuessed && allGuessed {
		q.mutex.Lock()
		q.allGuessed = true
		q.mutex.Unlock()

		q.session.Stop()
	}

	return result
}
