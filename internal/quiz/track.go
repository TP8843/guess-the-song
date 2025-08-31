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
}

// chooseTrack Chooses a track until one with a matching Deezer preview is found
func (q *Quiz) chooseTrack() error {
	q.currentTrack = nil

	source := rand.NewSource(time.Now().UnixNano())
	r := rand.New(source)

	for q.currentTrack == nil && len(q.remaining) > 0 {
		choice := q.remaining[r.Intn(len(q.remaining))]
		track := q.tracks[choice]

		q.remaining = append(q.remaining[:choice], q.remaining[choice+1:]...)

		deezerResponse, err := deezer.Search(track.Name, track.Artist)
		if err != nil && err.Error() == "no match" {
			log.Printf("No match for %s - %s\n", track.Name, track.Artist)
			continue
		} else if err != nil {
			return fmt.Errorf("error choosing track: %w", err)
		}

		q.currentTrack = &ResolvedTrack{
			Lastfm:        track,
			DeezerPreview: deezerResponse.Preview,
			DeezerUrl:     deezerResponse.Link,
		}
	}

	if len(q.remaining) == 0 {
		return errors.New("no remaining tracks found")
	}

	return nil
}
