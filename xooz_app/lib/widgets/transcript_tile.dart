import '../theme/app_theme.dart';
import 'package:flutter/material.dart';
import '../models/transcript.dart';

class TranscriptTile extends StatelessWidget {
  final Transcript transcript;
  final VoidCallback? onTap;

  const TranscriptTile({super.key, required this.transcript, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        decoration: BoxDecoration(
          color: AppColors.homeCard,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.homeBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.homeBackground,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mic_none,
                color: AppColors.homeInk,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transcript.displayTitle,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.homeInk,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    transcript.timeLabel,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.homeMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
