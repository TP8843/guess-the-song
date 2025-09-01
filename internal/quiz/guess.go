package quiz

func (q *Quiz) ProcessGuess(user, guess string) *GuessElement {
	q.mutex.Lock()
	var result *GuessElement

	// Only process guesses if round is currently running
	if q.roundActive == false || q.currentTrack == nil {
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
		q.session.Stop <- true

		q.mutex.Lock()
		q.allGuessed = true
		q.mutex.Unlock()
	}

	return result
}
