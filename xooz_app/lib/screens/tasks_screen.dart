import '../theme/app_theme.dart';
import 'package:flutter/material.dart';
import '../models/task.dart';
import '../services/api_service.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  List<Task> _tasks = [];
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final tasks = await ApiService.getTasks();
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<void> _toggleTask(Task task) async {
    final newStatus = task.isDone ? 'open' : 'done';
    // optimistic update
    setState(() => _tasks = [
          for (final t in _tasks)
            if (t.id == task.id) t.copyWith(status: newStatus) else t
        ]);
    try {
      await ApiService.updateTaskStatus(task.id, newStatus);
    } catch (e) {
      // revert on failure
      if (!mounted) return;
      setState(() => _tasks = [
            for (final t in _tasks)
              if (t.id == task.id) t.copyWith(status: task.status) else t
          ]);
    }
  }

  List<Task> get _open =>
      _tasks.where((t) => !t.isDone).toList();
  List<Task> get _done => _tasks.where((t) => t.isDone).toList();

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadTasks,
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      child: _buildTasksView(),
    );
  }

  Widget _buildTasksView() {
    if (_error) {
      return ListView(
        children: const [
          SizedBox(height: 80),
          Center(
            child: Text(
              'Couldn\'t load tasks.\nCheck that the server is running.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.muted),
            ),
          ),
        ],
      );
    }

    if (_tasks.isEmpty) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 40),
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: const Border.fromBorderSide(
                      BorderSide(color: AppColors.homeBorder),
                    ),
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: const Icon(
                    Icons.check_circle_outline,
                    color: AppColors.accent,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Tasks',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Tasks extracted from your conversations will appear here.',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    color: AppColors.muted,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      children: [
        if (_open.isNotEmpty) ...[
          const SizedBox(height: 12),
          _sectionLabel('Open'),
          ..._open.map(_buildTaskTile),
        ],
        if (_done.isNotEmpty) ...[
          const SizedBox(height: 20),
          _sectionLabel('Done'),
          ..._done.map(_buildTaskTile),
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _sectionLabel(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.cardMuted,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildTaskTile(Task task) {
    return GestureDetector(
      onTap: () => _toggleTask(task),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: const Border.fromBorderSide(
            BorderSide(color: AppColors.homeBorder),
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Icon(
              task.isDone
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              color: task.isDone ? AppColors.accent : AppColors.muted,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                task.title,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: task.isDone ? AppColors.muted : AppColors.ink,
                  decoration: task.isDone ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (!task.isDone && task.dueDate != null)
              Text(
                task.dueDate!,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: AppColors.cardMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
