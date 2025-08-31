package quiz

import "github.com/shkh/lastfm-go/lastfm"

// State Handles current state for a quiz in the server
type State struct {
	tracks []lastfm.UserGetTopTracks
}

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
