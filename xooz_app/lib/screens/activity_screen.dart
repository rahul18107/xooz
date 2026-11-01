import 'package:flutter/material.dart';
import '../models/transcript.dart';
import '../widgets/transcript_tile.dart';

class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});

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
                  _buildSection(
                    title: 'Needs Attention',
                    items: [],
                    emptyMessage: 'Nothing needs attention',
                  ),
                  const SizedBox(height: 24),
                  _buildSection(
                    title: 'Today',
                    items: [],
                    emptyMessage: 'No recordings today yet',
                  ),
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
          const Text(
            'Activity',
            style: TextStyle(
              fontFamily: 'DMSerifDisplay',
              fontSize: 22,
              color: Color(0xFFE8DFD0),
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
    required List<Transcript> items,
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
            color: Color(0xFF6B6460),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        items.isEmpty
            ? Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1512),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  emptyMessage,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    color: Color(0xFF6B6460),
                  ),
                ),
              )
            : Column(
                children: items
                    .map((t) => TranscriptTile(transcript: t))
                    .toList(),
              ),
      ],
    );
  }
}