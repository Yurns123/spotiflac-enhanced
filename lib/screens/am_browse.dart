import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/providers/track_provider.dart';
import 'package:spotiflac_android/providers/music_player_provider.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/widgets/cached_cover_image.dart';

class AMBrowseTab extends ConsumerWidget {
  const AMBrowseTab({super.key});

  static const _categories = [
    _CategoryItem('Pop', Icons.star, Color(0xFFE91E63)),
    _CategoryItem('Rock', Icons.rocket, Color(0xFF795548)),
    _CategoryItem('Hip-Hop', Icons.mic, Color(0xFFFF9800)),
    _CategoryItem('Electronic', Icons.bolt, Color(0xFF00BCD4)),
    _CategoryItem('Jazz', Icons.queue_music, Color(0xFF3F51B5)),
    _CategoryItem('Classical', Icons.piano, Color(0xFF9C27B0)),
    _CategoryItem('R&B', Icons.radio, Color(0xFFE040FB)),
    _CategoryItem('Alternative', Icons.disc_full, Color(0xFF607D8B)),
  ];

  static const _playlists = [
    _PlaylistItem('New Music Daily', 'The latest tracks added today'),
    _PlaylistItem('Today\'s Hits', 'The biggest songs right now'),
    _PlaylistItem('Chill Vibes', 'Relax and unwind'),
    _PlaylistItem('Workout Energy', 'Push through your workout'),
    _PlaylistItem('Focus Flow', 'Music for concentration'),
    _PlaylistItem('Throwback Thursday', 'Classics you forgot about'),
    _PlaylistItem('Indie Discovery', 'Find your next favorite artist'),
    _PlaylistItem('Late Night Sounds', 'Music for after hours'),
  ];

  void _searchCategory(WidgetRef ref, String category) {
    ref.read(trackProvider.notifier).search(category);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    final trendingState = ref.watch(trackProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar.large(
              pinned: true,
              centerTitle: false,
              title: Text(
                'Browse',
                style: textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: EdgeInsets.zero,
                title: null,
              ),
            ),
            SliverToBoxAdapter(
              child: _AMSectionHeader(
                title: 'Categories',
                colorScheme: colorScheme,
                textTheme: textTheme,
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 100,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _categories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final cat = _categories[index];
                    return _CategoryChip(
                      label: cat.label,
                      icon: cat.icon,
                      color: cat.color,
                      onTap: () => _searchCategory(ref, cat.label),
                    );
                  },
                ),
              ),
            ),
            if (trendingState.tracks.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _AMSectionHeader(
                  title: 'New Releases',
                  colorScheme: colorScheme,
                  textTheme: textTheme,
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 190,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: trendingState.tracks.length.clamp(0, 15),
                    itemBuilder: (context, index) {
                      final track = trendingState.tracks[index];
                      return _NewReleaseCard(track: track);
                    },
                  ),
                ),
              ),
            ],
            SliverToBoxAdapter(
              child: _AMSectionHeader(
                title: 'Featured Playlists',
                colorScheme: colorScheme,
                textTheme: textTheme,
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.72,
                ),
                delegate: SliverChildListDelegate(
                  _playlists
                      .map(
                        (p) => _FeaturedPlaylistCard(
                          playlist: p,
                          colorScheme: colorScheme,
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
          ],
        ),
      ),
    );
  }
}

class _CategoryItem {
  final String label;
  final IconData icon;
  final Color color;

  const _CategoryItem(this.label, this.icon, this.color);
}

class _PlaylistItem {
  final String name;
  final String description;

  const _PlaylistItem(this.name, this.description);
}

class _AMSectionHeader extends StatelessWidget {
  final String title;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  const _AMSectionHeader({
    required this.title,
    required this.colorScheme,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: Text(
        title,
        style: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: colorScheme.onSurface,
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _NewReleaseCard extends ConsumerWidget {
  final Track track;

  const _NewReleaseCard({required this.track});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        onTap: () {
          final controller = ref.read(musicPlayerControllerProvider);
          final playable = PlayableMedia(
            id: track.id,
            source: track.previewUrl ?? '',
            title: track.name,
            artist: track.artistName,
            album: track.albumName,
            artUri: track.coverUrl,
          );
          controller.playSingle(playable);
        },
        child: SizedBox(
          width: 150,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 150,
                  height: 150,
                  child: _buildCover(track.coverUrl, colorScheme),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                track.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              Text(
                track.albumName.isNotEmpty ? track.albumName : track.artistName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeaturedPlaylistCard extends StatelessWidget {
  final _PlaylistItem playlist;
  final ColorScheme colorScheme;

  const _FeaturedPlaylistCard({
    required this.playlist,
    required this.colorScheme,
  });

  static const _gradients = [
    [Color(0xFFE91E63), Color(0xFF9C27B0)],
    [Color(0xFF00BCD4), Color(0xFF2196F3)],
    [Color(0xFFFF9800), Color(0xFFF44336)],
    [Color(0xFF4CAF50), Color(0xFF8BC34A)],
    [Color(0xFF3F51B5), Color(0xFF673AB7)],
    [Color(0xFF009688), Color(0xFF4DB6AC)],
    [Color(0xFFFF5722), Color(0xFFFF9800)],
    [Color(0xFF607D8B), Color(0xFF455A64)],
  ];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = _gradients[playlist.name.hashCode.abs() % _gradients.length];

    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${playlist.name} — coming soon'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 1),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Spacer(),
            Text(
              playlist.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              playlist.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(
                color: Colors.white70,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _buildCover(String? coverUrl, ColorScheme colorScheme) {
  if (coverUrl != null && coverUrl.isNotEmpty) {
    return CachedCoverImage(imageUrl: coverUrl, fit: BoxFit.cover);
  }
  return Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          colorScheme.primaryContainer,
          colorScheme.secondaryContainer,
        ],
      ),
    ),
    child: Icon(
      Icons.music_note,
      size: 48,
      color: colorScheme.onSurfaceVariant,
    ),
  );
}
