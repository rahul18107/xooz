import '../theme/app_theme.dart';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/chat.dart';
import '../models/transcript.dart';
import '../widgets/transcript_tile.dart';
import 'transcript_screen.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  ActivityFeed? _feed;
  bool _loading = true;
  bool _error = false;

  List get _needsAttention => _feed?.needsAttention ?? [];
  List get _today => _feed?.today ?? [];

  @override
  void initState() {
    super.initState();
    _loadActivity();
  }

  Future<void> _loadActivity() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final feed = await ApiService.getActivity();
      if (!mounted) return;
      setState(() {
        _feed = feed;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  void _openTranscript(Transcript transcript) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TranscriptScreen(transcript: transcript)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.accent),
                    )
                  : _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_error) {
      return RefreshIndicator(
        onRefresh: _loadActivity,
        color: AppColors.accent,
        child: ListView(
          children: const [
            SizedBox(height: 80),
            Center(
              child: Text(
                'Couldn\'t load activity.\nCheck that the server is running.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.muted),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadActivity,
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          _buildSection(
            title: 'Needs Attention',
            items: _needsAttention,
            emptyMessage: 'Nothing needs attention',
          ),
          const SizedBox(height: 24),
          _buildSection(
            title: 'Today',
            items: _today,
            emptyMessage: 'No recordings today yet',
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: const Border.fromBorderSide(
                  BorderSide(color: AppColors.homeBorder),
                ),
                borderRadius: BorderRadius.circular(19),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: AppColors.muted,
                size: 18,
              ),
            ),
          ),
          const Spacer(),
          const Text(
            'Activity',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const Spacer(),
          const SizedBox(width: 38),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List items,
    required String emptyMessage,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.cardMuted,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        items.isEmpty
            ? Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: const Border.fromBorderSide(
                    BorderSide(color: AppColors.homeBorder),
                  ),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Text(
                  emptyMessage,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    color: AppColors.cardMuted,
                  ),
                ),
              )
            : Column(
                children: items
                    .map((t) => TranscriptTile(
                          transcript: t,
                          onTap: () => _openTranscript(t),
                        ))
                    .toList(),
              ),
      ],
    );
  }
}
