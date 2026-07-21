package gobackend

import (
	"context"
	"encoding/json"
	"sync"
)

// PreloadItem represents a track queued for background download
type PreloadItem struct {
	ItemID      string `json:"item_id"`
	TrackName   string `json:"track_name"`
	ArtistName  string `json:"artist_name"`
	OutputPath  string `json:"output_path"`
	DownloadURL string `json:"download_url"`
	Priority    int    `json:"priority"`
	Status      string `json:"status"` // queued, downloading, completed, failed
}

// PreloadQueue manages background track preloading
type PreloadQueue struct {
	mu       sync.RWMutex
	items    []*PreloadItem
	maxItems int
	ctx      context.Context
	cancel   context.CancelFunc
	activeID string
}

var (
	preloadQueue     *PreloadQueue
	preloadQueueOnce sync.Once
)

func GetPreloadQueue() *PreloadQueue {
	preloadQueueOnce.Do(func() {
		ctx, cancel := context.WithCancel(context.Background())
		preloadQueue = &PreloadQueue{
			items:    make([]*PreloadItem, 0),
			maxItems: 5,
			ctx:      ctx,
			cancel:   cancel,
		}
		go preloadQueue.worker()
	})
	return preloadQueue
}

func (pq *PreloadQueue) worker() {
	for {
		select {
		case <-pq.ctx.Done():
			return
		default:
		}

		pq.mu.Lock()
		var next *PreloadItem
		for _, item := range pq.items {
			if item.Status == "queued" {
				next = item
				break
			}
		}
		pq.mu.Unlock()

		if next == nil {
			// Sleep and retry
			select {
			case <-pq.ctx.Done():
				return
			default:
			}
			continue
		}

		pq.processItem(next)
	}
}

func (pq *PreloadQueue) processItem(item *PreloadItem) {
	pq.mu.Lock()
	item.Status = "downloading"
	pq.activeID = item.ItemID
	pq.mu.Unlock()

	GoLog("[Preload] Starting download: %s - %s -> %s\n", item.ArtistName, item.TrackName, item.OutputPath)

	// Use the streaming download system for preloading
	sd, err := StartStreamDownload(
		item.ItemID,
		item.DownloadURL,
		item.OutputPath,
		0, // No streamable threshold needed for preload (full download)
	)
	if err != nil {
		GoLog("[Preload] Failed to start stream for %s: %v\n", item.ItemID, err)
		pq.mu.Lock()
		item.Status = "failed"
		pq.activeID = ""
		CleanupStream(item.ItemID)
		pq.mu.Unlock()
		return
	}

	// Wait for completion or context cancellation
	for {
		if IsStreamComplete(item.ItemID) {
			pq.mu.Lock()
			item.Status = "completed"
			pq.activeID = ""
			pq.mu.Unlock()
			GoLog("[Preload] Completed: %s - %s (%d bytes)\n", item.ArtistName, item.TrackName, sd.ReceivedBytes)
			CleanupStream(item.ItemID)
			return
		}

		state := GetStreamState(item.ItemID)
		if s, ok := state["state"].(string); ok && (s == "failed" || s == "cancelled") {
			pq.mu.Lock()
			item.Status = "failed"
			pq.activeID = ""
			pq.mu.Unlock()
			CleanupStream(item.ItemID)
			return
		}

		select {
		case <-pq.ctx.Done():
			CancelStream(item.ItemID)
			pq.mu.Lock()
			item.Status = "cancelled"
			pq.activeID = ""
			pq.mu.Unlock()
			CleanupStream(item.ItemID)
			return
		default:
		}
	}
}

// EnqueuePreload adds a track to the preload queue
func EnqueuePreload(itemID, trackName, artistName, outputPath, downloadURL string, priority int) error {
	pq := GetPreloadQueue()

	pq.mu.Lock()
	defer pq.mu.Unlock()

	// Remove duplicate
	for i, item := range pq.items {
		if item.ItemID == itemID {
			pq.items = append(pq.items[:i], pq.items[i+1:]...)
			break
		}
	}

	// Trim queue if full
	for len(pq.items) >= pq.maxItems {
		pq.items = pq.items[1:]
	}

	item := &PreloadItem{
		ItemID:      itemID,
		TrackName:   trackName,
		ArtistName:  artistName,
		OutputPath:  outputPath,
		DownloadURL: downloadURL,
		Priority:    priority,
		Status:      "queued",
	}

	pq.items = append(pq.items, item)
	GoLog("[Preload] Enqueued: %s - %s (priority=%d, queue=%d)\n", artistName, trackName, priority, len(pq.items))

	return nil
}

// GetPreloadStatus returns the current preload queue status
func GetPreloadStatus() string {
	pq := GetPreloadQueue()
	pq.mu.RLock()
	defer pq.mu.RUnlock()

	items := make([]map[string]interface{}, 0, len(pq.items))
	for _, item := range pq.items {
		items = append(items, map[string]interface{}{
			"item_id":      item.ItemID,
			"track_name":   item.TrackName,
			"artist_name":  item.ArtistName,
			"output_path":  item.OutputPath,
			"priority":     item.Priority,
			"status":       item.Status,
		})
	}

	result := map[string]interface{}{
		"items":      items,
		"queue_size": len(pq.items),
		"active_id":  pq.activeID,
	}

	return toJSON(result)
}

// CancelPreload cancels all pending preloads
func CancelPreload() {
	pq := GetPreloadQueue()
	pq.mu.Lock()

	if pq.activeID != "" {
		CancelStream(pq.activeID)
	}

	for _, item := range pq.items {
		if item.Status == "queued" {
			item.Status = "cancelled"
		}
	}
	pq.items = nil
	pq.activeID = ""
	pq.mu.Unlock()
}

// IsPreloadComplete checks if a specific preload item has finished
func IsPreloadComplete(itemID string) bool {
	pq := GetPreloadQueue()
	pq.mu.RLock()
	defer pq.mu.RUnlock()

	for _, item := range pq.items {
		if item.ItemID == itemID {
			return item.Status == "completed"
		}
	}
	return true // Not in queue = don't wait
}

func toJSON(v interface{}) string {
	b, err := json.Marshal(v)
	if err != nil {
		return "{}"
	}
	return string(b)
}
