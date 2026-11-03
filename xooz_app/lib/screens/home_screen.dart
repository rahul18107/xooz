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
import 'activity_screen.dart';
import 'calendar_screen.dart';
import 'tasks_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Digest? _digest;
  final List<Transcript> _transcripts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final digest = await ApiService.getDigest();
      if (!mounted) return;
      setState(() {
        _digest = digest;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
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
                  MaterialPageRoute(builder: (_) => const RecordingScreen()),
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
            () => showModalBottomSheet(
              context: context,
              backgroundColor: Colors.transparent,
              isScrollControlled: true,
              builder: (_) => const CalendarScreen(),
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
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.homeAccent),
              )
            : _digest == null
            ? _emptyRecapCard()
            : DigestCard(digest: _digest!),
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
          'Today',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppColors.homeInk,
          ),
        ),
        const SizedBox(height: 14),
        _transcripts.isEmpty
            ? Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.homeCard,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Text(
                  'No recordings today yet.',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.homeMuted,
                  ),
                ),
              )
            : Column(
                children: _transcripts
                    .map((t) => TranscriptTile(transcript: t))
                    .toList(),
              ),
      ],
    );
  }
}
