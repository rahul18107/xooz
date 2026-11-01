import 'package:flutter/material.dart';
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
  List<Transcript> _transcripts = [];
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
      setState(() {
        _digest = digest;
        _loading = false;
      });
    } catch (e) {
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
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildHomeTab(),
                  const TasksScreen(),
                ],
              ),
            ),
            BottomBar(
              onRecordTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const RecordingScreen(),
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
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ConnectScreen()),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1512),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: const [
                  Icon(Icons.device_hub, color: Color(0xFF6B6460), size: 14),
                  SizedBox(width: 6),
                  Text(
                    'Connect',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      color: Color(0xFF6B6460),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          _topIcon(
            Icons.calendar_today,
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
            Icons.settings,
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
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1512),
          borderRadius: BorderRadius.circular(19),
        ),
        child: Icon(icon, color: const Color(0xFF6B6460), size: 18),
      ),
    );
  }

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _tabController.animateTo(0),
            child: Text(
              'Home',
              style: TextStyle(
                fontFamily: 'DMSerifDisplay',
                fontSize: 28,
                color: _tabController.index == 0
                    ? const Color(0xFFE8DFD0)
                    : const Color(0xFF3A3530),
              ),
            ),
          ),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: () => _tabController.animateTo(1),
            child: Text(
              'Tasks',
              style: TextStyle(
                fontFamily: 'DMSerifDisplay',
                fontSize: 28,
                color: _tabController.index == 1
                    ? const Color(0xFFE8DFD0)
                    : const Color(0xFF3A3530),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: const Color(0xFFC8B89A),
      backgroundColor: const Color(0xFF1A1512),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 20),
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
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFFE8DFD0),
              ),
            ),
            GestureDetector(
              onTap: () {},
              child: const Text(
                'View All',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: Color(0xFF6B6460),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _loading
            ? const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFFC8B89A),
                ),
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
        color: const Color(0xFF1A1512),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text(
        'No recap yet.\nRecord your first conversation.',
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          color: Color(0xFF6B6460),
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
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFFE8DFD0),
          ),
        ),
        const SizedBox(height: 14),
        _transcripts.isEmpty
            ? Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1512),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'No recordings today yet.',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    color: Color(0xFF6B6460),
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