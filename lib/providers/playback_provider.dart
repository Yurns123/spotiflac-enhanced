import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/providers/music_player_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/services/music_player_service.dart';
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:spotiflac_android/utils/logger.dart';

final _log = AppLogger('PlaybackProvider');

class PlaybackState {
  const PlaybackState();
}

class PlaybackController extends Notifier<PlaybackState> {
  @override
  PlaybackState build() => const PlaybackState();

  Future<bool> _useInternalPlayer() async {
    final mode = ref.read(settingsProvider).playerMode;
    if (mode != 'internal') return false;
    return await ref.read(musicPlayerControllerProvider).ensureInitialized() !=
        null;
  }

  String? _normalizeArtUri(String cover) {
    final value = cover.trim();
    if (value.isEmpty) return null;
    if (value.startsWith('http') ||
        value.startsWith('content://') ||
        value.startsWith('file://')) {
      return value;
    }
    return Uri.file(value).toString();
  }

  Future<void> playLocalPath({
    required String path,
    required String title,
    required String artist,
    String album = '',
    String coverUrl = '',
    Track? track,
  }) async {
    if (isCueVirtualPath(path)) {
      throw Exception(cueVirtualTrackRequiresSplitMessage);
    }

    if (await _useInternalPlayer()) {
      _log.d('Playing "$title" in the internal player: $path');
      await ref
          .read(musicPlayerControllerProvider)
          .playSingle(
            PlayableMedia(
              id: path,
              source: path,
              title: title,
              artist: artist,
              album: album,
              artUri: _normalizeArtUri(coverUrl),
              duration: (track != null && track.duration > 0)
                  ? Duration(seconds: track.duration)
                  : null,
            ),
          );
      return;
    }

    _log.d('Opening external player for "$title" by $artist: $path');
    await openFile(path);
  }

  /// Plays a local-library album/list starting at [startItem], queuing the rest
  /// so playback continues to the next track automatically. Honors player mode.
  Future<void> playLocalLibraryQueue(
    List<LocalLibraryItem> items, {
    required LocalLibraryItem startItem,
  }) async {
    final playable = items
        .where(
          (i) => i.filePath.trim().isNotEmpty && !isCueVirtualPath(i.filePath),
        )
        .toList();
    if (playable.isEmpty) return;
    var startIndex = playable.indexWhere((i) => i.id == startItem.id);
    if (startIndex < 0) startIndex = 0;

    if (await _useInternalPlayer()) {
      await ref
          .read(musicPlayerControllerProvider)
          .playLocal(playable, initialIndex: startIndex);
    } else {
      await openFile(playable[startIndex].filePath);
    }
  }

  /// Plays a downloaded-history album/list starting at [startItem], queuing the
  /// rest. Honors player mode.
  Future<void> playHistoryQueue(
    List<DownloadHistoryItem> items, {
    required DownloadHistoryItem startItem,
  }) async {
    final playable = items
        .where(
          (i) => i.filePath.trim().isNotEmpty && !isCueVirtualPath(i.filePath),
        )
        .toList();
    if (playable.isEmpty) return;
    var startIndex = playable.indexWhere((i) => i.id == startItem.id);
    if (startIndex < 0) startIndex = 0;

    if (await _useInternalPlayer()) {
      await ref
          .read(musicPlayerControllerProvider)
          .playHistory(playable, initialIndex: startIndex);
    } else {
      await openFile(playable[startIndex].filePath);
    }
  }

  /// Plays a prebuilt media queue starting at [startIndex]. Honors player mode
  /// ([externalPath] is opened externally when the built-in player is off).
  Future<void> playMediaQueue(
    Iterable<PlayableMedia> queue, {
    required int startIndex,
    required String externalPath,
  }) async {
    if (await _useInternalPlayer()) {
      final items = queue.toList(growable: false);
      if (items.isEmpty) return;
      final i = startIndex.clamp(0, items.length - 1);
      await ref
          .read(musicPlayerControllerProvider)
          .playAll(items, initialIndex: i);
    } else {
      await openFile(externalPath);
    }
  }

  Future<void> playTrackList(List<Track> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;

    final orderedTracks = _orderedTracksFromStartIndex(tracks, startIndex);

    if (await _useInternalPlayer()) {
      final queue = <PlayableMedia>[];
      var skippedCueVirtualTrack = false;
      final resolvedPaths = await _resolveTrackPaths(orderedTracks);
      for (var index = 0; index < orderedTracks.length; index++) {
        final track = orderedTracks[index];
        final resolvedPath = resolvedPaths[index];
        if (resolvedPath == null) continue;
        if (isCueVirtualPath(resolvedPath)) {
          skippedCueVirtualTrack = true;
          continue;
        }
        queue.add(
          PlayableMedia(
            id: resolvedPath,
            source: resolvedPath,
            title: track.name,
            artist: track.artistName,
            album: track.albumName,
            artUri: _normalizeArtUri(track.coverUrl ?? ''),
            duration: track.duration > 0
                ? Duration(seconds: track.duration)
                : null,
          ),
        );
      }

      if (queue.isNotEmpty) {
        _log.d('Playing ${queue.length} tracks in the internal player');
        await ref.read(musicPlayerControllerProvider).playAll(queue);
        return;
      }
      if (skippedCueVirtualTrack) {
        throw Exception(cueVirtualTrackRequiresSplitMessage);
      }
      throw Exception(
        'No local audio file is available to play. Download the track first.',
      );
    }

    var skippedCueVirtualTrack = false;
    for (final track in orderedTracks) {
      final resolvedPath = await _resolveTrackPath(track);
      if (resolvedPath == null) {
        continue;
      }
      if (isCueVirtualPath(resolvedPath)) {
        skippedCueVirtualTrack = true;
        continue;
      }

      _log.d(
        'Opening first available external track for list playback: '
        '"${track.name}" by ${track.artistName} -> $resolvedPath',
      );
      await openFile(resolvedPath);
      return;
    }

    if (skippedCueVirtualTrack) {
      throw Exception(cueVirtualTrackRequiresSplitMessage);
    }

    throw Exception(
      'No local audio file is available to open. Download the track first.',
    );
  }

