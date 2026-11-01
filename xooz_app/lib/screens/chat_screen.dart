import 'package:flutter/material.dart';

class ChatMessage {
  final String text;
  final bool isUser;

  ChatMessage({required this.text, required this.isUser});
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
  bool _isTyping = false;

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

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    _controller.clear();

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _isTyping = true;
    });
    _scrollToBottom();

    // placeholder response for now
    await Future.delayed(const Duration(seconds: 1));
    setState(() {
      _messages.add(ChatMessage(
        text: 'This feature is coming soon. Your conversations will be searchable here.',
        isUser: false,
      ));
      _isTyping = false;
    });
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
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: _messages.isEmpty
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
                color: const Color(0xFF1A1512),
                borderRadius: BorderRadius.circular(19),
              ),
              child: const Icon(
                Icons.close,
                color: Color(0xFF6B6460),
                size: 18,
              ),
            ),
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
                color: const Color(0xFF1A1512),
                borderRadius: BorderRadius.circular(32),
              ),
              child: const Icon(
                Icons.chat_bubble_outline,
                color: Color(0xFFC8B89A),
                size: 28,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Ask anything about your day',
              style: TextStyle(
                fontFamily: 'DMSerifDisplay',
                fontSize: 22,
                color: Color(0xFFE8DFD0),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Text(
              'Search your conversations, find decisions, recall what was said.',
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

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length + (_isTyping ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length) return _buildTypingIndicator();
        return _buildMessageBubble(_messages[index]);
      },
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    return Align(
      alignment:
          message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: message.isUser
              ? const Color(0xFFE8DFD0)
              : const Color(0xFF1A1512),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            height: 1.5,
            color: message.isUser
                ? const Color(0xFF0A0A0A)
                : const Color(0xFFE8DFD0),
          ),
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
          color: const Color(0xFF1A1512),
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
                color: const Color(0xFF6B6460),
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
      color: const Color(0xFF0A0A0A),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1512),
                borderRadius: BorderRadius.circular(30),
              ),
              child: TextField(
                controller: _controller,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  color: Color(0xFFE8DFD0),
                ),
                decoration: const InputDecoration(
                  hintText: 'Ask anything',
                  hintStyle: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    color: Color(0xFF6B6460),
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
            onTap: () => _sendMessage(_controller.text),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFFE8DFD0),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(
                Icons.mic,
                color: Color(0xFF0A0A0A),
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }
}