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
import 'activity_screen.dart';
import 'calendar_screen.dart';
import 'tasks_screen.dart';
import 'recap_screen.dart';
import 'day_conversations_screen.dart';

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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _skeletonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService.getDigests(),
        // all recordings, newest first — grouped by day in the list
        ApiService.getTranscripts(),
      ]);
      if (!mounted) return;
      setState(() {
        _digests = results[0] as List<Digest>;
        _transcripts = results[1] as List<Transcript>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
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
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RecapScreen(date: key)),
    );
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
                    builder: (_) => RecordingScreen(onUploadFinished: _loadData),
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
                children: const [
                  Icon(Icons.hub_outlined, color: AppColors.homeInk, size: 14),
                  SizedBox(width: 6),
                  Text(
                    'Connect',
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
            Icons.notifications_none,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ActivityScreen()),
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

  Widget _topIcon(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: AppColors.homeCard,
          borderRadius: BorderRadius.circular(19),
        ),
        child: Icon(
          icon,
          color: AppColors.homeInk,
          size: 21,
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
          _buildDailyRecapsSection(),
          const SizedBox(height: 28),
          _buildTodaySection(),
        ],
      ),
    );
  }

  Widget _buildDailyRecapsSection() {
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
              onTap: () {},
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
        _loading
            ? _buildRecapSkeleton()
            : _digests.isEmpty
            ? _emptyRecapCard()
            : SizedBox(
                height: 132,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _digests.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (context, i) {
                    final d = _digests[i];
                    return DigestCard(
                      digest: d,
                      onTap: () => _showRecapSummaryFor(d.date),
                    );
                  },
                ),
              ),
      ],
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
        _loading
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
            : Column(children: _buildGroupedTranscriptTiles()),
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
                  _SkeletonLine(animation: _skeletonController, width: 108, height: 15),
                  const SizedBox(height: 14),
                  _SkeletonLine(animation: _skeletonController, width: 180, height: 18),
                  const SizedBox(height: 12),
                  _SkeletonLine(animation: _skeletonController, width: 204, height: 15),
                  const SizedBox(height: 8),
                  _SkeletonLine(animation: _skeletonController, width: 162, height: 15),
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
        TranscriptTile(
          transcript: t,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TranscriptScreen(transcript: t),
            ),
          ).then((result) {
            // data may have changed (renamed / deleted / starred)
            if (result != null) _loadData();
          }),
        ),
      );
    }
    return tiles;
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
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
              if (child != null) child!,
              FractionallySizedBox(
                widthFactor: 0.52,
                alignment: Alignment(-1.8 + progress * 3.6, 0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        AppColors.homeBorder.withOpacity(0.18),
                        AppColors.homeMuted.withOpacity(0.24),
                        AppColors.homeBorder.withOpacity(0.18),
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
