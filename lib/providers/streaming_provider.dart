import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:spotiflac_android/services/streaming_player_service.dart';

final streamingPlayerProvider = Provider<StreamingAudioPlayer>((ref) {
  final player = StreamingAudioPlayer();
  ref.onDispose(() => player.dispose());
  return player;
});

final streamingStateProvider = StreamProvider<StreamingPlayerState>((ref) {
  final player = ref.watch(streamingPlayerProvider);
  return player.stateStream;
});

class HybridPlayerController {
  final StreamingAudioPlayer _player;
  StreamingTrack? _current;

  HybridPlayerController(this._player);

  Stream<StreamingPlayerState> get stateStream => _player.stateStream;
  StreamingPlayerState get currentState => _player.currentState;

  Future<void> playTrack({
    required String id,
    required String title,
    required String artist,
    String album = '',
    String? artUri,
    required String downloadUrl,
    required String localPath,
    String? streamUrl,
  }) async {
    final track = StreamingTrack(
      id: id,
      title: title,
      artist: artist,
      album: album,
      artUri: artUri,
      downloadUrl: downloadUrl,
      localPath: localPath,
      streamUrl: streamUrl,
      mode: streamUrl != null && streamUrl.isNotEmpty
          ? StreamingSourceMode.hybrid
          : StreamingSourceMode.lossless,
    );
    _current = track;
    await _player.play(track);
  }

  Future<void> playLossyOnly({
    required String url,
    required String id,
    required String title,
    required String artist,
  }) async {
    final track = StreamingTrack(
      id: id,
      title: title,
      artist: artist,
      downloadUrl: url,
      localPath: '',
      streamUrl: url,
      mode: StreamingSourceMode.lossy,
    );
    _current = track;
    await _player.play(track);
  }

  Future<void> togglePlayPause() async {
    final state = _player.currentState;
    if (state.playerState == StreamPlayerState.playingLossy ||
        state.playerState == StreamPlayerState.playingLossless) {
      await _player.pause();
    } else if (state.playerState == StreamPlayerState.paused) {
      await _player.resume();
    }
  }

  Future<void> seek(Duration position) => _player.seek(position);
  Future<void> stop() => _player.stop();

  Stream<Duration> get onPositionChanged => _player.onPositionChanged;
  Stream<Duration> get onDurationChanged => _player.onDurationChanged;
}

final hybridPlayerProvider = Provider<HybridPlayerController>((ref) {
  final player = ref.watch(streamingPlayerProvider);
  return HybridPlayerController(player);
});
