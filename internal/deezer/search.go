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

func Search(trackName string, artist string) (*Track, error) {
	const (
		baseUrl = "https://api.deezer.com/search/track"
		limit   = 1
	)

	// Fuzzier search returns better results
	//searchParams := fmt.Sprintf(`track:"%s" artist:"%s"`, trackName, artist)
	searchParams := fmt.Sprintf("%s %s", trackName, artist)

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
