import '../theme/app_theme.dart';
import 'package:flutter/material.dart';
import '../models/task.dart';
import '../models/transcript.dart';
import '../services/api_service.dart';
import 'conversation_tasks_screen.dart';
import '../widgets/swipe_delete_tile.dart';

class TasksScreen extends StatefulWidget {
  final String? date;
  final String? title;

  const TasksScreen({super.key, this.date, this.title});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  List<Task> _tasks = [];
  Map<String, Transcript> _conversations = const {};
  bool _loading = true;
  bool _error = false;
  final Set<String> _pendingDeleteIds = {};

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
      final tasks = await ApiService.getTasks(date: widget.date);
      Map<String, Transcript> conversations = const {};
      try {
        final transcripts = await ApiService.getTranscripts(limit: 200);
        conversations = {for (final t in transcripts) t.id: t};
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _tasks = tasks.where((t) => !_pendingDeleteIds.contains(t.id)).toList();
        _conversations = conversations;
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

  /// Refreshes the list after coming back from the detail screen,
  /// without flashing the full-screen loader.
  Future<void> _refreshQuiet() async {
    try {
      final tasks = await ApiService.getTasks(date: widget.date);
      if (!mounted) return;
      setState(
        () => _tasks = tasks
            .where((t) => !_pendingDeleteIds.contains(t.id))
            .toList(),
      );
    } catch (_) {}
  }

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
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: AppColors.muted,
              ),
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
                Text(
                  widget.title ?? 'Tasks',
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
        if (widget.title != null) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 14),
            child: Text(
              widget.title!,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
        ..._buildClusters(_tasks),
        const SizedBox(height: 32),
      ],
    );
  }

  Future<void> _openCluster(String? transcriptId, List<Task> tasks) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConversationTasksScreen(
          transcriptId: transcriptId ?? '',
          title: _conversationTitle(transcriptId),
        ),
      ),
    );
    // statuses may have changed inside the cluster — refresh quietly,
    // but only check again if some tasks were left open
    _refreshQuiet();
  }

  Future<void> _deleteClusterWithUndo(List<Task> tasks) async {
    final ids = tasks.map((t) => t.id).toSet();
    final original = List<Task>.of(_tasks);
    _pendingDeleteIds.addAll(ids);
    setState(() => _tasks.removeWhere((t) => ids.contains(t.id)));

    var undone = false;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text(
          'Tasks deleted',
          style: TextStyle(color: AppColors.ink),
        ),
        backgroundColor: AppColors.homeCard,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        persist: false,
        action: SnackBarAction(
          label: 'Undo',
          textColor: Colors.black,
          onPressed: () {
            undone = true;
            _pendingDeleteIds.removeAll(ids);
            if (mounted) setState(() => _tasks = original);
          },
        ),
      ),
    );
    await Future.delayed(const Duration(seconds: 2));
    if (undone) return;
    try {
      for (final id in ids) {
        await ApiService.deleteTask(id);
      }
      _pendingDeleteIds.removeAll(ids);
      if (mounted) await _refreshQuiet();
    } catch (_) {
      _pendingDeleteIds.removeAll(ids);
      if (!mounted) return;
      await _refreshQuiet();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not delete all tasks'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  List<Widget> _buildClusters(List<Task> tasks) {
    final groups = <String?, List<Task>>{};
    for (final task in tasks) {
      groups.putIfAbsent(task.sourceTranscriptId, () => []).add(task);
    }

    return [
      for (final entry in groups.entries)
        SwipeDeleteTile(
          id: entry.key ?? 'unlinked',
          onDismissed: () => _deleteClusterWithUndo(entry.value),
          child: GestureDetector(
            onTap: () => _openCluster(entry.key, entry.value),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: const Border.fromBorderSide(
                  BorderSide(color: AppColors.homeBorder),
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: AppColors.background,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.chat_bubble_outline,
                      color: AppColors.accent,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _conversationTitle(entry.key),
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _clusterSubtitle(entry.value),
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12.5,
                            color: AppColors.cardMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right,
                    color: AppColors.cardMuted,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
    ];
  }

  String _clusterSubtitle(List<Task> tasks) {
    final left = tasks.where((t) => !t.isDone).length;
    final total = tasks.length;
    if (left == 0) {
      return 'All $total task${total == 1 ? '' : 's'} done';
    }
    if (left == total) {
      return '$total task${total == 1 ? '' : 's'} to complete';
    }
    return '$left of $total left to complete';
  }

  String _conversationTitle(String? transcriptId) {
    if (transcriptId == null) return 'Tasks';
    return _conversations[transcriptId]?.displayTitle ?? 'Conversation';
  }
}
