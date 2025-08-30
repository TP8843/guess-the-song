package deezer

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
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
	trackNameEncoded := url.QueryEscape(trackName)
	artistEncoded := url.QueryEscape(artist)

	searchParams := fmt.Sprintf("track:\"%s\" artist:\"%s\"", trackNameEncoded, artistEncoded)

	req, err := http.NewRequest("GET", "https://api.deezer.com/search/track", nil)
	if err != nil {
		log.Println(err)
		return nil, errors.New("could not create request for track")
	}

	q := req.URL.Query()
	q.Add("q", searchParams)
	q.Add("limit", "1")

	req.URL.RawQuery = q.Encode()

	client := &http.Client{}

	resp, err := client.Do(req)
	if err != nil {
		log.Println("error getting deezer track, ", err)

		return nil, errors.New("could not get response from deezer")
	}
	defer func(Body io.ReadCloser) {
		err := Body.Close()
		if err != nil {
			log.Println("error closing deezer request body, ", err)
		}
	}(resp.Body)

	if resp.StatusCode != http.StatusOK {
		err = fmt.Errorf("%d status code from deezer", resp.StatusCode)
		log.Println(err)

		data, _ := io.ReadAll(resp.Body)
		fmt.Println(string(data))

		return nil, err
	}

	responseBody := TrackSearchResponse{}
	err = json.NewDecoder(resp.Body).Decode(&responseBody)
	if err != nil {
		log.Println("error decoding deezer response, ", err)
		return nil, errors.New("could not decode deezer response")
	}

	if responseBody.Total == 0 {
		return nil, errors.New("no match")
	}

	return &responseBody.Data[0], nil
}
