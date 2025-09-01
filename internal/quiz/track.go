package quiz

import (
	"errors"
	"fmt"
	"guess-the-song-discord/internal/deezer"
	"log"
	"math/rand"
	"time"
)

type LastfmTrack struct {
	LastfmUrl string
	Name      string
	Artist    string
	User      string
}

// ResolvedTrack LastfmTrack once it has been resolved using the Deezer API
type ResolvedTrack struct {
	Lastfm        LastfmTrack
	DeezerPreview string
	DeezerUrl     string
	GuessElements []*GuessElement
}

// GuessElement Used to track what can be guessed and what has been guessed
// so far
type GuessElement struct {
	Value   string
	Type    string
	Points  int
	Guessed bool
}

// chooseTrack Chooses a track until one with a matching Deezer preview is found
func (q *Quiz) chooseTrack() error {
	q.mutex.Lock()
	q.currentTrack = nil

	source := rand.NewSource(time.Now().UnixNano())
	r := rand.New(source)

	for q.currentTrack == nil && len(q.remaining) > 0 {
		choicePosition := r.Intn(len(q.remaining))
		choice := q.remaining[choicePosition]
		track := q.tracks[choice]

		q.remaining = append(q.remaining[:choicePosition], q.remaining[choicePosition+1:]...)

		deezerResponse, err := deezer.Search(track.Name, track.Artist)
		if err != nil && err.Error() == "no match" {
			log.Printf("No match for %s - %s\n", track.Name, track.Artist)
			continue
		} else if err != nil {
			q.mutex.Unlock()
			return fmt.Errorf("error choosing track: %w", err)
		}

		q.currentTrack = &ResolvedTrack{
			Lastfm:        track,
			DeezerPreview: deezerResponse.Preview,
			DeezerUrl:     deezerResponse.Link,
			GuessElements: []*GuessElement{
				{
					Value:   track.Name,
					Type:    "Name",
					Points:  2,
					Guessed: false,
				},
				{
					Value:   track.Artist,
					Type:    "Artist",
					Points:  2,
					Guessed: false,
				},
			},
		}
	}

	if q.currentTrack == nil {
		q.mutex.Unlock()
		return errors.New("no remaining tracks found")
	}

	q.mutex.Unlock()
	return nil
}
