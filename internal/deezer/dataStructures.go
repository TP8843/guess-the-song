package deezer

type TrackSearchResponse struct {
	Data  []Track `json:"data"`
	Total int     `json:"total"`
	Next  string  `json:"next"`
}

type Track struct {
	ID             int64    `json:"id"`
	Title          string   `json:"title"`
	TitleShort     string   `json:"title_short"`
	TitleVersion   string   `json:"title_version"`
	Link           string   `json:"link"`
	Duration       int      `json:"duration"`
	Rank           int      `json:"rank"`
	ExplicitLyrics bool     `json:"explicit_lyrics"`
	Preview        string   `json:"preview"`
	BPM            float64  `json:"bpm"`
	Gain           float64  `json:"gain"`
	Contributors   []Artist `json:"contributors"`
	Artist         Artist   `json:"artist"`
	Album          Album    `json:"album"`
	Type           string   `json:"type"`
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
	Role          string `json:"role"`
}
