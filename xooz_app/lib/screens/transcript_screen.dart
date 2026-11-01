import 'package:flutter/material.dart';
import '../models/transcript.dart';

class TranscriptScreen extends StatelessWidget {
  final Transcript transcript;

  const TranscriptScreen({super.key, required this.transcript});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const SizedBox(height: 8),
                  _buildHeader(),
                  const SizedBox(height: 24),
                  _buildTranscriptBody(),
                ],
              ),
            ),
          ],
        ),
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
                color: const Color(0xFF1A1512),
                borderRadius: BorderRadius.circular(19),
              ),
              child: const Icon(
                Icons.arrow_back,
                color: Color(0xFF6B6460),
                size: 18,
              ),
            ),
          ),
          const Spacer(),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1512),
              borderRadius: BorderRadius.circular(19),
            ),
            child: const Icon(
              Icons.more_horiz,
              color: Color(0xFF6B6460),
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1512),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.mic,
                color: Color(0xFFC8B89A),
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transcript.timeLabel,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    color: Color(0xFF6B6460),
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Recording',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFC8B89A),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          transcript.shortText,
          style: const TextStyle(
            fontFamily: 'DMSerifDisplay',
            fontSize: 24,
            color: Color(0xFFE8DFD0),
            height: 1.3,
          ),
        ),
      ],
    );
  }

  Widget _buildTranscriptBody() {
    if (transcript.speakerLabels.isNotEmpty) {
      return _buildSpeakerView();
    }
    return _buildPlainView();
  }

  Widget _buildPlainView() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1512),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        transcript.text,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 15,
          color: Color(0xFFE8DFD0),
          height: 1.7,
        ),
      ),
    );
  }

  Widget _buildSpeakerView() {
    return Column(
      children: transcript.speakerLabels.map((utterance) {
        final isA = utterance['speaker'] == 'A';
        return Align(
          alignment: isA ? Alignment.centerLeft : Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            constraints: const BoxConstraints(maxWidth: 280),
            decoration: BoxDecoration(
              color: isA
                  ? const Color(0xFF1A1512)
                  : const Color(0xFF252018),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Speaker ${utterance['speaker']}',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFC8B89A),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  utterance['text'] ?? '',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    color: Color(0xFFE8DFD0),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}