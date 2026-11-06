import 'package:flutter/material.dart';
import '../models/transcript.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/transcript_tile.dart';
import 'transcript_screen.dart';

class DayConversationsScreen extends StatefulWidget {
  final String date; // yyyy-MM-dd

  const DayConversationsScreen({super.key, required this.date});

  @override
  State<DayConversationsScreen> createState() => _DayConversationsScreenState();
}

class _DayConversationsScreenState extends State<DayConversationsScreen> {
  List<Transcript> _transcripts = [];
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
      final transcripts = await ApiService.getTranscripts(
        date: widget.date,
        limit: 200,
      );
      if (!mounted) return;
      setState(() {
        _transcripts = transcripts;
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

  void _openTranscript(Transcript transcript) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TranscriptScreen(transcript: transcript),
      ),
    ).then((result) {
      if (result != null) _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.homeBackground,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.homeAccent,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              _topBar(),
              const SizedBox(height: 24),
              Text(
                _dateLabel(widget.date),
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.homeMuted,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Conversations',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: AppColors.homeInk,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 22),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.homeAccent),
                  ),
                )
              else if (_error != null)
                _messageCard(_error!)
              else if (_transcripts.isEmpty)
                _messageCard('No conversations recorded on this day.')
              else
                ..._transcripts.map(
                  (transcript) => TranscriptTile(
                    transcript: transcript,
                    onTap: () => _openTranscript(transcript),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.homeCard,
              border: Border.all(color: AppColors.homeBorder),
              borderRadius: BorderRadius.circular(21),
            ),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: AppColors.homeMuted,
              size: 20,
            ),
          ),
        ),
      ],
    );
  }

  Widget _messageCard(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.homeCard,
        border: Border.all(color: AppColors.homeBorder),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.homeMuted,
          height: 1.45,
        ),
      ),
    );
  }

  String _dateLabel(String date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final parsed = DateTime.tryParse(date);
    if (parsed == null) return date;
    return '${months[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
  }
}
