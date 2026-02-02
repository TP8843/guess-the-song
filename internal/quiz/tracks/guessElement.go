package tracks

import (
	"regexp"
	"strings"
	"unicode"

	"golang.org/x/text/runes"
	"golang.org/x/text/transform"
	"golang.org/x/text/unicode/norm"
)

// GuessElement Used to track what can be guessed and what has been guessed
// so far
type GuessElement struct {
	value      string
	normalised string
	category   string
	points     int
	guessed    bool
}

// Precompiled regexes for normalisation
var (
	reParens = regexp.MustCompile("\\(.*\\)")
	reSquare = regexp.MustCompile("\\[.*]")
	reDash   = regexp.MustCompile("-.*")
	reFeat   = regexp.MustCompile("feat.*")
	repl     = strings.NewReplacer("and", "&", ".", "", "-", "")
)

func NewGuessElement(value, category string, points int) *GuessElement {
	return &GuessElement{
		value:      value,
		normalised: normaliseString(value),
		category:   category,
		points:     points,
		guessed:    false,
	}
}

func (gE *GuessElement) CheckGuess(text string) bool {
	// Only allow a guess once
	if !gE.guessed && strings.Contains(normaliseString(text), gE.normalised) {
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

func normaliseString(text string) string {
	text = strings.ToLower(text)

	text = reParens.ReplaceAllString(text, "")
	text = reSquare.ReplaceAllString(text, "")
	text = reDash.ReplaceAllString(text, "")
	text = reFeat.ReplaceAllString(text, "")
	text = repl.Replace(text)

	text = strings.TrimSpace(text)
	text = strings.TrimPrefix(text, "the ")

	t := transform.Chain(norm.NFD, runes.Remove(runes.In(unicode.Mn)), norm.NFC)
	text, _, _ = transform.String(t, text)

	return text
}
