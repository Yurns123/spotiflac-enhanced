import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/providers/music_player_provider.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/widgets/cached_cover_image.dart';

enum _LibrarySegment { playlists, artists, albums, songs, downloaded }

class AMLibraryTab extends ConsumerStatefulWidget {
  const AMLibraryTab({super.key});

  @override
  ConsumerState<AMLibraryTab> createState() => _AMLibraryTabState();
}

class _AMLibraryTabState extends ConsumerState<AMLibraryTab> {
  _LibrarySegment _segment = _LibrarySegment.songs;

  Future<void> _onRefresh() async {
    await ref.read(localLibraryProvider.notifier).reloadFromStorage();
    await ref.read(downloadHistoryProvider.notifier).reloadFromStorage();
  }

  void _playHistory(WidgetRef ref, int index) {
    final items = ref.read(downloadHistoryProvider).items;
    if (items.isEmpty) return;
    ref
        .read(musicPlayerControllerProvider)
        .playHistory(items, initialIndex: index);
  }

  void _playLocal(
    WidgetRef ref,
    List<LocalLibraryItem> items,
    int index,
  ) {
    if (items.isEmpty) return;
    ref
        .read(musicPlayerControllerProvider)
        .playLocal(items, initialIndex: index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final l10n = context.l10n;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          color: colorScheme.primary,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                  child: Text(
                    l10n.navLibrary,
                    style: textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _LibrarySegmentedControl(
                  selected: _segment,
                  onChanged: (value) {
                    setState(() => _segment = value);
                  },
                  colorScheme: colorScheme,
                ),
              ),
              const SliverPadding(padding: EdgeInsets.only(top: 8)),
              switch (_segment) {
                _LibrarySegment.songs => _SongsTab(
                    onPlay: (items, index) => _playLocal(ref, items, index),
                  ),
                _LibrarySegment.downloaded => _DownloadedTab(
                    onPlay: (index) => _playHistory(ref, index),
                  ),
                _LibrarySegment.artists => _ArtistsTab(
                    onPlay: (items, index) => _playLocal(ref, items, index),
                  ),
                _LibrarySegment.albums => const _AlbumsTab(),
                _LibrarySegment.playlists => _EmptySegment(
                    icon: Icons.playlist_play,
                    title: 'No Playlists',
                    subtitle: 'Create playlists to organize your music.',
                    colorScheme: colorScheme,
                  ),
              },
              const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibrarySegmentedControl extends StatelessWidget {
  final _LibrarySegment selected;
  final ValueChanged<_LibrarySegment> onChanged;
  final ColorScheme colorScheme;

  const _LibrarySegmentedControl({
    required this.selected,
    required this.onChanged,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: _LibrarySegment.values.map((segment) {
          final isSelected = selected == segment;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(segment.displayName),
              selected: isSelected,
              onSelected: (_) => onChanged(segment),
              selectedColor: colorScheme.primary,
              labelStyle: TextStyle(
                color: isSelected
                    ? colorScheme.onPrimary
                    : colorScheme.onSurface,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
              checkmarkColor: colorScheme.onPrimary,
              side: BorderSide(
                color: isSelected
                    ? Colors.transparent
                    : colorScheme.outlineVariant,
              ),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SongsTab extends ConsumerWidget {
  final void Function(List<LocalLibraryItem> items, int index) onPlay;

  const _SongsTab({required this.onPlay});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    final items = ref.watch(
      localLibraryPageProvider(const LocalLibraryPageRequest(limit: 50)),
    );

    return items.when(
      data: (tracks) {
        if (tracks.isEmpty) {
          return _EmptySegment(
            icon: Icons.music_note,
            title: 'No Songs',
            subtitle: 'Scan your device to find music files.',
            colorScheme: colorScheme,
          ).sliverFill;
        }
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final track = tracks[index];
              return _SongTile(
                track: track,
                onTap: () => onPlay(tracks, index),
                onMenu: () => _showTrackMenu(context, ref, track),
              );
            },
            childCount: tracks.length,
          ),
        );
      },
      loading: () => const SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ),
        ),
      ),
      error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
    );
  }
}

class _DownloadedTab extends ConsumerWidget {
  final void Function(int index) onPlay;

  const _DownloadedTab({required this.onPlay});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final historyItems = ref.watch(
      downloadHistoryProvider.select((s) => s.items),
    );

    if (historyItems.isEmpty) {
      return _EmptySegment(
        icon: Icons.cloud_download_outlined,
        title: 'No Downloads',
        subtitle: 'Downloaded tracks will appear here.',
        colorScheme: colorScheme,
      ).sliverFill;
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final item = historyItems[index];
          return _HistoryTile(
            item: item,
            onTap: () => onPlay(index),
            onMenu: () => _showHistoryMenu(context, ref, item),
          );
        },
        childCount: historyItems.length,
      ),
    );
  }
}

