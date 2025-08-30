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
	volume    float32 = 0.1
)

func (s *Session) PlayFile(file string) {
	// Transcode file into PCM for piping to discord
	run := exec.Command("ffmpeg", "-i", file, "-af", fmt.Sprintf("volume=%f", volume), "-f", "s16le", "-ar", strconv.Itoa(frameRate), "-ac", strconv.Itoa(channels), "pipe:1")

	ffmpegOut, err := run.StdoutPipe()
	if err != nil {
		log.Println(err)
		return
	}
	defer func(ffmpegOut io.ReadCloser) {
		err := ffmpegOut.Close()
		if err != nil {
			log.Println("error closing stdout for ffmpeg,", err)
		}
	}(ffmpegOut)

	run.Stderr = os.Stderr

	ffmpegBuf := bufio.NewReaderSize(ffmpegOut, 16384)

	err = run.Start()
	if err != nil {
		log.Println("error running ffmpeg", err)
	}
	defer func(Process *os.Process) {
		err := Process.Kill()
		if err != nil {
			log.Println("error killing ffmpeg", err)
		}
	}(run.Process)

	err = s.Vc.Speaking(true)
	if err != nil {
		log.Println("error turning on speaking", err)
	}
	defer func(vc *discordgo.VoiceConnection) {
		err := vc.Speaking(false)
		if err != nil {
			log.Println("error turning off speaking", err)
		}
	}(s.Vc)

	for {
		audioBuffer := make([]int16, frameSize*channels)
		err = binary.Read(ffmpegBuf, binary.LittleEndian, &audioBuffer)
		if errors.Is(err, io.EOF) || errors.Is(err, io.ErrUnexpectedEOF) {
			return
		}

		if err != nil {
			log.Println("error reading from ffmpeg", err)
			return
		}

		select {
		case s.pcm <- audioBuffer:
		}
	}
}
