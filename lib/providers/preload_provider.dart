import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:spotiflac_android/services/streaming_player_service.dart';
import 'package:spotiflac_android/utils/logger.dart';

final _log = AppLogger('PreloadProvider');

class PreloadItem {
  final String trackId;
  final String title;
  final String artist;
  final String downloadUrl;
  final String localPath;
  final int priority;
  PreloadStatus status;

  PreloadItem({
    required this.trackId,
    required this.title,
    required this.artist,
    required this.downloadUrl,
    required this.localPath,
    this.priority = 0,
    this.status = PreloadStatus.queued,
  });
}

enum PreloadStatus { queued, downloading, completed, failed }

class PreloadState {
  final List<PreloadItem> items;
  final String? activeId;

  const PreloadState({this.items = const [], this.activeId});

  PreloadState copyWith({List<PreloadItem>? items, String? activeId}) {
    return PreloadState(items: items ?? this.items, activeId: activeId);
  }
}

class PreloadNotifier extends StateNotifier<PreloadState> {
  static const int _maxConcurrent = 1;
  static const int _maxQueue = 5;

  Timer? _workerTimer;
  bool _workerRunning = false;

  PreloadNotifier() : super(const PreloadState());

  void enqueue({
    required String trackId,
    required String title,
    required String artist,
    required String downloadUrl,
    required String localPath,
    int priority = 0,
  }) {
    // Remove duplicates
    final filtered = state.items.where((i) => i.trackId != trackId).toList();

    // Trim if full
    while (filtered.length >= _maxQueue) {
      filtered.removeAt(0);
    }

    filtered.add(PreloadItem(
      trackId: trackId,
      title: title,
      artist: artist,
      downloadUrl: downloadUrl,
      localPath: localPath,
      priority: priority,
      status: PreloadStatus.queued,
    ));

    state = state.copyWith(items: filtered);
    _ensureWorker();
  }

  void enqueueNext(int currentIndex, List<StreamingTrack> queue, {int count = 2}) {
    for (var i = 1; i <= count; i++) {
      final nextIdx = currentIndex + i;
      if (nextIdx < queue.length) {
        final track = queue[nextIdx];
        final file = File(track.localPath);
        if (!file.existsSync()) {
          enqueue(
            trackId: track.id,
            title: track.title,
            artist: track.artist,
            downloadUrl: track.downloadUrl,
            localPath: track.localPath,
            priority: i,
          );
        }
      }
    }
  }

  void _ensureWorker() {
    if (_workerRunning) return;
    _workerTimer?.cancel();
    _workerTimer = Timer.periodic(const Duration(seconds: 1), (_) => _processQueue());
    _processQueue();
  }

  Future<void> _processQueue() async {
    if (_workerRunning) return;
    _workerRunning = true;

    try {
      final queued = state.items.where((i) => i.status == PreloadStatus.queued).toList();
      if (queued.isEmpty) {
        _workerRunning = false;
        _workerTimer?.cancel();
        return;
      }

      final next = queued.first;
      _updateItemStatus(next.trackId, PreloadStatus.downloading);
      state = state.copyWith(activeId: next.trackId);

      _log.i('Preloading: ${next.artist} - ${next.title}');

      try {
        final dir = Directory(next.localPath).parent;
        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }

        // Download via HTTP
        final client = HttpClient();
        final request = await client.getUrl(Uri.parse(next.downloadUrl));
        final response = await request.close();

        if (response.statusCode == 200) {
          final file = File(next.localPath);
          final sink = file.openWrite();
          await response.pipe(sink);
          await sink.close();

          _updateItemStatus(next.trackId, PreloadStatus.completed);
          _log.i('Preload complete: ${next.artist} - ${next.title}');
        } else {
          _updateItemStatus(next.trackId, PreloadStatus.failed);
        }
      } catch (e) {
        _log.e('Preload failed for ${next.title}: $e');
        _updateItemStatus(next.trackId, PreloadStatus.failed);
      }

      state = state.copyWith(activeId: null);
    } finally {
      _workerRunning = false;
    }
  }

  void _updateItemStatus(String trackId, PreloadStatus status) {
    final items = state.items.map((item) {
      if (item.trackId == trackId) {
        return PreloadItem(
          trackId: item.trackId,
          title: item.title,
          artist: item.artist,
          downloadUrl: item.downloadUrl,
          localPath: item.localPath,
          priority: item.priority,
          status: status,
        );
      }
      return item;
    }).toList();
    state = state.copyWith(items: items);
  }

  bool isReady(String trackId) {
    final item = state.items.where((i) => i.trackId == trackId).firstOrNull;
    if (item != null) return item.status == PreloadStatus.completed;
    return File(getLocalPath(trackId)).existsSync();
  }

  static Future<String> getLocalPath(String trackId) async {
    final temp = await getTemporaryDirectory();
    return '${temp.path}/spotiflac_preload/$trackId.flac';
  }

  void cancelAll() {
    _workerTimer?.cancel();
    _workerTimer = null;
    _workerRunning = false;
    state = const PreloadState();
  }

  @override
  void dispose() {
    _workerTimer?.cancel();
    super.dispose();
  }
}

final preloadProvider = StateNotifierProvider<PreloadNotifier, PreloadState>((ref) {
  return PreloadNotifier();
});
