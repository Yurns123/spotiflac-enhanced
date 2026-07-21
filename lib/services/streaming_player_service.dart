import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/utils/logger.dart';

final _log = AppLogger('StreamingPlayer');

enum StreamingSourceMode { lossy, lossless, hybrid }

class StreamingTrack {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String? artUri;
  final String downloadUrl;
  final String localPath;
  final String? streamUrl;
  final StreamingSourceMode mode;

  const StreamingTrack({
    required this.id,
    required this.title,
    required this.artist,
    this.album = '',
    this.artUri,
    required this.downloadUrl,
    required this.localPath,
    this.streamUrl,
    this.mode = StreamingSourceMode.hybrid,
  });
}

enum StreamPlayerState { idle, buffering, playingLossy, playingLossless, paused, completed, error }

class StreamingPlayerState {
  final StreamPlayerState playerState;
  final String? currentTrackId;
  final double lossyProgress;
  final double flacProgress;
  final bool flacReady;
  final String? error;

  const StreamingPlayerState({
    this.playerState = StreamPlayerState.idle,
    this.currentTrackId,
    this.lossyProgress = 0,
    this.flacProgress = 0,
    this.flacReady = false,
    this.error,
  });

  StreamingPlayerState copyWith({
    StreamPlayerState? playerState,
    String? currentTrackId,
    double? lossyProgress,
    double? flacProgress,
    bool? flacReady,
    String? error,
  }) {
    return StreamingPlayerState(
      playerState: playerState ?? this.playerState,
      currentTrackId: currentTrackId ?? this.currentTrackId,
      lossyProgress: lossyProgress ?? this.lossyProgress,
      flacProgress: flacProgress ?? this.flacProgress,
      flacReady: flacReady ?? this.flacReady,
      error: error,
    );
  }
}

class StreamingAudioPlayer {
  final AudioPlayer _lossyPlayer = AudioPlayer(playerId: 'streaming-lossy');
  final AudioPlayer _flacPlayer = AudioPlayer(playerId: 'streaming-flac');
  StreamingTrack? _currentTrack;
  Timer? _flacPollTimer;
  Timer? _positionPollTimer;

  final StreamController<StreamingPlayerState> _stateController =
      StreamController<StreamingPlayerState>.broadcast();
  Stream<StreamingPlayerState> get stateStream => _stateController.stream;

  StreamingPlayerState _state = const StreamingPlayerState();
  StreamingPlayerState get currentState => _state;

  StreamingAudioPlayer() {
    _init();
  }

