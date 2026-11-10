import '../theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/transcript.dart';
import '../models/digest.dart';
import '../services/api_service.dart';
import '../widgets/digest_card.dart';
import '../widgets/transcript_tile.dart';
import '../widgets/bottom_bar.dart';
import 'recording_screen.dart';
import 'chat_screen.dart';
import 'search_screen.dart';
import 'connect_screen.dart';
import 'settings_screen.dart';
import 'transcript_screen.dart';
import 'calendar_screen.dart';
import 'tasks_screen.dart';
import 'recap_screen.dart';
import 'day_conversations_screen.dart';
import 'all_recaps_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  late AnimationController _skeletonController;
  List<Digest> _digests = []; // one card per recent day
  List<Transcript> _transcripts = [];
  final Set<String> _pendingDeleteIds = {};
  int _loadRequestId = 0;
  bool _loading = true;
  bool _loadFailed = false;
  bool _generatingRecaps = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _skeletonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _loadData(showLoading: true);
  }

  Future<void> _loadData({bool showLoading = false}) async {
    final requestId = ++_loadRequestId;
    if (showLoading || (_digests.isEmpty && _transcripts.isEmpty)) {
      setState(() => _loading = true);
    }
    List<Digest>? digests;
    List<Transcript>? transcripts;
    await Future.wait([
      () async {
        try {
          digests = await ApiService.getDigests().timeout(
            const Duration(seconds: 10),
          );
        } catch (_) {}
      }(),
      () async {
        try {
          transcripts = await ApiService.getTranscripts().timeout(
            const Duration(seconds: 10),
          );
        } catch (_) {}
      }(),
    ]);
    if (!mounted || requestId != _loadRequestId) return;
    setState(() {
      if (digests != null) _digests = digests!;
      if (transcripts != null) {
        _transcripts = transcripts!
            .where((t) => !_pendingDeleteIds.contains(t.id))
            .toList();
      }
      _loadFailed = digests == null || transcripts == null;
      _loading = false;
    });
  }

  Future<void> _refreshDigestsOnly() async {
    try {
      final digests = await ApiService.getDigests();
      if (!mounted) return;
      setState(() => _digests = digests);
    } catch (_) {
      // Keep the current row if a silent refresh fails.
    }
  }

  // Calendar "Done" returns the picked date — open that day's recap screen
  Future<void> _showRecapFor(DateTime date) async {
    final key =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DayConversationsScreen(date: key)),
    );
  }

  Future<void> _showRecapSummaryFor(DateTime date) async {
    final key =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final deleted = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RecapScreen(date: key)),
    );
    if (deleted == true) {
      setState(() {
        _digests = [
          for (final digest in _digests)
            if (_dateKey(digest.date) != key) digest,
        ];
      });
    } else {
      _refreshDigestsOnly();
    }
  }

  @override
  void dispose() {
    _skeletonController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.homeBackground,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.homeBackground,
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              _buildTabBar(),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [_buildHomeTab(), const TasksScreen()],
                ),
              ),
              BottomBar(
                onRecordTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        RecordingScreen(onUploadFinished: _loadData),
                  ),
                ).then((_) => _loadData()),
                onAskAnythingTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ChatScreen()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ConnectScreen()),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.homeCard,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Row(
                children: [
                  Image.asset(
                    'assets/images/icons8-link-512.png',
                    width: 20,
                    height: 20,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Link',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.homeInk,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          _topIcon(
            Icons.calendar_today_outlined,
            () {
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (_) => const CalendarScreen(),
              ).then((result) {
                if (result is DateTime) _showRecapFor(result);
              });
            },
            child: Image.asset(
              'assets/images/icons8-calendar-512.png',
              width: 22,
              height: 22,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 8),
          _topIcon(
            Icons.search,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
          const SizedBox(width: 8),
          _topIcon(
            Icons.settings_outlined,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topIcon(IconData icon, VoidCallback onTap, {Widget? child}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: AppColors.homeCard,
          borderRadius: BorderRadius.circular(19),
        ),
        child: Center(
          child: child ?? Icon(icon, color: AppColors.homeInk, size: 21),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
        child: TabBar(
          controller: _tabController,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          dividerColor: Colors.transparent,
          indicator: const BoxDecoration(),
          labelPadding: const EdgeInsets.only(right: 20),
          labelColor: AppColors.homeInk,
          unselectedLabelColor: AppColors.homeMuted,
          labelStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 30,
            fontWeight: FontWeight.w600,
          ),
          tabs: const [
            Tab(text: 'Home'),
            Tab(text: 'Tasks'),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppColors.homeAccent,
      backgroundColor: AppColors.homeCard,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        children: [
          const SizedBox(height: 4),
          if (_loadFailed) ...[
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Could not load all data. Check your connection.',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: AppColors.homeInk,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => _loadData(showLoading: true),
                  child: const Text('Retry'),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          _buildDailyRecapsSection(),
          const SizedBox(height: 28),
          _buildTodaySection(),
        ],
      ),
    );
  }

  Widget _buildDailyRecapsSection() {
    final missingRecapDates = _missingRecapDates();
    final showGenerateCard = !_loading && missingRecapDates.isNotEmpty;
    final visibleDigests = _digests.take(5).toList();
    final recapCardCount = visibleDigests.length + (showGenerateCard ? 1 : 0);
    final recapBody = _loading
        ? _buildRecapSkeleton()
        : recapCardCount == 0
        ? _emptyRecapCard()
        : SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: recapCardCount,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, i) {
                if (i >= visibleDigests.length) {
                  return _generateRecapCard(missingRecapDates);
                }
                final d = visibleDigests[i];
                return DigestCard(
                  digest: d,
                  onTap: () => _showRecapSummaryFor(d.date),
                );
              },
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Daily Recaps',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColors.homeInk,
              ),
            ),
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AllRecapsScreen()),
              ).then((_) => _refreshDigestsOnly()),
              child: const Text(
                'View All',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: AppColors.homeMuted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeOutCubic,
          child: KeyedSubtree(
            key: ValueKey(
              _loading ? 'recap-loading' : 'recap-ready-$recapCardCount',
            ),
            child: recapBody,
          ),
        ),
      ],
    );
  }

  Widget _generateRecapCard(List<String> missingDates) {
    final count = missingDates.length;
    return GestureDetector(
      onTap: _generatingRecaps
          ? null
          : () => _generateMissingRecaps(missingDates),
      child: Container(
        width: 246,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          color: AppColors.homeInk,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.homeInk),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              color: _generatingRecaps ? Colors.white54 : Colors.white,
              size: 20,
            ),
            const Spacer(),
            Text(
              _generatingRecaps
                  ? 'Generating recaps'
                  : 'Generate missing recaps',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              count == 1 ? '1 day needs a recap.' : '$count days need recaps.',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyRecapCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.homeCard,
        borderRadius: BorderRadius.circular(28),
      ),
      child: const Text(
        'No recap yet.\nRecord your first conversation.',
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: AppColors.homeMuted,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _buildTodaySection() {
    final recordingsBody = _loading
        ? _buildRecordingSkeleton()
        : _transcripts.isEmpty
        ? Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.homeCard,
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Text(
              'No recordings yet.',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.homeMuted,
              ),
            ),
          )
        : Column(children: _buildGroupedTranscriptTiles());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recordings',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppColors.homeInk,
          ),
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeOutCubic,
          child: KeyedSubtree(
            key: ValueKey(
              _loading
                  ? 'recording-loading'
                  : 'recording-ready-${_transcripts.length}',
            ),
            child: recordingsBody,
          ),
        ),
      ],
    );
  }

  Widget _buildRecapSkeleton() {
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 2,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          return _ShimmerBox(
            animation: _skeletonController,
            width: 246,
            height: 132,
            radius: 22,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SkeletonLine(
                    animation: _skeletonController,
                    width: 108,
                    height: 15,
                  ),
                  const SizedBox(height: 14),
                  _SkeletonLine(
                    animation: _skeletonController,
                    width: 180,
                    height: 18,
                  ),
                  const SizedBox(height: 12),
                  _SkeletonLine(
                    animation: _skeletonController,
                    width: 204,
                    height: 15,
                  ),
                  const SizedBox(height: 8),
                  _SkeletonLine(
                    animation: _skeletonController,
                    width: 162,
                    height: 15,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRecordingSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SkeletonLine(animation: _skeletonController, width: 96, height: 18),
        const SizedBox(height: 18),
        for (var i = 0; i < 3; i++) ...[
          _ShimmerBox(
            animation: _skeletonController,
            width: double.infinity,
            height: 86,
            radius: 24,
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 18),
        _SkeletonLine(animation: _skeletonController, width: 96, height: 18),
        const SizedBox(height: 18),
        _ShimmerBox(
          animation: _skeletonController,
          width: double.infinity,
          height: 86,
          radius: 24,
        ),
      ],
    );
  }

  /// Cards grouped by day — "Today", "Yesterday", then "Wed, Nov 5" style
  /// labels above the first card of each older day.
  List<Widget> _buildGroupedTranscriptTiles() {
    final tiles = <Widget>[];
    String? lastLabel;

    for (final t in _transcripts) {
      final label = _dayLabel(t.recordedAt);
      if (label != lastLabel) {
        lastLabel = label;
        tiles.add(_dayHeader(label));
      }
      tiles.add(
        _SwipeDeleteTile(
          key: ValueKey('home-transcript-${t.id}'),
          onDismissed: () => _deleteTranscriptWithUndo(t),
          child: TranscriptTile(
            transcript: t,
            onTap: () =>
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TranscriptScreen(transcript: t),
                  ),
                ).then((result) {
                  // data may have changed (renamed / deleted / starred)
                  if (result != null) _loadData();
                }),
          ),
        ),
      );
    }
    return tiles;
  }

  Future<void> _deleteTranscriptWithUndo(Transcript transcript) async {
    final index = _transcripts.indexWhere((t) => t.id == transcript.id);
    if (index == -1) return;

    _pendingDeleteIds.add(transcript.id);
    setState(() {
      _transcripts = [
        for (final t in _transcripts)
          if (t.id != transcript.id) t,
      ];
    });

    var undone = false;
    void restore() {
      _pendingDeleteIds.remove(transcript.id);
      if (!mounted) return;
      setState(() {
        if (_transcripts.any((t) => t.id == transcript.id)) return;
        final restored = [..._transcripts];
        restored.insert(index.clamp(0, restored.length), transcript);
        _transcripts = restored;
      });
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text(
          'Recording deleted',
          style: TextStyle(color: AppColors.ink),
        ),
        backgroundColor: AppColors.homeCard,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 104),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        duration: const Duration(seconds: 2),
        persist: false,
        action: SnackBarAction(
          label: 'Undo',
          textColor: Colors.black,
          onPressed: () {
            undone = true;
            restore();
          },
        ),
      ),
    );

    // Keep the server delete independent of whether Home is still mounted.
    await Future.delayed(const Duration(seconds: 2));
    if (undone) return;

    try {
      await ApiService.deleteTranscript(transcript.id);
      if (mounted) await _loadData();
      _pendingDeleteIds.remove(transcript.id);
    } catch (_) {
      restore();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not delete recording'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  List<String> _missingRecapDates() {
    final digestDates = _digests.map((d) => _dateKey(d.date)).toSet();
    final recordingDates = <String>{};

    for (final transcript in _transcripts) {
      if (transcript.status != 'completed' || transcript.text.trim().isEmpty)
        continue;
      recordingDates.add(_dateKey(transcript.recordedAt));
    }

    final missing = recordingDates
        .where((date) => !digestDates.contains(date))
        .toList();
    missing.sort((a, b) => b.compareTo(a));
    return missing;
  }

  Future<void> _generateMissingRecaps(List<String> dates) async {
    if (_generatingRecaps || dates.isEmpty) return;

    setState(() => _generatingRecaps = true);
    final generated = <Digest>[];
    var failed = 0;
    for (final date in dates) {
      try {
        generated.add(await ApiService.generateDigest(date));
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() {
      final byDate = {
        for (final digest in _digests) _dateKey(digest.date): digest,
        for (final digest in generated) _dateKey(digest.date): digest,
      };
      _digests = byDate.values.toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      _generatingRecaps = false;
    });
    if (failed > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failed == 1
                ? 'Could not generate 1 recap. Try again.'
                : 'Could not generate $failed recaps. Try again.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  String _dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String _dayLabel(DateTime recorded) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(recorded.year, recorded.month, recorded.day);
    final diff = today.difference(day).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    final d = recorded;
    return '${_days[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}';
  }

  Widget _dayHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 0, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.homeInk,
          ),
        ),
      ),
    );
  }
}

