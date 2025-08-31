package voice

import (
	"bufio"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"strconv"

	"github.com/bwmarrin/discordgo"
)

// Inspired from dgvoice

// Technically the below settings can be adjusted however that poses
// a lot of other problems that are not handled well at this time.
// These below values seem to provide the best overall performance
const (
	channels  int     = 2                   // 1 for mono, 2 for stereo
	frameRate int     = 48000               // audio sampling rate
	frameSize int     = 960                 // uint16 size of each audio frame
	maxBytes  int     = (frameSize * 2) * 2 // max size of opus data
	volume    float32 = 0.15
)

var (
	// ErrFilePlaying Error if file is already playing in session
	ErrFilePlaying = errors.New("file is playing")

	// ErrFfmpeg Error if ffmpeg command fails
	ErrFfmpeg = errors.New("error running ffmpeg transcode")

	ErrDiscord = errors.New("error communicating with discord")
)

func (s *Session) PlayFile(file string) error {
	// Ensure that no content is currently playing in the session
	s.playingMu.Lock()
	if s.playing {
		s.playingMu.Unlock()
		return ErrFilePlaying
	}
	s.playing = true
	s.playingMu.Unlock()

	defer func() {
		s.playingMu.Lock()
		s.playing = false
		s.playingMu.Unlock()
	}()

	// Transcode file into PCM for piping to discord
	run := exec.Command("ffmpeg", "-i", file, "-af", fmt.Sprintf("volume=%f", volume), "-f", "s16le", "-ar", strconv.Itoa(frameRate), "-ac", strconv.Itoa(channels), "pipe:1")

	ffmpegOut, err := run.StdoutPipe()
	if err != nil {
		return fmt.Errorf("%w: error opening stdout pipe", ErrFfmpeg)
	}
	defer func(ffmpegOut io.ReadCloser) {
		err := ffmpegOut.Close()
		if err != nil {
			log.Println(fmt.Errorf("%w: error closing stdout pipe", ErrFfmpeg))
		}
	}(ffmpegOut)

	ffmpegBuf := bufio.NewReaderSize(ffmpegOut, 16384)

	err = run.Start()
	if err != nil {
		return ErrFfmpeg
	}
	defer func(Process *os.Process) {
		err := Process.Release()
		if err != nil {
			log.Println(fmt.Errorf("%w: error releasing ffmpeg, %v", ErrFfmpeg, err))
		}
	}(run.Process)

	err = s.Vc.Speaking(true)
	if err != nil {
		return fmt.Errorf("%w: error turning off speaking, %v", ErrDiscord, err)
	}
	defer func(vc *discordgo.VoiceConnection) {
		err := vc.Speaking(false)
		if err != nil {
			log.Println(fmt.Errorf("%w: error turning on speaking, %v", ErrDiscord, err))
		}
	}(s.Vc)

	for {
		audioBuffer := make([]int16, frameSize*channels)
		err = binary.Read(ffmpegBuf, binary.LittleEndian, &audioBuffer)
		if errors.Is(err, io.EOF) || errors.Is(err, io.ErrUnexpectedEOF) {
			return nil
		}

		if err != nil {
			return fmt.Errorf("%w: error reading from ffmpeg buffer, %v", ErrFfmpeg, err)
		}

		select {
		case <-s.Stop:
			err := run.Cancel()
			if err != nil && errors.Is(err, os.ErrProcessDone) {
				log.Println(fmt.Errorf("%w: error cancelling ffmpeg process on force close, %v", ErrFfmpeg, err))
			}
			return nil
		case s.pcm <- audioBuffer:
		}
	}
}
