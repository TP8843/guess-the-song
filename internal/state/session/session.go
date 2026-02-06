package session

import (
	"fmt"
	"guess-the-song-discord/internal/voice"

	"github.com/bwmarrin/discordgo"
)

type Session struct {
	guild        string
	textChannel  string
	voiceChannel string
	voiceSession *voice.Session
}

// StartSession creates a new session for the game
func StartSession(s *discordgo.Session, guild string, textChannel, voiceChannel string) (*Session, error) {
	session, err := voice.JoinVoiceSession(s, guild, voiceChannel)
	if err != nil {
		return nil, fmt.Errorf("could not join vc: %v", err)
	}

	return &Session{
		guild:        guild,
		textChannel:  textChannel,
		voiceChannel: voiceChannel,
		voiceSession: session,
	}, nil
}

func (session *Session) Guild() string {
	return session.guild
}

func (session *Session) TextChannel() string {
	return session.textChannel
}

func (session *Session) VoiceChannel() string {
	return session.voiceChannel
}

func (session *Session) Close() error {
	err := session.voiceSession.Close()
	if err != nil {
		return fmt.Errorf("could not close voice session: %w", err)
	}

	return nil
}

func (session *Session) PlayFile(path string) error {
	err := session.voiceSession.PlayFile(path)
	if err != nil {
		return fmt.Errorf("could not play file for session: %w", err)
	}

	return nil
}

// Stop end playing audio for the current round
func (session *Session) Stop() {
	session.voiceSession.Stop <- true
}
