import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/track_provider.dart';
import 'package:spotiflac_android/providers/music_player_provider.dart';
import 'package:spotiflac_android/widgets/cached_cover_image.dart';

class AMSearchTab extends ConsumerStatefulWidget {
  const AMSearchTab({super.key});

  @override
  ConsumerState<AMSearchTab> createState() => _AMSearchTabState();
}

class _AMSearchTabState extends ConsumerState<AMSearchTab> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasSearched = false;

  static const _browseCategories = [
    _BrowseCategory('Pop', Icons.star, Color(0xFFE91E63)),
    _BrowseCategory('Hip-Hop', Icons.mic, Color(0xFFFF9800)),
    _BrowseCategory('Electronic', Icons.bolt, Color(0xFF00BCD4)),
    _BrowseCategory('Rock', Icons.rocket, Color(0xFF795548)),
    _BrowseCategory('Jazz', Icons.queue_music, Color(0xFF3F51B5)),
    _BrowseCategory('Classical', Icons.piano, Color(0xFF9C27B0)),
    _BrowseCategory('R&B', Icons.radio, Color(0xFFE040FB)),
    _BrowseCategory('Latin', Icons.public, Color(0xFF009688)),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {
      _hasSearched = value.trim().isNotEmpty;
    });
    if (value.trim().isNotEmpty) {
      ref.read(trackProvider.notifier).search(value.trim());
    }
  }

  void _clearSearch() {
    _searchController.clear();
    _focusNode.unfocus();
    setState(() {
      _hasSearched = false;
    });
  }

  void _searchCategory(String category) {
    _searchController.text = category;
    _onSearchChanged(category);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    final trackState = ref.watch(trackProvider);
    final results = trackState.tracks;
    final isLoading = trackState.isLoading;
    final searchArtists = trackState.searchArtists;
    final searchAlbums = trackState.searchAlbums;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                child: Text(
                  'Search',
                  style: textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: _searchController,
                  focusNode: _focusNode,
                  onChanged: _onSearchChanged,
                  style: textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search music...',
                    hintStyle: textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    suffixIcon: _hasSearched
                        ? IconButton(
                            icon: Icon(
                              Icons.close,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            onPressed: _clearSearch,
                          )
                        : null,
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
            ),
            if (isLoading)
              SliverToBoxAdapter(
                child: LinearProgressIndicator(color: colorScheme.primary),
              ),
            if (_hasSearched && !isLoading) ...[
              if (trackState.error != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      trackState.error!,
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.error,
                      ),
                    ),
                  ),
                ),
              if (results.isEmpty &&
                  (searchArtists == null || searchArtists.isEmpty) &&
                  (searchAlbums == null || searchAlbums.isEmpty))
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptySearch(
                    colorScheme: colorScheme,
                    textTheme: textTheme,
                  ),
                ),
              if (results.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _ResultSectionHeader(
                    title: 'Songs',
                    colorScheme: colorScheme,
                    textTheme: textTheme,
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final track = results[index];
                      return _SearchTrackTile(track: track);
                    },
                    childCount: results.length,
                  ),
                ),
              ],
              if (searchAlbums != null && searchAlbums.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _ResultSectionHeader(
                    title: 'Albums',
                    colorScheme: colorScheme,
                    textTheme: textTheme,
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 180,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: searchAlbums.length,
                      itemBuilder: (context, index) {
                        final album = searchAlbums[index];
                        return _SearchAlbumCard(album: album);
                      },
                    ),
                  ),
                ),
                const SliverPadding(padding: EdgeInsets.only(top: 8)),
              ],
              if (searchArtists != null && searchArtists.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _ResultSectionHeader(
                    title: 'Artists',
                    colorScheme: colorScheme,
                    textTheme: textTheme,
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 160,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: searchArtists.length,
                      itemBuilder: (context, index) {
                        final artist = searchArtists[index];
                        return _SearchArtistCard(artist: artist);
                      },
                    ),
                  ),
                ),
                const SliverPadding(padding: EdgeInsets.only(top: 8)),
              ],
            ] else ...[
              SliverToBoxAdapter(
                child: _ResultSectionHeader(
                  title: 'Browse Categories',
                  colorScheme: colorScheme,
                  textTheme: textTheme,
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 2.0,
                  ),
                  delegate: SliverChildListDelegate(
                    _browseCategories
                        .map(
                          (c) => _BrowseCategoryCard(
                            category: c,
                            onTap: () => _searchCategory(c.label),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ],
            const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
          ],
        ),
      ),
    );
  }
}

class _BrowseCategory {
  final String label;
  final IconData icon;
  final Color color;

  const _BrowseCategory(this.label, this.icon, this.color);
}

class _ResultSectionHeader extends StatelessWidget {
  final String title;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  const _ResultSectionHeader({
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
        style: textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: colorScheme.onSurface,
        ),
      ),
    );
  }
}

class _BrowseCategoryCard extends StatelessWidget {
  final _BrowseCategory category;
  final VoidCallback onTap;

  const _BrowseCategoryCard({
    required this.category,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: category.color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(category.icon, color: category.color, size: 24),
              const SizedBox(width: 12),
              Text(
                category.label,
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: category.color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchTrackTile extends ConsumerWidget {
  final Track track;

  const _SearchTrackTile({required this.track});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 48,
          height: 48,
          child: _buildCover(track.coverUrl, colorScheme),
        ),
      ),
      title: Text(
        track.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        '${track.artistName} \u2014 ${track.albumName}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: const Icon(Icons.play_arrow_rounded, size: 28),
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
    );
  }
}

class _SearchAlbumCard extends StatelessWidget {
  final SearchAlbum album;

  const _SearchAlbumCard({required this.album});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        onTap: () {},
        child: SizedBox(
          width: 140,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 140,
                  height: 140,
                  child: _buildCover(album.imageUrl, colorScheme),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                album.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              Text(
                album.artists,
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

class _SearchArtistCard extends StatelessWidget {
  final SearchArtist artist;

  const _SearchArtistCard({required this.artist});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        onTap: () {},
        child: SizedBox(
          width: 120,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(60),
                child: SizedBox(
                  width: 100,
                  height: 100,
                  child: _buildCover(artist.imageUrl, colorScheme),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                artist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptySearch extends StatelessWidget {
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  const _EmptySearch({
    required this.colorScheme,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              size: 56,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'No results',
              style: textTheme.titleLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try a different search term.',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
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
      size: 28,
      color: colorScheme.onSurfaceVariant,
    ),
  );
}
