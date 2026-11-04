import '../theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import '../services/api_service.dart';
import '../models/transcript.dart';
import '../models/task.dart';
import '../models/digest.dart';
import '../models/chat.dart';
import '../widgets/transcript_tile.dart';
import 'transcript_screen.dart';

class SearchCategory {
  final String title;
  final IconData icon;
  final Color iconColor;

  SearchCategory({
    required this.title,
    required this.icon,
    required this.iconColor,
  });
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  Map<String, int> _counts = {};
  SearchResults? _results;
  bool _searching = false;

  final List<SearchCategory> _categories = [
    SearchCategory(title: 'Starred', icon: Icons.star_outline, iconColor: AppColors.ink),
    SearchCategory(title: 'Work', icon: Icons.work_outline, iconColor: AppColors.accent),
    SearchCategory(title: 'Personal', icon: Icons.favorite_outline, iconColor: AppColors.ink),
    SearchCategory(title: 'Social', icon: Icons.group_outlined, iconColor: AppColors.accent),
    SearchCategory(title: 'Recaps', icon: Icons.calendar_today_outlined, iconColor: AppColors.ink),
    SearchCategory(title: 'Memories', icon: Icons.psychology_outlined, iconColor: AppColors.accent),
    SearchCategory(title: 'People', icon: Icons.people_outline, iconColor: AppColors.ink),
    SearchCategory(title: 'Places', icon: Icons.place_outlined, iconColor: AppColors.accent),
  ];

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    final counts = await ApiService.getCategoryCounts();
    if (!mounted) return;
    setState(() => _counts = counts);
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _results = null;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 500), () => _runSearch(value.trim()));
  }

  Future<void> _runSearch(String query) async {
    try {
      final results = await ApiService.search(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _results = SearchResults(transcripts: [], digests: [], tasks: []);
        _searching = false;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSearching = _controller.text.isNotEmpty;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchBar(context),
            Expanded(
              child: isSearching
                  ? _buildSearchResults()
                  : _buildCategoryGrid(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: const Border.fromBorderSide(
                  BorderSide(color: AppColors.homeBorder),
                ),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: AppColors.muted, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      onChanged: _onSearchChanged,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        color: AppColors.ink,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Search',
                        hintStyle: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          color: AppColors.muted,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () {
              _debounce?.cancel();
              Navigator.pop(context);
            },
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                color: AppColors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryGrid() {
    int countFor(SearchCategory cat) => _counts[cat.title] ?? 0;

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.2,
      ),
      itemCount: _categories.length,
      itemBuilder: (context, index) {
        final category = _categories[index];
        return _buildCategoryCard(category, countFor(category));
      },
    );
  }

  Widget _buildCategoryCard(SearchCategory category, int count) {
    return GestureDetector(
      onTap: () {
        _controller.text = category.title;
        _onSearchChanged(category.title);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: const Border.fromBorderSide(
            BorderSide(color: AppColors.homeBorder),
          ),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(category.icon, color: AppColors.ink, size: 22),
                Text(
                  count.toString(),
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              category.title,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: AppColors.cardMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_searching && _results == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }

    final results = _results;
    if (results == null) {
      return const Center(
        child: Text(
          'Type to search your conversations',
          style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.muted),
        ),
      );
    }

    if (results.isEmpty) {
      return const Center(
        child: Text(
          'No results found',
          style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.muted),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (results.transcripts.isNotEmpty) ...[
          _resultSection('Conversations', results.transcripts.length),
          ...results.transcripts.map((t) => TranscriptTile(
                transcript: t as Transcript,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TranscriptScreen(transcript: t),
                  ),
                ),
              )),
        ],
        if (results.tasks.isNotEmpty) ...[
          _resultSection('Tasks', results.tasks.length),
          ...results.tasks.map((task) => _resultTile(
                icon: Icons.check_circle_outline,
                title: (task as Task).title,
                subtitle: task.statusLabel,
              )),
        ],
        if (results.digests.isNotEmpty) ...[
          _resultSection('Recaps', results.digests.length),
          ...results.digests.map((d) => _resultTile(
                icon: Icons.calendar_today_outlined,
                title: (d as Digest).shortSummary,
                subtitle: d.dateLabel,
              )),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _resultSection(String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 0, 12),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.cardMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            count.toString(),
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border.fromBorderSide(
          BorderSide(color: AppColors.homeBorder),
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.accent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: AppColors.cardMuted,
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
