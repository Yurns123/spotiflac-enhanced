package gobackend

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"sync"
	"time"
)

// StreamState represents the current state of a streaming download
type StreamState int

const (
	StreamStateInitializing StreamState = iota
	StreamStateBuffering
	StreamStateStreamable
	StreamStateDownloading
	StreamStateCompleted
	StreamStateFailed
	StreamStateCancelled
)

func (s StreamState) String() string {
	switch s {
	case StreamStateInitializing:
		return "initializing"
	case StreamStateBuffering:
		return "buffering"
	case StreamStateStreamable:
		return "streamable"
	case StreamStateDownloading:
		return "downloading"
	case StreamStateCompleted:
		return "completed"
	case StreamStateFailed:
		return "failed"
	case StreamStateCancelled:
		return "cancelled"
	default:
		return "unknown"
	}
}

// StreamDownload manages a progressive streaming download
type StreamDownload struct {
	mu             sync.RWMutex
	ID             string
	URL            string
	OutputPath     string
	State          StreamState
	TotalBytes     int64
	ReceivedBytes  int64
	StreamableAt   int64
	Error          string
	startTime      time.Time
	cancel         context.CancelFunc
	headerComplete bool
	file           *os.File
}

// Global streaming manager
var (
	activeStreams   = make(map[string]*StreamDownload)
	activeStreamsMu sync.RWMutex
)

// StartStreamDownload initiates a progressive streaming download.
// It downloads the FLAC header + enough initial data to make the file playable,
// then continues downloading the rest. The file is written directly to disk
// and can be played while being downloaded.
func StartStreamDownload(id, urlStr, outputPath string, streamableThreshold int64) (*StreamDownload, error) {
	activeStreamsMu.Lock()
	if existing, ok := activeStreams[id]; ok {
		activeStreamsMu.Unlock()
		return existing, fmt.Errorf("stream %s already exists in state %s", id, existing.State)
	}

	ctx, cancel := context.WithCancel(context.Background())
	sd := &StreamDownload{
		ID:           id,
		URL:          urlStr,
		OutputPath:   outputPath,
		State:        StreamStateInitializing,
		StreamableAt: streamableThreshold,
		startTime:    time.Now(),
		cancel:       cancel,
	}
	activeStreams[id] = sd
	activeStreamsMu.Unlock()

	if streamableThreshold <= 0 {
		sd.StreamableAt = 512 * 1024 // 512KB default threshold
	}

	go sd.run(ctx)
	return sd, nil
}

func (sd *StreamDownload) run(ctx context.Context) {
	var err error
	sd.file, err = os.Create(sd.OutputPath)
	if err != nil {
		sd.setState(StreamStateFailed, fmt.Sprintf("create file: %v", err))
		return
	}

	client := GetDownloadClient()
	req, err := http.NewRequestWithContext(ctx, "GET", sd.URL, nil)
	if err != nil {
		sd.setState(StreamStateFailed, fmt.Sprintf("request: %v", err))
		return
	}
	req.Header.Set("User-Agent", userAgentForURL(req.URL))

	resp, err := client.Do(req)
	if err != nil {
		sd.setState(StreamStateFailed, fmt.Sprintf("request: %v", err))
		return
	}

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		resp.Body.Close()
		sd.setState(StreamStateFailed, fmt.Sprintf("HTTP %d", resp.StatusCode))
		return
	}

	contentLength := resp.ContentLength
	if contentLength > 0 {
		sd.mu.Lock()
		sd.TotalBytes = contentLength
		sd.mu.Unlock()
	}

	sd.setState(StreamStateBuffering, "")

	buf := make([]byte, 64*1024)
	var written int64

	for {
		select {
		case <-ctx.Done():
			sd.setState(StreamStateCancelled, "cancelled")
			resp.Body.Close()
			return
		default:
		}

		nr, er := resp.Body.Read(buf)
		if nr > 0 {
			nw, ew := sd.file.Write(buf[0:nr])
			if ew != nil {
				resp.Body.Close()
				sd.setState(StreamStateFailed, fmt.Sprintf("write: %v", ew))
				return
			}
			written += int64(nw)

			sd.mu.Lock()
			sd.ReceivedBytes = written
			sd.mu.Unlock()

			// Transition to streamable when enough data is available
			if !sd.headerComplete && written >= sd.StreamableAt {
				sd.mu.Lock()
				sd.headerComplete = true
				sd.mu.Unlock()
				sd.setState(StreamStateStreamable, "")
			}

			// Progress reporting via ItemProgressWriter-like mechanism
			if itemID := sd.ID; itemID != "" && contentLength > 0 {
				SetItemBytesReceived(itemID, written)
				if contentLength > 0 {
					SetItemProgress(itemID, float64(written)/float64(contentLength), written, contentLength)
				}
			}
		}
		if er != nil {
			if er == io.EOF {
				sd.setState(StreamStateCompleted, "")
			} else {
				sd.setState(StreamStateFailed, fmt.Sprintf("read: %v", er))
			}
			resp.Body.Close()
			return
		}
	}
}

func (sd *StreamDownload) setState(state StreamState, errMsg string) {
	sd.mu.Lock()
	sd.State = state
	if errMsg != "" {
		sd.Error = errMsg
	}
	sd.mu.Unlock()
	GoLog("[Stream:%s] State -> %s (bytes=%d/%d, error=%s)\n",
		sd.ID, state, sd.ReceivedBytes, sd.TotalBytes, errMsg)
}

// CancelStream cancels an active streaming download
func CancelStream(id string) {
	activeStreamsMu.RLock()
	sd, ok := activeStreams[id]
	activeStreamsMu.RUnlock()
	if ok {
		sd.cancel()
	}
}

// GetStreamState returns the current state of a stream
func GetStreamState(id string) map[string]interface{} {
	activeStreamsMu.RLock()
	sd, ok := activeStreams[id]
	activeStreamsMu.RUnlock()
	if !ok {
		return map[string]interface{}{
			"state": "not_found",
		}
	}
	sd.mu.RLock()
	defer sd.mu.RUnlock()
	return map[string]interface{}{
		"id":             sd.ID,
		"state":          sd.State.String(),
		"output_path":    sd.OutputPath,
		"total_bytes":    sd.TotalBytes,
		"received_bytes": sd.ReceivedBytes,
		"streamable_at":  sd.StreamableAt,
		"error":          sd.Error,
		"elapsed_ms":     time.Since(sd.startTime).Milliseconds(),
	}
}

// IsStreamable checks if a stream has enough data for playback
func IsStreamable(id string) bool {
	activeStreamsMu.RLock()
	sd, ok := activeStreams[id]
	activeStreamsMu.RUnlock()
	if !ok {
		return false
	}
	sd.mu.RLock()
	defer sd.mu.RUnlock()
	return sd.State >= StreamStateStreamable && sd.State <= StreamStateCompleted
}

// IsStreamComplete checks if a stream download has finished
func IsStreamComplete(id string) bool {
	activeStreamsMu.RLock()
	sd, ok := activeStreams[id]
	activeStreamsMu.RUnlock()
	if !ok {
		return false
	}
	sd.mu.RLock()
	defer sd.mu.RUnlock()
	return sd.State == StreamStateCompleted
}

// CleanupStream removes a completed/failed stream from memory
func CleanupStream(id string) {
	activeStreamsMu.Lock()
	sd, ok := activeStreams[id]
	if ok {
		if sd.file != nil {
			sd.file.Close()
		}
		delete(activeStreams, id)
	}
	activeStreamsMu.Unlock()
}
