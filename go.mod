module guess-the-song-discord

go 1.25

require (
	github.com/bwmarrin/discordgo v0.29.0
	github.com/shkh/lastfm-go v0.0.0-20191215035245-89a801c244e0
)

require golang.org/x/text v0.30.0

require (
	github.com/gorilla/websocket v1.5.3 // indirect
	golang.org/x/crypto v0.43.0 // indirect
	golang.org/x/sys v0.37.0 // indirect
	layeh.com/gopus v0.0.0-20210501142526-1ee02d434e32
)

replace github.com/bwmarrin/discordgo => ./discordgo-patch-rework-vc