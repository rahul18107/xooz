import '../theme/app_theme.dart';
import 'dart:math';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/chat.dart';
import 'recording_screen.dart';
import 'transcript_screen.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final List<String> sourceIds;

  const ChatMessage({required this.text, required this.isUser, this.sourceIds = const []});
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  final Set<int> _expandedSources = {};
  final Map<String, String> _sourceTitles = {};
  final Set<String> _loadingSourceIds = {};
  bool _isTyping = false;
  bool _hasText = false;
  String? _failedMessage;
  String? _failedRequestId;
  String _sessionId = ApiService.chatSessionId;
  bool _loadingHistory = true;
  bool _startingNewChat = false;
  int _historyEpoch = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) setState(() => _hasText = hasText);
    });
    _loadHistory();
  }

  /// Restores previous messages from the server so chats survive
  /// leaving and re-opening the screen.
  Future<void> _loadHistory() async {
    final epoch = _historyEpoch;
    try {
      final threads = await ApiService.getChatThreads();
      if (!mounted || epoch != _historyEpoch) return;
      await _openThread(threads.isEmpty ? _newSessionId() : threads.first.sessionId);
    } catch (_) {
      if (mounted && epoch == _historyEpoch) await _openThread(ApiService.chatSessionId);
    }
  }

  String _newSessionId() =>
      '${ApiService.chatSessionId}-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

  Future<void> _openThread(String sessionId) async {
    final epoch = ++_historyEpoch;
    setState(() {
      _sessionId = sessionId;
      _messages.clear();
      _expandedSources.clear();
      _failedMessage = null;
      _failedRequestId = null;
      _controller.clear();
      _loadingHistory = true;
    });
    try {
      final history = await ApiService.loadChatHistory(sessionId: sessionId);
      if (!mounted || epoch != _historyEpoch) return;
      setState(() {
        _messages.addAll([
          for (final m in history)
            ChatMessage(text: m.text, isUser: m.isUser, sourceIds: m.sourceIds),
        ]);
      });
      _scrollToBottom();
    } catch (_) {
      if (mounted && epoch == _historyEpoch) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load this chat.')),
        );
      }
    } finally {
      if (mounted && epoch == _historyEpoch) setState(() => _loadingHistory = false);
    }
  }

  Future<bool> _startNewChat() async {
    if (_isTyping || _startingNewChat) return false;
    setState(() => _startingNewChat = true);
    try {
      final thread = await ApiService.createChatThread();
      if (!mounted) return false;
      ++_historyEpoch;
      setState(() {
        _sessionId = thread.sessionId;
        _messages.clear();
        _expandedSources.clear();
        _failedMessage = null;
        _failedRequestId = null;
        _controller.clear();
        _loadingHistory = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('New chat started'),
        duration: Duration(seconds: 2),
      ));
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not start a new chat.'),
        ));
      }
      return false;
    } finally {
      if (mounted) setState(() => _startingNewChat = false);
    }
  }

  Future<void> _showThreads() async {
    if (_isTyping) return;
    var threadsFuture = ApiService.getChatThreads();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, refreshSheet) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.7,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
                  child: Row(children: [
                    const Expanded(child: Text('Chats', style: TextStyle(
                      fontFamily: 'Inter', fontSize: 20, fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ))),
                  ]),
                ),
                ListTile(
                  leading: const Icon(Icons.add_rounded, color: AppColors.ink),
                  title: const Text('New chat', style: TextStyle(
                    fontFamily: 'Inter', fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  )),
                  onTap: () async {
                    if (await _startNewChat() && sheetContext.mounted) {
                      Navigator.pop(sheetContext);
                    }
                  },
                ),
                Expanded(
                  child: FutureBuilder<List<ChatThread>>(
                    future: threadsFuture,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        if (snapshot.hasError) {
                          final error = snapshot.error;
                          final setupNeeded = error is ApiException &&
                              (error.statusCode == 404 || error.statusCode == 500);
                          return Column(children: [
                            ListTile(
                              leading: const Icon(Icons.chat_bubble_outline,
                                color: AppColors.ink),
                              title: const Text('Current chat', style: TextStyle(
                                fontFamily: 'Inter', color: AppColors.ink,
                              )),
                              onTap: () => Navigator.pop(sheetContext),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                              child: Text(
                                setupNeeded
                                    ? 'Past chats need the updated server and migration 017.'
                                    : 'Past chats could not be loaded.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontFamily: 'Inter',
                                  color: AppColors.muted),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => refreshSheet(() {
                                threadsFuture = ApiService.getChatThreads();
                              }),
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Try again'),
                            ),
                          ]);
                        }
                        return const Center(child: CircularProgressIndicator(color: AppColors.ink));
                      }
                      final threads = snapshot.data!;
                      if (threads.isEmpty) {
                        return Column(children: [
                          ListTile(
                            leading: const Icon(Icons.chat_bubble_outline,
                              color: AppColors.ink),
                            title: const Text('Current chat', style: TextStyle(
                              fontFamily: 'Inter', color: AppColors.ink,
                            )),
                            selected: true,
                            onTap: () => Navigator.pop(sheetContext),
                          ),
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('No past chats yet.', style: TextStyle(
                              fontFamily: 'Inter', color: AppColors.muted,
                            )),
                          ),
                        ]);
                      }
                      final currentListed = threads.any(
                        (thread) => thread.sessionId == _sessionId);
                      return ListView.builder(
                        itemCount: threads.length + (currentListed ? 0 : 1),
                        itemBuilder: (context, index) {
                          if (!currentListed && index == 0) {
                            return ListTile(
                              leading: const Icon(Icons.chat_bubble_outline,
                                color: AppColors.ink),
                              title: const Text('Current chat', style: TextStyle(
                                fontFamily: 'Inter', color: AppColors.ink,
                              )),
                              selected: true,
                              onTap: () => Navigator.pop(sheetContext),
                            );
                          }
                          final thread = threads[index - (currentListed ? 0 : 1)];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                            title: Text(thread.title, maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontFamily: 'Inter', color: AppColors.ink)),
                            subtitle: Text('${thread.updatedAt.day}/${thread.updatedAt.month}/${thread.updatedAt.year}',
                              style: const TextStyle(fontFamily: 'Inter', color: AppColors.muted)),
                            selected: thread.sessionId == _sessionId,
                            onTap: () {
                              Navigator.pop(sheetContext);
                              if (thread.sessionId != _sessionId) _openThread(thread.sessionId);
                            },
                            trailing: IconButton(
                              tooltip: 'Delete chat',
                              icon: const Icon(Icons.delete_outline, color: AppColors.muted),
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: sheetContext,
                                  builder: (dialogContext) => AlertDialog(
                                    backgroundColor: AppColors.surface,
                                    title: const Text('Delete chat?'),
                                    content: const Text('This chat and its messages will be removed.'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(dialogContext, false),
                                        child: const Text('Cancel')),
                                      TextButton(onPressed: () => Navigator.pop(dialogContext, true),
                                        child: const Text('Delete')),
                                    ],
                                  ),
                                );
                                if (confirmed != true || !sheetContext.mounted) return;
                                try {
                                  await ApiService.deleteChatThread(thread.sessionId);
                                  if (!sheetContext.mounted) return;
                                  if (thread.sessionId == _sessionId) await _startNewChat();
                                  refreshSheet(() { threadsFuture = ApiService.getChatThreads(); });
                                } catch (_) {
                                  if (!sheetContext.mounted) return;
                                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                                    const SnackBar(content: Text('Could not delete chat.')),
                                  );
                                }
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _openSource(String id) async {
    try {
      final transcript = await ApiService.getTranscript(id);
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => TranscriptScreen(transcript: transcript),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this recording.')),
      );
    }
  }

  Future<void> _loadSourceTitles(List<String> ids) async {
    final pending = ids.where((id) => !_sourceTitles.containsKey(id) && _loadingSourceIds.add(id)).toList();
    if (pending.isEmpty) return;
    await Future.wait(pending.map((id) async {
      String title;
      try {
        title = (await ApiService.getTranscript(id)).displayTitle;
      } catch (_) {
        title = 'Unavailable conversation';
      }
      if (!mounted) return;
      setState(() {
        _sourceTitles[id] = title;
        _loadingSourceIds.remove(id);
      });
    }));
  }

  String _displayAnswer(String text) => text
      .replaceAll(RegExp(r'[ \t]*\[(?:recording|task)(?:\s+\d+)?\]', caseSensitive: false), ' ')
      .replaceAll(RegExp(r' {2,}'), ' ')
      .trim();

  Future<void> _sendMessage(String text) async {
    final message = text.trim();
    if (message.isEmpty || _isTyping || _loadingHistory) return;
    final requestId = message == _failedMessage && _failedRequestId != null
        ? _failedRequestId!
        : '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    _controller.clear();

    setState(() {
      _messages.add(ChatMessage(text: message, isUser: true));
      _isTyping = true;
    });
    _scrollToBottom();

    try {
      final reply = await ApiService.sendChat(
        message,
        sessionId: _sessionId,
        requestId: requestId,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage(text: reply.reply, isUser: false, sourceIds: reply.sourceIds));
        _isTyping = false;
        _failedMessage = null;
        _failedRequestId = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.removeLast();
        _controller.text = message;
        _failedMessage = message;
        _failedRequestId = requestId;
        _isTyping = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message not sent. Try again.')),
      );
    }
    _scrollToBottom();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: _loadingHistory
                  ? const Center(child: CircularProgressIndicator(color: AppColors.ink))
                  : _messages.isEmpty
                  ? _buildEmptyState()
                  : _buildMessageList(),
            ),
            _buildInputBar(),
          ],
        ),
      ),
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
          const Spacer(),
          IconButton(
            tooltip: 'Past chats',
            onPressed: _isTyping ? null : _showThreads,
            icon: const Icon(Icons.history_rounded, color: AppColors.ink),
          ),
          IconButton(
            tooltip: 'New chat',
            onPressed: _isTyping || _startingNewChat ? null : () => _startNewChat(),
            icon: const Icon(Icons.add_rounded, color: AppColors.ink),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
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
                color: AppColors.surface,
                border: const Border.fromBorderSide(
                  BorderSide(color: AppColors.homeBorder),
                ),
                borderRadius: BorderRadius.circular(32),
              ),
              child: const Icon(
                Icons.chat_bubble_outline,
                color: AppColors.accent,
                size: 28,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Ask anything about your day',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Text(
              'Search your conversations, find decisions, recall what was said.',
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
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length + (_isTyping ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length) return _buildTypingIndicator();
        return _buildMessageBubble(_messages[index], index);
      },
    );
  }

  Widget _buildMessageBubble(ChatMessage message, int index) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: message.isUser ? AppColors.ink : AppColors.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.isUser ? message.text : _displayAnswer(message.text),
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                height: 1.5,
                color: message.isUser ? AppColors.background : AppColors.ink,
              ),
            ),
            if (message.sourceIds.isNotEmpty) ...[
              const SizedBox(height: 10),
              TextButton(
                onPressed: () {
                  setState(() {
                    if (!_expandedSources.add(index)) _expandedSources.remove(index);
                  });
                  if (_expandedSources.contains(index)) _loadSourceTitles(message.sourceIds);
                },
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.muted,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 36),
                  alignment: Alignment.centerLeft,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Sources', style: TextStyle(fontFamily: 'Inter', fontSize: 12)),
                    const SizedBox(width: 4),
                    Icon(_expandedSources.contains(index) ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, size: 20),
                  ],
                ),
              ),
              if (_expandedSources.contains(index))
                Wrap(
                  spacing: 8,
                  children: [
                    for (var i = 0; i < message.sourceIds.length; i++)
                      TextButton.icon(
                        onPressed: () => _openSource(message.sourceIds[i]),
                        icon: const Icon(Icons.article_outlined, size: 15),
                        label: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.5),
                          child: Text(
                            _sourceTitles[message.sourceIds[i]] ?? 'Loading...',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: const Border.fromBorderSide(
            BorderSide(color: AppColors.homeBorder),
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            return AnimatedContainer(
              duration: Duration(milliseconds: 400 + (i * 100)),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: AppColors.muted,
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      color: AppColors.background,
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: const Border.fromBorderSide(
                  BorderSide(color: AppColors.homeBorder),
                ),
                borderRadius: BorderRadius.circular(30),
              ),
              child: TextField(
                controller: _controller,
                keyboardType: TextInputType.multiline,
                minLines: 1,
                maxLines: 5,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  color: AppColors.ink,
                ),
                decoration: const InputDecoration(
                  hintText: 'Ask anything',
                  hintStyle: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    color: AppColors.muted,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
                onSubmitted: _sendMessage,
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _hasText
                ? () => _sendMessage(_controller.text)
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RecordingScreen()),
                    );
                  },
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Icon(
                _hasText ? Icons.arrow_upward_rounded : Icons.mic_none_rounded,
                color: AppColors.background,
                size: _hasText ? 26 : 24,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