  void _init() {
    _lossyPlayer.setReleaseMode(ReleaseMode.stop);
    _flacPlayer.setReleaseMode(ReleaseMode.stop);

    _lossyPlayer.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.completed && _state.flacReady) {
        _switchToFlac();
      }
    });

    _flacPlayer.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.playing) {
        _emitState(StreamPlayerState.playingLossless);
      } else if (state == PlayerState.completed) {
        _emitState(StreamPlayerState.completed);
      }
    });
  }

  Future<void> play(StreamingTrack track) async {
    await stop();

    _currentTrack = track;
    _emitState(StreamPlayerState.buffering, currentTrackId: track.id);

    switch (track.mode) {
      case StreamingSourceMode.lossy:
        await _playLossyOnly(track);
      case StreamingSourceMode.lossless:
        await _playLosslessOnly(track);
      case StreamingSourceMode.hybrid:
        await _playHybrid(track);
    }
  }

  Future<void> _playLossyOnly(StreamingTrack track) async {
    final streamUrl = track.streamUrl ?? track.downloadUrl;
    try {
      await _lossyPlayer.play(UrlSource(streamUrl));
      _emitState(StreamPlayerState.playingLossy);
    } catch (e) {
      _log.e('Lossy playback failed: $e');
      _emitState(StreamPlayerState.error, error: e.toString());
    }
  }

  Future<void> _playLosslessOnly(StreamingTrack track) async {
    final file = File(track.localPath);
    if (await file.exists()) {
      try {
        await _flacPlayer.play(DeviceFileSource(track.localPath));
        _emitState(StreamPlayerState.playingLossless);
      } catch (e) {
        _log.e('FLAC playback failed: $e');
        _emitState(StreamPlayerState.error, error: e.toString());
      }
      return;
    }

    _emitState(StreamPlayerState.buffering);
    _startFlacDownload(track);
    _startFlacPolling(track);
  }

  Future<void> _playHybrid(StreamingTrack track) async {
    if (track.streamUrl != null && track.streamUrl!.isNotEmpty) {
      try {
        await _lossyPlayer.play(UrlSource(track.streamUrl!));
        _emitState(StreamPlayerState.playingLossy);
      } catch (e) {
        _log.w('Lossy stream failed, falling back to download: $e');
      }
    }

    _startFlacDownload(track);
    _startFlacPolling(track);
  }

  void _startFlacDownload(StreamingTrack track) {
    final file = File(track.localPath);
    if (file.existsSync()) {
      _state = _state.copyWith(flacReady: true);
      _emitState(_state.playerState, flacReady: true);
      if (_state.playerState == StreamPlayerState.playingLossy) {
        _switchToFlac();
      }
      return;
    }

    // Use the existing download mechanism via PlatformBridge
    PlatformBridge.startDownload(
      DownloadRequestPayload(
        trackName: track.title,
        artistName: track.artist,
        albumName: track.album,
        outputPath: track.localPath,
        spotifyID: track.id,
        quality: 'lossless',
        itemID: 'stream_${track.id}',
      ),
      onProgress: (progress, speedMBps, bytesReceived) {
        _state = _state.copyWith(flacProgress: progress);
        _flacPlayerStateNotify(progress);
      },
    ).then((result) {
      if (result['success'] == true) {
        _state = _state.copyWith(flacReady: true);
        _flacPlayerStateNotify(1.0);
      }
    }).catchError((e) {
      _log.e('FLAC download failed: $e');
    });
  }

  void _startFlacPolling(StreamingTrack track) {
    _flacPollTimer?.cancel();
    _flacPollTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      final file = File(track.localPath);
      if (file.existsSync()) {
        final size = file.lengthSync();
        if (size > 256 * 1024) {
          _state = _state.copyWith(flacReady: true);
          _flacPlayerStateNotify(1.0);
          timer.cancel();
          _flacPollTimer = null;

          if (_state.playerState == StreamPlayerState.playingLossy) {
            _switchToFlac();
          }
        }
      }
    });
  }

  void _flacPlayerStateNotify(double progress) {
    // Called from download callback or poller; update state
  }

  Future<void> _switchToFlac() async {
    if (_currentTrack == null || !_state.flacReady) return;

    _log.i('Switching from lossy to FLAC');
    final position = (await _lossyPlayer.getCurrentPosition()) ?? Duration.zero;

    await _lossyPlayer.stop();
    try {
      await _flacPlayer.play(DeviceFileSource(_currentTrack!.localPath));
      await _flacPlayer.seek(position);
      _emitState(StreamPlayerState.playingLossless, flacReady: true);
    } catch (e) {
      _log.e('FLAC switch failed: $e');
      _emitState(StreamPlayerState.error, error: e.toString());
    }
  }

  Future<void> pause() async {
    if (_state.playerState == StreamPlayerState.playingLossy) {
      await _lossyPlayer.pause();
    } else if (_state.playerState == StreamPlayerState.playingLossless) {
      await _flacPlayer.pause();
    }
    _emitState(StreamPlayerState.paused);
  }

  Future<void> resume() async {
    if (_state.playerState == StreamPlayerState.paused) {
      if (_state.flacReady) {
        await _flacPlayer.resume();
        _emitState(StreamPlayerState.playingLossless);
      } else {
        await _lossyPlayer.resume();
        _emitState(StreamPlayerState.playingLossy);
      }
    }
  }

  Future<void> seek(Duration position) async {
    if (_state.flacReady) {
      await _flacPlayer.seek(position);
    } else {
      await _lossyPlayer.seek(position);
    }
  }

  Stream<Duration> get onPositionChanged {
    // Return position from the currently active player
    if (_state.flacReady) {
      return _flacPlayer.onPositionChanged;
    }
    return _lossyPlayer.onPositionChanged;
  }

  Stream<Duration> get onDurationChanged {
    if (_state.flacReady) {
      return _flacPlayer.onDurationChanged;
    }
    return _lossyPlayer.onDurationChanged;
  }

  Future<void> stop() async {
    _flacPollTimer?.cancel();
    _flacPollTimer = null;
    _positionPollTimer?.cancel();
    _positionPollTimer = null;

    await _lossyPlayer.stop();
    await _flacPlayer.stop();
    _currentTrack = null;
    _emitState(StreamPlayerState.idle);
  }

  void _emitState(StreamPlayerState state, {
    String? currentTrackId,
    bool? flacReady,
    String? error,
  }) {
    _state = _state.copyWith(
      playerState: state,
      currentTrackId: currentTrackId ?? _state.currentTrackId,
      flacReady: flacReady ?? _state.flacReady,
      error: error,
    );
    _stateController.add(_state);
  }

  Future<void> dispose() async {
    _flacPollTimer?.cancel();
    _positionPollTimer?.cancel();
    await _lossyPlayer.dispose();
    await _flacPlayer.dispose();
    await _stateController.close();
  }
}
