import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'tasks_screen.dart';

class DayTasksScreen extends StatelessWidget {
  final String date;
  final String dateLabel;

  const DayTasksScreen({
    super.key,
    required this.date,
    required this.dateLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
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
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: AppColors.muted,
                    size: 20,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateLabel,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.cardMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tasks',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: TasksScreen(date: date)),
          ],
        ),
      ),
    );
  }
}
