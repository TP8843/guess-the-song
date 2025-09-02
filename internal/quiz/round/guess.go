package round

import "guess-the-song-discord/internal/quiz/tracks"

func (round *Round) ProcessGuess(textChannel, user, guess string) *tracks.GuessElement {
	round.mutex.Lock()
	defer round.mutex.Unlock()

	// Only process guesses if round is currently running and guess in correct channel
	if round.state != Running || round.session.TextChannel() != textChannel {
		return nil
	}

	allGuessed := true
	var result *tracks.GuessElement

	for _, element := range round.currentTrack.GuessElements {
		if element.Guessed == false {
			if element.Value == guess {
				element.Guessed = true
				result = element
				round.roundPoints[user] += element.Points
			} else {
				allGuessed = false
			}
		}
	}

	if !round.allGuessed && allGuessed {
		round.allGuessed = true
		round.state = Complete
		round.session.Stop()
	}

	return result
}
