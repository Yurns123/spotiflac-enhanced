import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/providers/music_player_provider.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/widgets/cached_cover_image.dart';

class AMListenNowTab extends ConsumerWidget {
  const AMListenNowTab({super.key});

  Future<void> _onRefresh(WidgetRef ref) async {
    await ref.read(downloadHistoryProvider.notifier).reloadFromStorage();
    await ref.read(localLibraryProvider.notifier).reloadFromStorage();
  }

  void _playHistoryItem(WidgetRef ref, int index) {
    final history = ref.read(downloadHistoryProvider);
    if (history.items.isEmpty) return;
    final controller = ref.read(musicPlayerControllerProvider);
    controller.playHistory(history.items, initialIndex: index);
  }

  void _playLocalItem(WidgetRef ref, List<LocalLibraryItem> items, int index) {
    if (items.isEmpty) return;
    final controller = ref.read(musicPlayerControllerProvider);
    controller.playLocal(items, initialIndex: index);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    final historyItems =
        ref.watch(downloadHistoryProvider.select((s) => s.items));
    final recentItems = historyItems.take(10).toList();

    final localCount =
        ref.watch(localLibraryProvider.select((s) => s.totalCount));
    final localLibraryItems = ref.watch(
      localLibraryPageProvider(const LocalLibraryPageRequest(limit: 15)),
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => _onRefresh(ref),
          color: colorScheme.primary,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 8),
                  child: Text(
                    'Listen Now',
                    style: textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
              if (recentItems.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _AMSectionHeader(
                    title: 'Recently Played',
                    colorScheme: colorScheme,
                    textTheme: textTheme,
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 200,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: recentItems.length,
                      itemBuilder: (context, index) {
                        return _RecentlyPlayedCard(
                          item: recentItems[index],
                          index: index,
                          onTap: () => _playHistoryItem(ref, index),
                        );
                      },
                    ),
                  ),
                ),
              ],
              SliverToBoxAdapter(
                child: _AMSectionHeader(
                  title: 'Quick Picks',
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
                    childAspectRatio: 1.6,
                  ),
                  delegate: SliverChildListDelegate(const [
                    _QuickPickCard(
                      title: 'Pop',
                      color: Color(0xFFE91E63),
                      icon: Icons.celebration,
                    ),
                    _QuickPickCard(
                      title: 'Hip-Hop',
                      color: Color(0xFFFF9800),
                      icon: Icons.mic_external_on,
                    ),
                    _QuickPickCard(
                      title: 'Electronic',
                      color: Color(0xFF00BCD4),
                      icon: Icons.bolt,
                    ),
                    _QuickPickCard(
                      title: 'Chill',
                      color: Color(0xFF4CAF50),
                      icon: Icons.self_improvement,
                    ),
                  ]),
                ),
              ),
              if (localCount > 0) ...[
                SliverToBoxAdapter(
                  child: _AMSectionHeader(
                    title: 'Your Library',
                    colorScheme: colorScheme,
                    textTheme: textTheme,
                  ),
                ),
                localLibraryItems.when(
                  data: (items) {
                    if (items.isEmpty) {
                      return const SliverToBoxAdapter(child: SizedBox.shrink());
                    }
                    return SliverToBoxAdapter(
                      child: SizedBox(
                        height: 160,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            return _LibraryCard(
                              item: items[index],
                              index: index,
                              onTap: () =>
                                  _playLocalItem(ref, items, index),
                            );
                          },
                        ),
                      ),
                    );
                  },
                  loading: () => const SliverToBoxAdapter(
                    child: _ShimmerCards(),
                  ),
                  error: (_, __) =>
                      const SliverToBoxAdapter(child: SizedBox.shrink()),
                ),
              ],
              if (recentItems.isEmpty && localCount == 0)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(
                    icon: Icons.headphones,
                    title: 'Your music lives here',
                    subtitle:
                        'Downloaded tracks and local library items will appear here.',
                    colorScheme: colorScheme,
                  ),
                ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
            ],
          ),
        ),
      ),
    );
  }
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
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
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

class _RecentlyPlayedCard extends StatelessWidget {
  final DownloadHistoryItem item;
  final int index;
  final VoidCallback onTap;

  const _RecentlyPlayedCard({
    required this.item,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(
        left: index == 0 ? 4 : 0,
        right: 12,
      ),
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 160,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 160,
                  height: 160,
                  child: _buildCover(item.coverUrl, colorScheme),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                item.trackName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              Text(
                item.artistName,
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

class _LibraryCard extends StatelessWidget {
  final LocalLibraryItem item;
  final int index;
  final VoidCallback onTap;

  const _LibraryCard({
    required this.item,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(
        left: index == 0 ? 4 : 0,
        right: 12,
      ),
      child: GestureDetector(
        onTap: onTap,
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
                  child: _buildCover(item.coverPath, colorScheme),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                item.trackName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              Text(
                item.artistName,
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

class _QuickPickCard extends StatelessWidget {
  final String title;
  final Color color;
  final IconData icon;

  const _QuickPickCard({
    required this.title,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$title — coming soon'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 1),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShimmerCards extends StatelessWidget {
  const _ShimmerCards();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 160,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: 4,
        itemBuilder: (context, index) {
          return Padding(
            padding: EdgeInsets.only(
              left: index == 0 ? 4 : 0,
              right: 12,
            ),
            child: SizedBox(
              width: 140,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 100,
                    height: 12,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 70,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final ColorScheme colorScheme;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
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
  }
}

Widget _buildCover(String? coverUrl, ColorScheme colorScheme) {
  if (coverUrl != null && coverUrl.isNotEmpty) {
    if (coverUrl.startsWith('http')) {
      return CachedCoverImage(imageUrl: coverUrl, fit: BoxFit.cover);
    }
    final file = File(coverUrl);
    return Image(
      image: FileImage(file),
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
      size: 48,
      color: colorScheme.onSurfaceVariant,
    ),
  );
}
