package round

import "guess-the-song-discord/internal/state/tracks"

func (round *Round) ProcessGuess(textChannel, user, guess string) []*tracks.GuessElement {
	round.mutex.Lock()
	defer round.mutex.Unlock()

	// Only process guesses if round is currently running and guess in correct channel
	if round.state != Running || round.session.TextChannel() != textChannel {
		return nil
	}

	result := make([]*tracks.GuessElement, 0)

	for _, element := range round.currentTrack.GuessElements {
		if element.CheckGuess(guess) {
			round.guessTotal += 1
			result = append(result, element)
			round.roundPoints[user] += element.GetPoints()
		}
	}

	// If all guesses have been made
	if round.guessTotal == len(round.currentTrack.GuessElements) {
		round.state = Complete
		round.session.Stop()
	}

	return result
}
