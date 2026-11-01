import 'package:flutter/material.dart';

class BottomBar extends StatelessWidget {
  final VoidCallback onRecordTap;
  final VoidCallback onAskAnythingTap;

  const BottomBar({
    super.key,
    required this.onRecordTap,
    required this.onAskAnythingTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A0A),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: onAskAnythingTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1512),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Text(
                  'Ask anything',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF6B6460),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: onRecordTap,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFFE8DFD0),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(
                Icons.mic,
                color: Color(0xFF0A0A0A),
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }
}