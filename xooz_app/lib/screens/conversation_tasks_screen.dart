import '../theme/app_theme.dart';
import 'package:flutter/material.dart';
import '../models/task.dart';
import '../models/transcript.dart';
import '../services/api_service.dart';
import 'transcript_screen.dart';
import '../widgets/swipe_delete_tile.dart';

/// All the tasks extracted from ONE conversation.
/// Each row has a toggle and a 2-line AI summary; the full conversation
/// is one tap away via the transcript screen link.
class ConversationTasksScreen extends StatefulWidget {
  final String transcriptId;
  final String? title;
  final String? focusTaskId;

  const ConversationTasksScreen({
    super.key,
    required this.transcriptId,
    this.title,
    this.focusTaskId,
  });

  @override
  State<ConversationTasksScreen> createState() =>
      _ConversationTasksScreenState();
}

class _ConversationTasksScreenState extends State<ConversationTasksScreen> {
  List<Task> _tasks = [];
  Map<String, String> _briefs = const {};
  Transcript? _transcript;
  bool _loading = true;
  bool _error = false;
  final GlobalKey _focusedTaskKey = GlobalKey();
  final Set<String> _pendingDeleteIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final all = await ApiService.getTasks();
      final tasks = all
          .where((t) => t.sourceTranscriptId == widget.transcriptId)
          .toList();
      String? briefError;
      Map<String, String> briefs = const {};
      if (tasks.isNotEmpty) {
        try {
          briefs = await ApiService.getTaskBriefs(widget.transcriptId);
        } catch (_) {
          briefError = 'x';
        }
      }
      if (!mounted) return;
      setState(() {
        _tasks = tasks.where((t) => !_pendingDeleteIds.contains(t.id)).toList();
        _briefs = briefs;
        _error = tasks.isEmpty && briefError != null;
        _loading = false;
      });
      if (widget.focusTaskId != null &&
          tasks.any((t) => t.id == widget.focusTaskId)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final target = _focusedTaskKey.currentContext;
          if (mounted && target != null) {
            Scrollable.ensureVisible(
              target,
              duration: const Duration(milliseconds: 350),
              alignment: 0.25,
            );
          }
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
    // transcript detail is only needed for the date label + link
    _loadTranscript();
  }

  Future<void> _loadTranscript() async {
    try {
      final transcript = await ApiService.getTranscript(widget.transcriptId);
      if (!mounted) return;
      setState(() => _transcript = transcript);
    } catch (_) {}
  }

  List<Task> get _open => _tasks.where((t) => !t.isDone).toList();
  List<Task> get _done => _tasks.where((t) => t.isDone).toList();

  Future<void> _toggleTask(Task task) async {
    final previous = task;
    final newStatus = task.isDone ? 'open' : 'done';
    setState(
      () => _tasks = [
        for (final t in _tasks)
          if (t.id == task.id) t.copyWith(status: newStatus) else t,
      ],
    );
    try {
      await ApiService.updateTaskStatus(task.id, newStatus);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _tasks = [
          for (final t in _tasks)
            if (t.id == task.id) t.copyWith(status: previous.status) else t,
        ],
      );
    }
  }

  Future<void> _deleteTaskWithUndo(Task task) async {
    final original = List<Task>.of(_tasks);
    _pendingDeleteIds.add(task.id);
    setState(() => _tasks.removeWhere((t) => t.id == task.id));

    var undone = false;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text(
          'Task deleted',
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
            _pendingDeleteIds.remove(task.id);
            if (mounted) setState(() => _tasks = original);
          },
        ),
      ),
    );
    await Future.delayed(const Duration(seconds: 2));
    if (undone) return;
    try {
      await ApiService.deleteTask(task.id);
      _pendingDeleteIds.remove(task.id);
    } catch (_) {
      _pendingDeleteIds.remove(task.id);
      if (!mounted) return;
      setState(() => _tasks = original);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not delete task'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              )
            : _error
            ? _buildMessage(
                "Couldn't load these tasks.\nCheck that the server is running.",
              )
            : _tasks.isEmpty
            ? Column(
                children: [
                  _buildTopBar(),
                  Expanded(
                    child: _buildMessage('No tasks from this conversation.'),
                  ),
                ],
              )
            : _buildBody(),
      ),
    );
  }

  Widget _buildMessage(String message) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          height: 1.5,
          color: AppColors.muted,
        ),
      ),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        _buildTopBar(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              _buildHeader(),
              if (_open.isEmpty && _tasks.isNotEmpty) ...[
                const SizedBox(height: 14),
                _allDoneCard(),
              ],
              if (_open.isNotEmpty) ...[
                const SizedBox(height: 14),
                _sectionLabel('Tasks'),
                ..._open.map(_buildTaskRow),
              ],
              if (_done.isNotEmpty) ...[
                const SizedBox(height: 14),
                _sectionLabel('Completed'),
                ..._done.map(_buildTaskRow),
              ],
              _buildConversationLink(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: const Border.fromBorderSide(
                  BorderSide(color: AppColors.homeBorder),
                ),
                borderRadius: BorderRadius.circular(19),
              ),
              child: const Icon(Icons.close, color: AppColors.muted, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final left = _open.length;
    final total = _tasks.length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border.fromBorderSide(
          BorderSide(color: AppColors.homeBorder),
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title ?? _transcript?.displayTitle ?? 'Conversation',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 19,
              fontWeight: FontWeight.w800,
              height: 1.3,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  color: AppColors.background,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.chat_bubble_outline,
                  color: AppColors.accent,
                  size: 13,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  left == 0
                      ? '$total task${total == 1 ? '' : 's'} — all done'
                      : '${total - left} of $total completed · $left left to complete',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    color: AppColors.cardMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _allDoneCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: const Border.fromBorderSide(
          BorderSide(color: AppColors.homeBorder),
        ),
      ),
      child: const Row(
        children: [
          Icon(Icons.celebration_outlined, color: AppColors.accent, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              "Everything from this conversation is done.",
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
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

  Widget _buildTaskRow(Task task) {
    final brief = _briefs[task.id];
    return SwipeDeleteTile(
      id: task.id,
      onDismissed: () => _deleteTaskWithUndo(task),
      child: GestureDetector(
        key: task.id == widget.focusTaskId ? _focusedTaskKey : null,
        onTap: () => _toggleTask(task),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: task.id == widget.focusTaskId
                ? AppColors.background
                : AppColors.surface,
            border: const Border.fromBorderSide(
              BorderSide(color: AppColors.homeBorder),
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  task.isDone
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: task.isDone ? AppColors.accent : AppColors.muted,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: task.isDone ? AppColors.muted : AppColors.ink,
                        decoration: task.isDone
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    if (!task.isDone && task.dueDate != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Due ${task.dueDate}',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: AppColors.cardMuted,
                        ),
                      ),
                    ],
                    if (!task.isDone &&
                        (brief == null || brief.isNotEmpty) &&
                        brief != null &&
                        brief.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        brief,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          height: 1.45,
                          color: AppColors.muted,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConversationLink() {
    if (_transcript == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TranscriptScreen(transcript: _transcript!),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: const Border.fromBorderSide(
              BorderSide(color: AppColors.homeBorder),
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.format_quote_outlined,
                color: AppColors.accent,
                size: 18,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'View the original conversation',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.cardMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
