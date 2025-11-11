package deezer

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
	"time"
)

// GetTrack Get a track using a track ID
func GetTrack(track int64) (*Track, error) {
	const (
		baseUrl = "https://api.deezer.com/track/"
	)

	req, err := http.NewRequest("GET", fmt.Sprintf("%s/%d", baseUrl, track), nil)
	if err != nil {
		log.Println(err)
		return nil, fmt.Errorf("could not create request for track: %w", err)
	}

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
		if resp.StatusCode == http.StatusNotFound {
			return nil, errors.New("not found")
		}

		body, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		err = fmt.Errorf("deezer returned status %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
		log.Println(err)
		return nil, err
	}

	responseBody := Track{}
	if err = json.NewDecoder(resp.Body).Decode(&responseBody); err != nil {
		log.Println("error decoding deezer response,", err)
		return nil, fmt.Errorf("could not decode deezer response: %w", err)
	}

	return &responseBody, nil
}
