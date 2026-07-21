import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/providers/music_player_provider.dart';
import 'package:spotiflac_android/services/cover_cache_manager.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/utils/lyrics_parser.dart';
import 'package:spotiflac_android/utils/logger.dart';

final _log = AppLogger('AMNowPlaying');

class AMNowPlayingScreen extends ConsumerStatefulWidget {
  const AMNowPlayingScreen({super.key});

  @override
  ConsumerState<AMNowPlayingScreen> createState() =>
      _AMNowPlayingScreenState();
}

class _AMNowPlayingScreenState extends ConsumerState<AMNowPlayingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  ProviderSubscription<AsyncValue<MediaItem?>>? _mediaItemSub;
  String? _loadedSource;
  Map<String, dynamic>? _metadata;
  ParsedLyrics _lyrics = ParsedLyrics.empty;
  bool _loadingMeta = false;

  late final AnimationController _artScaleController;
  late final AnimationController _controlsFadeController;
  late final Animation<double> _artScaleAnimation;
  late final Animation<double> _controlsFadeAnimation;

  @override
  void initState() {
    super.initState();

    _artScaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _controlsFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _artScaleAnimation = CurvedAnimation(
      parent: _artScaleController,
      curve: Curves.easeOutCubic,
    );
    _controlsFadeAnimation = CurvedAnimation(
      parent: _controlsFadeController,
      curve: Curves.easeOutCubic,
    );

    _artScaleController.forward();
    _controlsFadeController.forward();

    _mediaItemSub = ref.listenManual<AsyncValue<MediaItem?>>(
      currentMediaItemProvider,
      (previous, next) => _loadMetadataForItem(next.value),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadMetadataForItem(ref.read(currentMediaItemProvider).value);
    });
  }

  @override
  void dispose() {
    _mediaItemSub?.close();
    _pageController.dispose();
    _artScaleController.dispose();
    _controlsFadeController.dispose();
    super.dispose();
  }

  void _loadMetadataForItem(MediaItem? item) {
    if (item == null) return;
    final source = item.extras?['source']?.toString() ?? '';
    if (source.isEmpty) return;
    final resolvedSource = item.extras?['resolvedSource']?.toString();
    unawaited(_loadMetadataFor(source, resolvedSource: resolvedSource));
  }

  Future<void> _loadMetadataFor(
    String source, {
    String? resolvedSource,
  }) async {
    if (source == _loadedSource) return;
    _loadedSource = source;
    setState(() {
      _loadingMeta = true;
      _metadata = null;
      _lyrics = ParsedLyrics.empty;
    });
    try {
      String path = (resolvedSource != null && resolvedSource.isNotEmpty)
          ? resolvedSource
          : source;
      if (path == source && source.startsWith('content://')) {
        final temp = await PlatformBridge.copyContentUriToTemp(source);
        if (temp == null || temp.isEmpty) {
          throw Exception('Cannot resolve content URI');
        }
        path = temp;
      }
      final meta = await PlatformBridge.readFileMetadata(path);
      if (!mounted || _loadedSource != source) return;
      setState(() {
        _metadata = meta;
        _lyrics = LyricsParser.parse((meta['lyrics'] ?? '').toString());
        _loadingMeta = false;
      });
    } catch (e) {
      _log.w('Failed to read metadata: $e');
      if (!mounted || _loadedSource != source) return;
      setState(() {
        _metadata = null;
        _lyrics = ParsedLyrics.empty;
        _loadingMeta = false;
      });
    }
  }

  String _fmt(Duration d) {
    final neg = d.isNegative;
    final abs = neg ? -d : d;
    final m = abs.inMinutes;
    final s = abs.inSeconds % 60;
    final prefix = neg ? '-' : '';
    return '$prefix$m:${s.toString().padLeft(2, '0')}';
  }

  String? _qualityLabel() {
    final meta = _metadata;
    if (meta == null) return null;

    final parts = <String>[];
    final format = (meta['format'] ?? meta['audio_codec'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
    if (format.isNotEmpty) parts.add(format);

    final bitDepth = (meta['bit_depth'] as num?)?.toInt() ?? 0;
    if (bitDepth > 0) parts.add('$bitDepth-bit');

    final sampleRate = (meta['sample_rate'] as num?)?.toDouble() ?? 0;
    if (sampleRate > 0) {
      final khz = sampleRate / 1000;
      final khzStr = khz == khz.roundToDouble()
          ? khz.toStringAsFixed(0)
          : khz.toStringAsFixed(1);
      parts.add('$khzStr kHz');
    }

    final bitrate = (meta['bitrate'] as num?)?.toInt() ?? 0;
    if (bitDepth == 0 && bitrate > 0) parts.add('$bitrate kbps');

    if (parts.isEmpty) return null;
    return parts.join('  \u00b7  ');
  }

  String _artUri() {
    return ref.watch(currentMediaItemProvider).value?.artUri?.toString() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final mediaItem = ref.watch(currentMediaItemProvider).value;
    final controller = ref.read(musicPlayerControllerProvider);

    if (mediaItem == null) {
      return Scaffold(
        body: Center(child: Text(context.l10n.nowPlayingNothingPlaying)),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            Theme.of(context).brightness == Brightness.dark
                ? Brightness.light
                : Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onVerticalDragEnd: (details) {
            if (details.primaryVelocity != null &&
                details.primaryVelocity! > 800) {
              _dismiss();
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              _BackgroundBlur(artUri: _artUri()),
              _GradientOverlay(),
              SafeArea(
                child: Column(
                  children: [
                    _TopBar(colorScheme: colorScheme),
                    Expanded(
                      child: PageView(
                        controller: _pageController,
                        children: [
                          _PlayerPage(
                            mediaItem: mediaItem,
                            colorScheme: colorScheme,
                            controller: controller,
                            artScaleAnimation: _artScaleAnimation,
                            controlsFadeAnimation: _controlsFadeAnimation,
                            qualityLabel: _qualityLabel(),
                            fmt: _fmt,
                          ),
                          _LyricsPage(
                            lyrics: _lyrics,
                            loading: _loadingMeta,
                            colorScheme: colorScheme,
                          ),
                        ],
                      ),
                    ),
                    _PageIndicator(
                      controller: _pageController,
                      colorScheme: colorScheme,
                    ),
                    _TimelineSlider(
                      colorScheme: colorScheme,
                      controller: controller,
                      fmt: _fmt,
                    ),
                    _ControlsRow(
                      colorScheme: colorScheme,
                      controller: controller,
                    ),
                    _BottomRow(
                      colorScheme: colorScheme,
                      onLyricsTap: () => _pageController.animateToPage(
                        1,
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _VolumeSlider(colorScheme: colorScheme),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _dismiss() {
    Navigator.of(context, rootNavigator: true).maybePop();
  }
}

class _BackgroundBlur extends StatelessWidget {
  final String artUri;

  const _BackgroundBlur({required this.artUri});

  @override
  Widget build(BuildContext context) {
    final uri = artUri;
    Widget image;
    if (uri.startsWith('http')) {
      image = CachedNetworkImage(
        imageUrl: uri,
        fit: BoxFit.cover,
        cacheManager: CoverCacheManager.instance,
        memCacheWidth: 512,
        memCacheHeight: 512,
        fadeInDuration: Duration.zero,
        placeholder: (_, _) => Container(color: Colors.black),
        errorWidget: (_, _, _) => Container(color: Colors.black),
      );
    } else if (uri.startsWith('file://')) {
      image = Image.file(
        File(Uri.parse(uri).toFilePath()),
        fit: BoxFit.cover,
        cacheWidth: 512,
        cacheHeight: 512,
        errorBuilder: (_, _, _) => Container(color: Colors.black),
      );
    } else {
      image = Container(color: Colors.black);
    }

    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
      child: Transform.scale(
        scale: 1.2,
        child: image,
      ),
    );
  }
}

class _GradientOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.3),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withValues(alpha: 0.6),
          ],
          stops: const [0.0, 0.15, 0.6, 1.0],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final ColorScheme colorScheme;

  const _TopBar({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              Icons.keyboard_arrow_down,
              color: Colors.white,
              size: 32,
            ),
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).maybePop(),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(
              Icons.more_horiz,
              color: Colors.white.withValues(alpha: 0.8),
            ),
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}

class _PageIndicator extends StatelessWidget {
  final PageController controller;
  final ColorScheme colorScheme;

  const _PageIndicator({
    required this.controller,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        double page = 0;
        if (controller.hasClients && controller.position.haveDimensions) {
          page = controller.page ?? 0;
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(2, (i) {
            final isActive = (page - i).abs() < 0.5;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: isActive ? 8 : 5,
              height: isActive ? 8 : 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.4),
              ),
            );
          }),
        );
      },
    );
  }
}

class _PlayerPage extends StatelessWidget {
  final MediaItem mediaItem;
  final ColorScheme colorScheme;
  final MusicPlayerController controller;
  final Animation<double> artScaleAnimation;
  final Animation<double> controlsFadeAnimation;
  final String? qualityLabel;
  final String Function(Duration) fmt;

  const _PlayerPage({
    required this.mediaItem,
    required this.colorScheme,
    required this.controller,
    required this.artScaleAnimation,
    required this.controlsFadeAnimation,
    required this.qualityLabel,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final artSize = (constraints.maxWidth * 0.64).clamp(200.0, 280.0);
        return SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 8),
                ScaleTransition(
                  scale: Tween<double>(begin: 0.85, end: 1.0).animate(
                    artScaleAnimation,
                  ),
                  child: Hero(
                    tag: 'now_playing_art',
                    child: Container(
                      width: artSize,
                      height: artSize,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _Artwork(
                          artUri: mediaItem.artUri?.toString(),
                          cacheWidth: (artSize *
                                  MediaQuery.devicePixelRatioOf(context))
                              .round(),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                FadeTransition(
                  opacity: controlsFadeAnimation,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      children: [
                        Text(
                          mediaItem.title,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            height: 1.2,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          mediaItem.artist ?? '',
                          style: TextStyle(
                            fontSize: 16,
                            color: colorScheme.primary.withValues(alpha: 0.9),
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (mediaItem.album != null &&
                            mediaItem.album!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            mediaItem.album!,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (qualityLabel != null) ...[
                          const SizedBox(height: 10),
                          _QualityPill(
                            label: qualityLabel!,
                            colorScheme: colorScheme,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QualityPill extends StatelessWidget {
  final String label;
  final ColorScheme colorScheme;

  const _QualityPill({required this.label, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.25),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: 0.8),
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _TimelineSlider extends ConsumerWidget {
  final ColorScheme colorScheme;
  final MusicPlayerController controller;
  final String Function(Duration) fmt;

  const _TimelineSlider({
    required this.colorScheme,
    required this.controller,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mediaItem = ref.watch(currentMediaItemProvider).value;
    final playback = ref.watch(playbackStateProvider).value;
    final position = playback?.position ?? Duration.zero;
    final duration = mediaItem?.duration ?? Duration.zero;
    final maxMs = duration.inMilliseconds > 0
        ? duration.inMilliseconds.toDouble()
        : 1.0;
    final posMs = position.inMilliseconds
        .clamp(0, duration.inMilliseconds > 0 ? duration.inMilliseconds : 0)
        .toDouble();
    final remaining = duration > position ? duration - position : Duration.zero;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 0),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 0),
              trackShape: const RectangularSliderTrackShape(),
            ),
            child: Slider(
              value: posMs.clamp(0, maxMs),
              max: maxMs,
              onChanged: duration.inMilliseconds > 0
                  ? (value) => controller.seek(
                        Duration(milliseconds: value.round()),
                      )
                  : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Text(
                  fmt(position),
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: Colors.white.withValues(alpha: 0.7),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const Spacer(),
                Text(
                  '-${fmt(remaining)}',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: Colors.white.withValues(alpha: 0.7),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlsRow extends ConsumerWidget {
  final ColorScheme colorScheme;
  final MusicPlayerController controller;

  const _ControlsRow({
    required this.colorScheme,
    required this.controller,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackStateProvider).value;
    final isPlaying = playback?.playing ?? false;
    final shuffleOn =
        playback?.shuffleMode == AudioServiceShuffleMode.all;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            icon: Icon(
              Icons.shuffle,
              size: 22,
              color: shuffleOn
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.4),
            ),
            onPressed: () => controller.setShuffle(!shuffleOn),
          ),
          IconButton(
            icon: Icon(
              Icons.skip_previous,
              size: 36,
              color: Colors.white,
            ),
            onPressed: controller.previous,
          ),
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) {
                  return ScaleTransition(
                    scale: animation,
                    child: FadeTransition(opacity: animation, child: child),
                  );
                },
                child: Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow,
                  key: ValueKey(isPlaying ? 'pause' : 'play'),
                  size: 36,
                  color: Colors.black,
                ),
              ),
              onPressed: () => controller.togglePlayPause(isPlaying),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.skip_next, size: 36, color: Colors.white),
            onPressed: controller.next,
          ),
          IconButton(
            icon: Icon(
              Icons.repeat,
              size: 22,
              color: Colors.white.withValues(alpha: 0.4),
            ),
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}

class _BottomRow extends StatelessWidget {
  final ColorScheme colorScheme;
  final VoidCallback onLyricsTap;

  const _BottomRow({
    required this.colorScheme,
    required this.onLyricsTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = Colors.white.withValues(alpha: 0.7);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(Icons.airplay, size: 22, color: iconColor),
          IconButton(
            icon: Icon(Icons.lyrics_outlined, size: 22, color: iconColor),
            onPressed: onLyricsTap,
          ),
          Icon(Icons.queue_music, size: 22, color: iconColor),
        ],
      ),
    );
  }
}

class _VolumeSlider extends StatelessWidget {
  final ColorScheme colorScheme;

  const _VolumeSlider({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: SizedBox(
        height: 20,
        child: SliderTheme(
          data: SliderThemeData(
            trackHeight: 2.5,
            activeTrackColor: Colors.white.withValues(alpha: 0.8),
            inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
            thumbShape: SliderComponentShape.noThumb,
            overlayShape: SliderComponentShape.noOverlay,
          ),
          child: Slider(
            value: 0.7,
            onChanged: (_) {},
          ),
        ),
      ),
    );
  }
}

class _LyricsPage extends ConsumerStatefulWidget {
  final ParsedLyrics lyrics;
  final bool loading;
  final ColorScheme colorScheme;

  const _LyricsPage({
    required this.lyrics,
    required this.loading,
    required this.colorScheme,
  });

  @override
  ConsumerState<_LyricsPage> createState() => _LyricsPageState();
}

class _LyricsPageState extends ConsumerState<_LyricsPage> {
  final ScrollController _scroll = ScrollController();
  int _active = -1;
  bool _userScrolling = false;
  static const double _estimatedLyricExtent = 64;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _maybeAutoScroll(int index) {
    if (_userScrolling || index < 0 || !_scroll.hasClients) return;
    final position = _scroll.position;
    final target = (index * _estimatedLyricExtent) -
        (position.viewportDimension * 0.35);
    final clamped = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _scroll.animateTo(
      clamped.toDouble(),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      );
    }

    if (widget.lyrics.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lyrics_outlined,
              size: 40,
              color: widget.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.nowPlayingNoLyrics,
              style: TextStyle(
                fontSize: 15,
                color: widget.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (widget.lyrics.synced) {
      return _buildSyncedLyrics();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 80),
      child: Text(
        widget.lyrics.plainText,
        style: const TextStyle(
          fontSize: 18,
          height: 1.7,
          color: Colors.white70,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildSyncedLyrics() {
    return Consumer(
      builder: (context, ref, _) {
        final position =
            ref.watch(playbackStateProvider).value?.position ?? Duration.zero;
        final lines = widget.lyrics.lines;
        final active = LyricsParser.activeIndex(lines, position);

        if (active != _active) {
          _active = active;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _maybeAutoScroll(active);
          });
        }

        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollStartNotification) {
              _userScrolling = true;
              Future.delayed(const Duration(seconds: 4), () {
                if (mounted) _userScrolling = false;
              });
            }
            return false;
          },
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
            itemCount: lines.length,
            itemBuilder: (context, index) {
              final line = lines[index];
              final isActive = index == active;
              final color = isActive
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.4);
              final text =
                  line.text.trim().isEmpty ? '\u00b7\u00b7\u00b7' : line.text;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: GestureDetector(
                  onTap: () => ref
                      .read(musicPlayerControllerProvider)
                      .seek(line.time),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 280),
                    style: TextStyle(
                      fontSize: isActive ? 24 : 18,
                      fontWeight:
                          isActive ? FontWeight.bold : FontWeight.w500,
                      color: color,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                    child: Text(text),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _Artwork extends StatelessWidget {
  final String? artUri;
  final int? cacheWidth;

  const _Artwork({required this.artUri, this.cacheWidth});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: Colors.white12,
      child: const Icon(
        Icons.music_note,
        size: 48,
        color: Colors.white24,
      ),
    );

    final uri = artUri;
    if (uri == null || uri.isEmpty) return placeholder;

    if (uri.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: uri,
        fit: BoxFit.cover,
        cacheManager: CoverCacheManager.instance,
        memCacheWidth: cacheWidth,
        fadeInDuration: const Duration(milliseconds: 150),
        fadeOutDuration: const Duration(milliseconds: 0),
        placeholder: (_, _) => placeholder,
        errorWidget: (_, _, _) => placeholder,
      );
    }
    if (uri.startsWith('file://')) {
      return Image.file(
        File(Uri.parse(uri).toFilePath()),
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        errorBuilder: (_, _, _) => placeholder,
      );
    }
    return placeholder;
  }
}
