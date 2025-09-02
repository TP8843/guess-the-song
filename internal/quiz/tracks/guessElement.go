package tracks

// GuessElement Used to track what can be guessed and what has been guessed
// so far
type GuessElement struct {
	value    string
	category string
	points   int
	guessed  bool
}

func (gE *GuessElement) CheckGuess(text string) bool {
	// Only allow a guess once
	if !gE.guessed && text == gE.value {
		gE.guessed = true
		return true
	}

	return false
}

func (gE *GuessElement) GetValue() string {
	return gE.value
}

func (gE *GuessElement) GetCategory() string {
	return gE.category
}

func (gE *GuessElement) GetPoints() int {
	return gE.points
}
