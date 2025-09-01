package quiz

func (q *Quiz) ProcessGuess(user, guess string) *GuessElement {
	q.mutex.Lock()
	var result *GuessElement

	// Only process guesses if round is currently running
	if q.roundActive == false || q.currentTrack == nil {
		q.mutex.Unlock()
		return nil
	}

	for _, element := range q.currentTrack.GuessElements {
		if element.Guessed == false && element.Value == guess {
			element.Guessed = true
			result = element
			q.roundPoints[user] += element.Points
			break
		}
	}

	q.mutex.Unlock()
	return result
}