class _ArtistsTab extends ConsumerWidget {
  final void Function(List<LocalLibraryItem> items, int index) onPlay;

  const _ArtistsTab({required this.onPlay});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    final items = ref.watch(
      localLibraryPageProvider(
        const LocalLibraryPageRequest(limit: 200, sortMode: LocalLibrarySortMode.artist),
      ),
    );

    return items.when(
      data: (tracks) {
        if (tracks.isEmpty) {
          return _EmptySegment(
            icon: Icons.person,
            title: 'No Artists',
            subtitle: 'Scanned tracks with artist info will appear here.',
            colorScheme: colorScheme,
          ).sliverFill;
        }

        final grouped = <String, List<LocalLibraryItem>>{};
        for (final t in tracks) {
          grouped.putIfAbsent(t.artistName, () => []).add(t);
        }
        final artists = grouped.entries.toList();

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverGrid(
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.85,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final artist = artists[index];
                final coverPath =
                    artist.value
                        .firstWhere(
                          (t) =>
                              t.coverPath != null &&
                              t.coverPath!.isNotEmpty,
                          orElse: () => artist.value.first,
                        )
                        .coverPath;
                return _GridItemCard(
                  title: artist.key,
                  subtitle: '${artist.value.length} tracks',
                  coverPath: coverPath,
                  colorScheme: colorScheme,
                  onTap: () => onPlay(artist.value, 0),
                );
              },
              childCount: artists.length,
            ),
          ),
        );
      },
      loading: () => const SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ),
        ),
      ),
      error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
    );
  }
}

class _AlbumsTab extends ConsumerWidget {
  const _AlbumsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    final albums = ref.watch(
      localLibraryAlbumPageProvider(
        const LocalLibraryAlbumPageRequest(limit: 50),
      ),
    );

    return albums.when(
      data: (items) {
        if (items.isEmpty) {
          return _EmptySegment(
            icon: Icons.album,
            title: 'No Albums',
            subtitle: 'Scanned tracks with album info will appear here.',
            colorScheme: colorScheme,
          ).sliverFill;
        }
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverGrid(
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.82,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final album = items[index];
                return _AlbumCard(
                  album: album,
                  colorScheme: colorScheme,
                );
              },
              childCount: items.length,
            ),
          ),
        );
      },
      loading: () => const SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ),
        ),
      ),
      error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
    );
  }
}

class _SongTile extends StatelessWidget {
  final LocalLibraryItem track;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  const _SongTile({
    required this.track,
    required this.onTap,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 44,
          height: 44,
          child: _buildCover(track.coverPath, colorScheme),
        ),
      ),
      title: Text(
        track.trackName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        track.artistName.isNotEmpty
            ? '${track.artistName}${track.albumName.isNotEmpty ? ' \u2014 ${track.albumName}' : ''}'
            : track.albumName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.more_horiz, size: 20),
        onPressed: onMenu,
        visualDensity: VisualDensity.compact,
      ),
      onTap: onTap,
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final DownloadHistoryItem item;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  const _HistoryTile({
    required this.item,
    required this.onTap,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 44,
          height: 44,
          child: _buildCover(item.coverUrl, colorScheme),
        ),
      ),
      title: Text(
        item.trackName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        item.artistName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.more_horiz, size: 20),
        onPressed: onMenu,
        visualDensity: VisualDensity.compact,
      ),
      onTap: onTap,
    );
  }
}

