package tracks

// GuessElement Used to track what can be guessed and what has been guessed
// so far
type GuessElement struct {
	Value   string
	Type    string
	Points  int
	Guessed bool
}

func (gE *GuessElement) CheckGuess(text string) bool {
	// Only allow a guess once
	if gE.Guessed {
		return false
	}

	if text == gE.Value {
		gE.Guessed = true
		return true
	}

	return false
}
