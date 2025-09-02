package tracks

import (
	"errors"
	"fmt"
	"guess-the-song-discord/internal/deezer"
	"log"
	"math/rand"
	"sync"
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

type Tracks struct {
	tracks    []LastfmTrack // tracks all the track to be used in the quiz
	remaining []int         // remaining all the tracks not yet used in the quiz
	mutex     sync.Mutex
}

func NewTracks(tracks []LastfmTrack) *Tracks {
	remaining := make([]int, len(tracks))
	for i := range remaining {
		remaining[i] = i
	}

	return &Tracks{tracks: tracks, remaining: remaining}
}

func (tracks *Tracks) ChooseTrack() (*ResolvedTrack, error) {
	var currentTrack *ResolvedTrack

	source := rand.NewSource(time.Now().UnixNano())
	r := rand.New(source)

	tracks.mutex.Lock()

	for currentTrack == nil && len(tracks.remaining) > 0 {
		choicePosition := r.Intn(len(tracks.remaining))
		choice := tracks.remaining[choicePosition]
		track := tracks.tracks[choice]

		tracks.remaining = append(tracks.remaining[:choicePosition], tracks.remaining[choicePosition+1:]...)

		deezerResponse, err := deezer.Search(track.Name, track.Artist)
		if err != nil && err.Error() == "no match" {
			log.Printf("No match for %s - %s\n", track.Name, track.Artist)
			continue
		} else if err != nil {
			tracks.mutex.Unlock()
			return nil, fmt.Errorf("error choosing track: %w", err)
		}

		currentTrack = &ResolvedTrack{
			Lastfm:        track,
			DeezerPreview: deezerResponse.Preview,
			DeezerUrl:     deezerResponse.Link,
			GuessElements: []*GuessElement{
				{
					value:    track.Name,
					category: "Name",
					points:   2,
					guessed:  false,
				},
				{
					value:    track.Artist,
					category: "Artist",
					points:   2,
					guessed:  false,
				},
			},
		}
	}

	tracks.mutex.Unlock()

	if currentTrack == nil {
		return nil, errors.New("no remaining tracks found")
	}

	return currentTrack, nil
}
