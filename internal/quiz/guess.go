package quiz

type GuessResult struct {
	GuessType string
	Corrected string
}

func (q *Quiz) ProcessGuess(user, guess string) *GuessResult {
	q.mutex.Lock()
	var result *GuessResult

	// Only process guesses if round is currently running
	if q.roundActive == false || q.currentTrack == nil {
	} else if q.currentTrack.Lastfm.Name == guess {
		q.roundPoints[user] += 2
		result = &GuessResult{"title", q.currentTrack.Lastfm.Name}
	} else if q.currentTrack.Lastfm.Artist == guess {
		q.roundPoints[user] += 2
		result = &GuessResult{"artist", q.currentTrack.Lastfm.Artist}
	}

	q.mutex.Unlock()
	return result
}
