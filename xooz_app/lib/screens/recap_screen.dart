import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_theme.dart';
import '../models/recap.dart';
import '../models/transcript.dart';
import '../services/api_service.dart';
import 'transcript_screen.dart';
import 'day_conversations_screen.dart';
import 'day_tasks_screen.dart';

/// Daily Recap screen — digest of one day:
/// title, quick + detailed summary, stats, and highlights.
class RecapScreen extends StatefulWidget {
  /// Server date key 'YYYY-MM-DD'; null = today.
  final String? date;

  const RecapScreen({super.key, this.date});

  @override
  State<RecapScreen> createState() => _RecapScreenState();
}

class _RecapScreenState extends State<RecapScreen> {
  Recap? _recap;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final recap = await ApiService.getRecap(date: widget.date);
      if (!mounted) return;
      setState(() {
        _recap = recap;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst(RegExp(r'^ApiException:\s*'), '');
        _loading = false;
      });
    }
  }

  void _openTranscript(RecapEntry entry) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TranscriptScreen(transcript: Transcript.fromJson(entry.raw))),
    );
  }

  void _openDayConversations() {
    final r = _recap;
    if (r == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DayConversationsScreen(date: r.date)),
    );
  }

  void _openDayTasks() {
    final r = _recap;
    if (r == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DayTasksScreen(date: r.date, dateLabel: r.dateLabel),
      ),
    );
  }

  void _shareRecap() {
    final r = _recap;
    if (r == null) return;
    final text = '${r.dateLabel} — ${r.title}\n\n${r.quickSummary}\n\n${r.detailedSummary}'.trim();
    SharePlus.instance.share(ShareParams(text: text));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
            : _error != null
            ? _buildError()
            : RefreshIndicator(
                color: AppColors.accent,
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    const SizedBox(height: 8),
                    _buildTopBar(),
                    const SizedBox(height: 24),
                    _buildDateTitle(),
                    const SizedBox(height: 22),
                    _buildSummary(),
                    const SizedBox(height: 28),
                    _buildStatsRow(),
                    const SizedBox(height: 36),
                    _buildHighlights(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.cardMuted, height: 1.5),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _load,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Text(
                'Try Again',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.background,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    Widget circle({IconData? icon, String? emoji, VoidCallback? onTap}) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: const Border.fromBorderSide(
              BorderSide(color: AppColors.homeBorder),
            ),
            borderRadius: BorderRadius.circular(21),
          ),
          child: Center(
            child: emoji != null
                ? Text(emoji, style: const TextStyle(fontSize: 18))
                : icon != null
                ? Icon(icon, color: AppColors.muted, size: 20)
                : null,
          ),
        ),
      );
    }

    return Row(
      children: [
        circle(icon: Icons.arrow_back_ios_new_rounded, onTap: () => Navigator.pop(context)),
        const Spacer(),
        circle(icon: Icons.share_outlined, onTap: _shareRecap),
        const SizedBox(width: 12),
        circle(
          icon: Icons.more_horiz,
          onTap: () {
            final text =
                '${_recap!.dateLabel} — ${_recap!.title}\n\n${_recap!.quickSummary}\n\n${_recap!.detailedSummary}'.trim();
            Clipboard.setData(ClipboardData(text: text));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Recap copied'), duration: Duration(seconds: 1)),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDateTitle() {
    final r = _recap!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          r.dateLabel,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.cardMuted,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.mic_rounded, size: 30, color: AppColors.homeInk),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                r.title,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummary() {
    final r = _recap!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (r.quickSummary.isNotEmpty)
          Text(
            r.quickSummary,
            textAlign: TextAlign.start,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              height: 1.5,
            ),
          ),
        if (r.detailedSummary.isNotEmpty && r.detailedSummary != r.quickSummary) ...[
          const SizedBox(height: 10),
          ...r.detailedSummary.split('\n\n').where((paragraph) => paragraph.trim().isNotEmpty).map(
            (paragraph) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                paragraph.trim(),
                textAlign: TextAlign.start,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  color: AppColors.ink,
                  height: 1.6,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatsRow() {
    final r = _recap!;
    Widget card({
      required IconData icon,
      String? label,
      bool hasChevron = false,
      VoidCallback? onTap,
    }) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.ink, size: 19),
              const SizedBox(width: 6),
              Text(
                label!,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              if (hasChevron) ...[
                const SizedBox(width: 2),
                const Icon(Icons.chevron_right_rounded, color: AppColors.muted, size: 18),
              ],
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: card(
            icon: Icons.chat_bubble_outline_rounded,
            label: '${r.recordingCount} ',
            hasChevron: true,
            onTap: _openDayConversations,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: card(icon: Icons.access_time_rounded, label: r.minutesLabel),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: card(
            icon: Icons.check_circle_outline_rounded,
            label: '${r.taskCount} ',
            hasChevron: true,
            onTap: _openDayTasks,
          ),
        ),
      ],
    );
  }

  Widget _sectionHeading(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 22,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
      ),
    );
  }

  Widget _buildHighlights() {
    final r = _recap!;
    if (r.recordings.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading('Highlights'),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'No recordings on this day.',
              style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.cardMuted),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeading('Highlights'),
        const SizedBox(height: 14),
        ...r.recordings.map(
          (entry) => GestureDetector(
            onTap: () => _openTranscript(entry),
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: const Border.fromBorderSide(
                  BorderSide(color: AppColors.homeBorder),
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                const Icon(Icons.mic_rounded, size: 22, color: AppColors.homeInk),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.highlightTitle,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          entry.highlightLine,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            color: AppColors.cardMuted,
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.muted, size: 20),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

}
