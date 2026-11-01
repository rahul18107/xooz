import 'package:flutter/material.dart';
import '../models/digest.dart';

class DigestCard extends StatelessWidget {
  final Digest digest;
  final VoidCallback? onTap;

  const DigestCard({
    super.key,
    required this.digest,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 260,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1512),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.mic,
                  color: Color(0xFFC8B89A),
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  digest.dateLabel,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF6B6460),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              digest.shortSummary,
              style: const TextStyle(
                fontFamily: 'DMSerifDisplay',
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: Color(0xFFE8DFD0),
                height: 1.4,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}