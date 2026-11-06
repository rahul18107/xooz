import '../theme/app_theme.dart';
import 'package:flutter/material.dart';
import '../models/digest.dart';

class DigestCard extends StatelessWidget {
  final Digest digest;
  final VoidCallback? onTap;

  const DigestCard({super.key, required this.digest, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 246,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.homeCard,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.homeBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              child: Row(
                children: [
                  const Icon(
                    Icons.mic_none_rounded,
                    color: AppColors.homeAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    digest.dateLabel,
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
            const SizedBox(height: 5),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    digest.shortSummary,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.homeInk,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
