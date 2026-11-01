import 'package:flutter/material.dart';

class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1512),
                borderRadius: BorderRadius.circular(32),
              ),
              child: const Icon(
                Icons.check_circle_outline,
                color: Color(0xFFC8B89A),
                size: 28,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Tasks',
              style: TextStyle(
                fontFamily: 'DMSerifDisplay',
                fontSize: 24,
                color: Color(0xFFE8DFD0),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Tasks extracted from your conversations will appear here.',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: Color(0xFF6B6460),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}