class _GridItemCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? coverPath;
  final ColorScheme colorScheme;
  final VoidCallback? onTap;

  const _GridItemCard({
    required this.title,
    required this.subtitle,
    required this.coverPath,
    required this.colorScheme,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: double.infinity,
              child: AspectRatio(
                aspectRatio: 1,
                child: _buildCover(coverPath, colorScheme),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  final LocalLibraryAlbumGroup album;
  final ColorScheme colorScheme;

  const _AlbumCard({required this.album, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: () {},
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: double.infinity,
              child: AspectRatio(
                aspectRatio: 1,
                child: _buildCover(album.coverPath, colorScheme),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            album.albumName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            album.artistName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptySegment extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final ColorScheme colorScheme;

  const _EmptySegment({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colorScheme,
  });

  Widget get sliverFill {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: buildBody(),
    );
  }

  Widget buildBody() {
    return Builder(builder: (context) {
      final textTheme = Theme.of(context).textTheme;
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 64,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: textTheme.titleLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => buildBody();
}

void _showTrackMenu(
  BuildContext context,
  WidgetRef ref,
  LocalLibraryItem track,
) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  Text(
                    track.trackName,
                    style: Theme.of(ctx).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    track.artistName,
                    style: Theme.of(ctx).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.playlist_play),
              title: const Text('Play Next'),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(musicPlayerControllerProvider).playNextLocal(track);
              },
            ),
            ListTile(
              leading: const Icon(Icons.queue_music),
              title: const Text('Add to Queue'),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(musicPlayerControllerProvider).addToQueueLocal(track);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(ctx).colorScheme.error,
              ),
              title: Text(
                'Delete',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(localLibraryProvider.notifier).removeItem(track.id);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      );
    },
  );
}

void _showHistoryMenu(
  BuildContext context,
  WidgetRef ref,
  DownloadHistoryItem item,
) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  Text(
                    item.trackName,
                    style: Theme.of(ctx).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.artistName,
                    style: Theme.of(ctx).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.playlist_play),
              title: const Text('Play Next'),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(musicPlayerControllerProvider).playNextHistory(item);
              },
            ),
            ListTile(
              leading: const Icon(Icons.queue_music),
              title: const Text('Add to Queue'),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(musicPlayerControllerProvider).addToQueueHistory(item);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(ctx).colorScheme.error,
              ),
              title: Text(
                'Delete',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
              onTap: () {
                Navigator.pop(ctx);
                ref
                    .read(downloadHistoryProvider.notifier)
                    .removeFromHistory(item.id);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      );
    },
  );
}

Widget _buildCover(String? coverUrl, ColorScheme colorScheme) {
  if (coverUrl != null && coverUrl.isNotEmpty) {
    if (coverUrl.startsWith('http')) {
      return CachedCoverImage(imageUrl: coverUrl, fit: BoxFit.cover);
    }
    return Image(
      image: FileImage(File(coverUrl)),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _coverPlaceholder(colorScheme),
    );
  }
  return _coverPlaceholder(colorScheme);
}

Widget _coverPlaceholder(ColorScheme colorScheme) {
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

extension _LibrarySegmentX on _LibrarySegment {
  String get displayName => switch (this) {
        _LibrarySegment.playlists => 'Playlists',
        _LibrarySegment.artists => 'Artists',
        _LibrarySegment.albums => 'Albums',
        _LibrarySegment.songs => 'Songs',
        _LibrarySegment.downloaded => 'Downloaded',
      };
}
