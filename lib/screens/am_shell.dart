import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/providers/music_player_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/providers/preview_player_provider.dart';
import 'package:spotiflac_android/providers/preload_provider.dart';
import 'package:spotiflac_android/providers/streaming_provider.dart';
import 'package:spotiflac_android/providers/track_provider.dart';
import 'package:spotiflac_android/screens/am_listen_now.dart';
import 'package:spotiflac_android/screens/am_browse.dart';
import 'package:spotiflac_android/screens/am_library.dart';
import 'package:spotiflac_android/screens/am_search.dart';
import 'package:spotiflac_android/services/music_player_service.dart';
import 'package:spotiflac_android/services/notification_service.dart';
import 'package:spotiflac_android/widgets/am_mini_player.dart';
import 'package:spotiflac_android/utils/logger.dart';

final _log = AppLogger('AMShell');

final currentAMTabProvider = StateProvider<int>((ref) => 0);

class AMShell extends ConsumerStatefulWidget {
  const AMShell({super.key});

  @override
  ConsumerState<AMShell> createState() => _AMShellState();
}

class _AMShellState extends ConsumerState<AMShell> with TickerProviderStateMixin {
  late final PageController _pageController;
  late final TabController _tabController;
  final GlobalKey<NavigatorState> _listenNowNavKey = GlobalKey<NavigatorState>();
  final GlobalKey<NavigatorState> _browseNavKey = GlobalKey<NavigatorState>();
  final GlobalKey<NavigatorState> _libraryNavKey = GlobalKey<NavigatorState>();
  final GlobalKey<NavigatorState> _searchNavKey = GlobalKey<NavigatorState>();
  DateTime? _lastBackPress;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this, initialIndex: 0);
    _pageController = PageController(initialPage: 0);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        ref.read(currentAMTabProvider.notifier).state = _tabController.index;
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = context.l10n;
    NotificationService().updateStrings(l10n);
    updateMusicPlayerStrings(unknownTitle: l10n.unknownTitle, unknownArtist: l10n.unknownArtist);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<bool> _onWillPop() async {
    final now = DateTime.now();
    if (_lastBackPress != null && now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return true;
    }
    _lastBackPress = now;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.pressBackAgainToExit),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final queueCount = ref.watch(downloadQueueProvider.select((s) => s.queuedCount));
    final mediaItem = ref.watch(currentMediaItemProvider).valueOrNull;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _onWillPop();
      },
      child: Scaffold(
        body: Stack(
          children: [
            // Main content with PageView
            Padding(
              padding: EdgeInsets.only(bottom: mediaItem != null ? 64 : 0),
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _TabNavigator(navigatorKey: _listenNowNavKey, child: const AMListenNowTab()),
                  _TabNavigator(navigatorKey: _browseNavKey, child: const AMBrowseTab()),
                  _TabNavigator(navigatorKey: _libraryNavKey, child: const AMLibraryTab()),
                  _TabNavigator(navigatorKey: _searchNavKey, child: const AMSearchTab()),
                ],
              ),
            ),
            // Mini player at bottom
            if (mediaItem != null)
              Positioned(
                left: 8,
                right: 8,
                bottom: 0,
                child: const AMMiniPlayer(),
              ),
          ],
        ),
        bottomNavigationBar: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
              ),
              child: SafeArea(
                child: SizedBox(
                  height: 56,
                  child: TabBar(
                    controller: _tabController,
                    onTap: (index) {
                      _pageController.jumpToPage(index);
                      ref.read(currentAMTabProvider.notifier).state = index;
                    },
                    labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                    unselectedLabelStyle: const TextStyle(fontSize: 11),
                    indicatorSize: TabBarIndicatorSize.label,
                    indicatorColor: Theme.of(context).colorScheme.primary,
                    dividerColor: Colors.transparent,
                    tabs: [
                      Tab(icon: const Icon(Icons.play_circle_outline, size: 22), text: l10n.navHome),
                      Tab(icon: const Icon(Icons.explore_outlined, size: 22), text: 'Browse'),
                      Tab(
                        icon: Badge(
                          isLabelVisible: queueCount > 0,
                          label: Text('$queueCount'),
                          child: const Icon(Icons.library_music_outlined, size: 22),
                        ),
                        text: l10n.navLibrary,
                      ),
                      Tab(icon: const Icon(Icons.search, size: 22), text: 'Search'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabNavigator extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  const _TabNavigator({required this.navigatorKey, required this.child});

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      onGenerateInitialRoutes: (_, _) => [
        MaterialPageRoute<void>(builder: (_) => child),
      ],
    );
  }
}
