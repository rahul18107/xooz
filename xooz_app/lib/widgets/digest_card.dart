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
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: Text(
                digest.shortSummary,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppColors.homeInk,
                  height: 1.4,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(
              width: double.infinity,
              height: 66,
              child: ExcludeSemantics(
                child: CustomPaint(painter: _RecapMapPainter()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Decorative map artwork, independent of the user's location.
class _RecapMapPainter extends CustomPainter {
  const _RecapMapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFE8EAE3),
    );
    final street = Paint()
      ..color = const Color(0xFFF9FAF6)
      ..strokeWidth = 1;
    for (var i = -2; i < 12; i++) {
      canvas.drawLine(
        Offset(i * 27.0, 0),
        Offset(i * 27.0 - 16, size.height),
        street,
      );
      canvas.drawLine(
        Offset(0, i * 17.0),
        Offset(size.width, i * 17.0 + 25),
        street,
      );
    }
    final road = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = 5;
    canvas.drawLine(
      Offset(size.width * .12, size.height),
      Offset(size.width * .63, 0),
      road,
    );
    canvas.drawLine(
      Offset(size.width * .77, size.height),
      Offset(size.width * .83, 0),
      road,
    );
    final center = Offset(size.width * .53, size.height * .46);
    canvas.drawCircle(center, 25, Paint()..color = const Color(0x22807870));
    canvas.drawCircle(center, 8, Paint()..color = AppColors.homeCard);
    canvas.drawCircle(center, 5, Paint()..color = AppColors.homeAccent);
  }

  @override
  bool shouldRepaint(covariant _RecapMapPainter oldDelegate) => false;
}
