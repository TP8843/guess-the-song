package deezer

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"
)

type TrackSearchResponse struct {
	Data  []Track `json:"data"`
	Total int     `json:"total"`
	Next  string  `json:"next"`
}

type Track struct {
	ID             int64   `json:"id"`
	Title          string  `json:"title"`
	TitleShort     string  `json:"title_short"`
	TitleVersion   string  `json:"title_version"`
	Link           string  `json:"link"`
	Duration       int     `json:"duration"`
	Rank           int     `json:"rank"`
	ExplicitLyrics bool    `json:"explicit_lyrics"`
	Preview        string  `json:"preview"`
	BPM            float64 `json:"bpm"`
	Gain           float64 `json:"gain"`
	Artist         Artist  `json:"artist"`
	Album          Album   `json:"album"`
	Type           string  `json:"type"`
}

type Album struct {
	ID             int64  `json:"id"`
	Title          string `json:"title"`
	Link           string `json:"link"`
	Cover          string `json:"cover"`
	CoverSmall     string `json:"cover_small"`
	CoverMedium    string `json:"cover_medium"`
	CoverBig       string `json:"cover_big"`
	CoverXL        string `json:"cover_xl"`
	GenreID        int    `json:"genre_id"`
	NbTracks       int    `json:"nb_tracks"`
	ReleaseDate    string `json:"release_date"`
	RecordType     string `json:"record_type"`
	Tracklist      string `json:"tracklist"`
	ExplicitLyrics bool   `json:"explicit_lyrics"`
	Artist         Artist `json:"artist"`
	Type           string `json:"type"`
}

type Artist struct {
	ID            int64  `json:"id"`
	Name          string `json:"name"`
	Link          string `json:"link"`
	Picture       string `json:"picture"`
	PictureSmall  string `json:"picture_small"`
	PictureMedium string `json:"picture_medium"`
	PictureBig    string `json:"picture_big"`
	PictureXL     string `json:"picture_xl"`
	NbAlbum       int    `json:"nb_album"`
	NbFan         int    `json:"nb_fan"`
	Radio         bool   `json:"radio"`
	Tracklist     string `json:"tracklist"`
	Type          string `json:"type"`
}

func Search(trackName string, artist string) (*Track, error) {
	const (
		baseUrl = "https://api.deezer.com/search/track"
		limit   = 1
	)

	searchParams := fmt.Sprintf(`track:"%s" artist:"%s"`, trackName, artist)

	req, err := http.NewRequest("GET", baseUrl, nil)
	if err != nil {
		log.Println(err)
		return nil, fmt.Errorf("could not create request for track: %w", err)
	}

	q := req.URL.Query()
	q.Add("q", searchParams)
	q.Add("limit", strconv.Itoa(limit))
	req.URL.RawQuery = q.Encode()

	client := &http.Client{
		Timeout: 10 * time.Second,
	}

	resp, err := client.Do(req)
	if err != nil {
		log.Println("error getting deezer track, ", err)
		return nil, fmt.Errorf("could not get response from deezer: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		err = fmt.Errorf("deezer returned status %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
		log.Println(err)
		return nil, err
	}

	responseBody := TrackSearchResponse{}
	if err = json.NewDecoder(resp.Body).Decode(&responseBody); err != nil {
		log.Println("error decoding deezer response,", err)
		return nil, fmt.Errorf("could not decode deezer response: %w", err)
	}

	if responseBody.Total == 0 || len(responseBody.Data) == 0 {
		return nil, errors.New("no match")
	}

	return &responseBody.Data[0], nil
}