class _SwipeDeleteTile extends StatefulWidget {
  final Widget child;
  final VoidCallback onDismissed;

  const _SwipeDeleteTile({
    super.key,
    required this.child,
    required this.onDismissed,
  });

  @override
  State<_SwipeDeleteTile> createState() => _SwipeDeleteTileState();
}

class _SwipeDeleteTileState extends State<_SwipeDeleteTile> {
  final ValueNotifier<double> _swipeProgress = ValueNotifier(0);

  @override
  void dispose() {
    _swipeProgress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('swipe-delete-${widget.key}'),
      direction: DismissDirection.endToStart,
      onUpdate: (details) => _swipeProgress.value = details.progress,
      onDismissed: (_) => widget.onDismissed(),
      background: LayoutBuilder(
        builder: (context, constraints) => ValueListenableBuilder<double>(
          valueListenable: _swipeProgress,
          builder: (context, progress, _) {
            final width = constraints.maxWidth * progress;
            return Align(
              alignment: Alignment.centerRight,
              child: Container(
                width: width,
                margin: const EdgeInsets.only(bottom: 10),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: const Color(0xFFAB5463),
                  borderRadius: BorderRadius.circular(24),
                ),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 24),
                child: width >= 56
                    ? const Icon(
                        Icons.delete_rounded,
                        color: Color(0xFF29141A),
                        size: 24,
                      )
                    : null,
              ),
            );
          },
        ),
      ),
      child: widget.child,
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  final Animation<double> animation;
  final double width;
  final double height;
  final double radius;
  final Widget? child;

  const _ShimmerBox({
    required this.animation,
    required this.width,
    required this.height,
    required this.radius,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final progress = animation.value;
        return Container(
          width: width,
          height: height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.homeCard,
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (child != null) ...[child!],
              FractionallySizedBox(
                widthFactor: 0.52,
                alignment: Alignment(-1.8 + progress * 3.6, 0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        AppColors.homeBorder.withValues(alpha: 0.18),
                        AppColors.homeMuted.withValues(alpha: 0.24),
                        AppColors.homeBorder.withValues(alpha: 0.18),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  final Animation<double> animation;
  final double width;
  final double height;

  const _SkeletonLine({
    required this.animation,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return _ShimmerBox(
      animation: animation,
      width: width,
      height: height,
      radius: height / 2,
    );
  }
}