  List<Track> _orderedTracksFromStartIndex(List<Track> tracks, int startIndex) {
    final safeStart = startIndex.clamp(0, tracks.length - 1);
    if (safeStart == 0) {
      return List<Track>.from(tracks, growable: false);
    }

    return <Track>[
      ...tracks.sublist(safeStart),
      ...tracks.sublist(0, safeStart),
    ];
  }

  Future<String?> _resolveTrackPath(Track track) async {
    final historyState = ref.read(downloadHistoryProvider);
    final historyNotifier = ref.read(downloadHistoryProvider.notifier);

    final localItem = await _findLocalLibraryItemForTrack(track);
    if (localItem != null && await fileExists(localItem.filePath)) {
      return localItem.filePath;
    }

    final historyItem = await _findDownloadHistoryItemForTrack(
      track,
      historyState,
    );
    if (historyItem != null) {
      if (await fileExists(historyItem.filePath)) {
        return historyItem.filePath;
      }
      historyNotifier.removeFromHistory(historyItem.id);
    }

    return null;
  }

  Future<List<String?>> _resolveTrackPaths(List<Track> tracks) async {
    if (tracks.isEmpty) return const [];
    final results = List<String?>.filled(tracks.length, null);
    var next = 0;
    final workerCount = tracks.length < 4 ? tracks.length : 4;
    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= tracks.length) return;
        results[index] = await _resolveTrackPath(tracks[index]);
      }
    }

    await Future.wait(List.generate(workerCount, (_) => worker()));
    return results;
  }

  Future<LocalLibraryItem?> _findLocalLibraryItemForTrack(Track track) async {
    final isLocalSource = (track.source ?? '').toLowerCase() == 'local';
    if (isLocalSource) {
      final byId = await ref
          .read(localLibraryProvider.notifier)
          .getById(track.id);
      if (byId != null) return byId;
    }

    final isrc = track.isrc?.trim();
    return ref
        .read(localLibraryProvider.notifier)
        .findExistingAsync(
          isrc: isrc,
          trackName: track.name,
          artistName: track.artistName,
        );
  }

  Future<DownloadHistoryItem?> _findDownloadHistoryItemForTrack(
    Track track,
    DownloadHistoryState historyState,
  ) async {
    final historyNotifier = ref.read(downloadHistoryProvider.notifier);
    for (final candidateId in _spotifyIdLookupCandidates(track.id)) {
      final bySpotifyId = historyState.getBySpotifyId(candidateId);
      if (bySpotifyId != null) {
        return bySpotifyId;
      }
      final bySpotifyIdAsync = await historyNotifier.getBySpotifyIdAsync(
        candidateId,
      );
      if (bySpotifyIdAsync != null) {
        return bySpotifyIdAsync;
      }
    }

    final isrc = track.isrc?.trim();
    if (isrc != null && isrc.isNotEmpty) {
      final byIsrc = historyState.getByIsrc(isrc);
      if (byIsrc != null) {
        return byIsrc;
      }
      final byIsrcAsync = await historyNotifier.getByIsrcAsync(isrc);
      if (byIsrcAsync != null) {
        return byIsrcAsync;
      }
    }

    return historyNotifier.findByTrackAndArtistAsync(
      track.name,
      track.artistName,
    );
  }

  List<String> _spotifyIdLookupCandidates(String rawId) {
    final trimmed = rawId.trim();
    if (trimmed.isEmpty) {
      return const [];
    }

    final candidates = <String>{trimmed};
    final lowered = trimmed.toLowerCase();
    if (lowered.startsWith('spotify:track:')) {
      final compact = trimmed.split(':').last.trim();
      if (compact.isNotEmpty) {
        candidates.add(compact);
      }
    } else if (!trimmed.contains(':')) {
      candidates.add('spotify:track:$trimmed');
    }

    final uri = Uri.tryParse(trimmed);
    final segments = uri?.pathSegments ?? const <String>[];
    final trackIndex = segments.indexOf('track');
    if (trackIndex >= 0 && trackIndex + 1 < segments.length) {
      final pathId = segments[trackIndex + 1].trim();
      if (pathId.isNotEmpty) {
        candidates.add(pathId);
        candidates.add('spotify:track:$pathId');
      }
    }

    return candidates.toList(growable: false);
  }
}

final playbackProvider = NotifierProvider<PlaybackController, PlaybackState>(
  PlaybackController.new,
);
