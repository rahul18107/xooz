import '../theme/app_theme.dart';
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: onAskAnythingTap,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.homeCard,
                  foregroundColor: AppColors.homeInk,
                  side: const BorderSide(color: AppColors.homeBorder),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                ),
                child: const Text(
                  'Ask anything',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Semantics(
            label: 'Start recording',
            button: true,
            child: Tooltip(
              message: 'Start recording',
              child: InkResponse(
                onTap: onRecordTap,
                radius: 30,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: AppColors.homeInk,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.mic_none_rounded,
                    color: Colors.white,
                    size: 25,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
