import '../theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../models/transcript.dart';
import '../services/api_service.dart';
import '../widgets/audio_player_bar.dart';
import '../services/audio_export.dart';
import 'chat_screen.dart';

class TranscriptScreen extends StatefulWidget {
  final Transcript transcript;

  const TranscriptScreen({super.key, required this.transcript});

  @override
  State<TranscriptScreen> createState() => _TranscriptScreenState();
}

class _TranscriptScreenState extends State<TranscriptScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Transcript transcript;

  // signals the audio player to stop + rewind when its tab is hidden
  final ValueNotifier<bool> _playerVisible = ValueNotifier<bool>(false);

  bool _generating = false;
  bool _savingSpeakerName = false;
  int _summaryVersion = 0;
  String? _error;

  final GlobalKey _menuButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    transcript = widget.transcript;
    _tabController = TabController(length: 2, vsync: this);
    _loadLatestTranscript();
    // summary loads by default — no button needed
    if (!_hasSummary) _generateSummary();
  }

  @override
  void dispose() {
    _playerVisible.dispose();
    _tabController.dispose();
    super.dispose();
  }

  String get _summaryText => transcript.summary ?? '';

  bool get _hasSummary => _summaryText.trim().isNotEmpty;

  Future<void> _loadLatestTranscript() async {
    final version = _summaryVersion;
    try {
      final latest = await ApiService.getTranscript(transcript.id);
      if (mounted && version == _summaryVersion) {
        setState(() => transcript = latest);
      }
    } catch (_) {
      // Keep the transcript passed by the previous screen when offline.
    }
  }

  Future<void> _generateSummary() async {
    if (_generating || _savingSpeakerName) return;
    final version = _summaryVersion;
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final result = await ApiService.generateSummary(transcript.id);
      if (!mounted) return;
      if (version != _summaryVersion) {
        setState(() => _generating = false);
        if (!_hasSummary) _generateSummary();
        return;
      }
      setState(() {
        transcript = transcript.copyWith(title: result.title, summary: result.summary);
        _generating = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (version != _summaryVersion) {
        setState(() => _generating = false);
        if (!_hasSummary) _generateSummary();
        return;
      }
      setState(() {
        _generating = false;
        _error = e.toString().replaceFirst(RegExp(r'^ApiException:\s*'), '');
      });
    }
  }

  Future<void> _toggleStar() async {
    final newStarred = !transcript.starred;
    setState(() => transcript = transcript.copyWith(starred: newStarred));
    try {
      final updated = await ApiService.setStarred(transcript.id, newStarred);
      if (!mounted) return;
      setState(() => transcript = updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => transcript = transcript.copyWith(starred: !newStarred));
      _showSnackBar('Couldn\'t update star');
    }
  }

  Future<void> _editSpeakerName(String label) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _SpeakerNameDialog(
        label: label,
        initialName: transcript.speakerNames[label] ?? '',
      ),
    );
    if (!mounted || _savingSpeakerName || name == null || name == (transcript.speakerNames[label] ?? '')) return;
    final previous = transcript;
    final names = Map<String, String>.from(transcript.speakerNames);
    if (name.isEmpty) {
      names.remove(label);
    } else {
      names[label] = name;
    }
    setState(() {
      transcript = transcript.copyWith(speakerNames: names, clearSummary: true);
      _summaryVersion++;
      _savingSpeakerName = true;
    });
    try {
      final updated = await ApiService.setSpeakerName(transcript.id, names);
      if (!mounted) return;
      if (updated.speakerNames[label] != (name.isEmpty ? null : name)) {
        throw StateError('Server did not return the saved speaker name');
      }
      setState(() {
        transcript = updated;
        _savingSpeakerName = false;
      });
      _generateSummary();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        transcript = previous;
        _summaryVersion++;
        _savingSpeakerName = false;
      });
      final migrationMissing = error.toString().contains('speaker_names') &&
          (error.toString().contains('column') || error.toString().contains('schema'));
      _showSnackBar(migrationMissing
          ? 'Run database migration 007, then try again'
          : 'Couldn\'t update speaker name: $error');
    }
  }

  Future<void> _showActionsMenu() async {
    final button = _menuButtonKey.currentContext!.findRenderObject() as RenderBox;
    final rect =
        button.localToGlobal(Offset.zero) & button.size; // anchor at the 3-dot button

    final action = await Navigator.push<String>(
      context,
      _AnchorMenuRoute(
        anchorRect: rect,
        hasAudio: (transcript.audioUrl ?? '').isNotEmpty,
      ),
    );

    if (!mounted || action == null) return;
    switch (action) {
      case 'rename':
        _showRenameDialog();
      case 'copy-transcript':
        _copyToClipboard(transcript.text, 'Transcript copied');
      case 'copy-summary':
        _hasSummary
            ? _copyToClipboard(_summaryText, 'Summary copied')
            : _showSnackBar('No summary yet');
      case 'export-audio':
        _exportAudio();
      case 'delete':
        _confirmDelete();
    }
  }

  /// Converts the stored recording to a real .mp3 and opens the
  /// system share sheet so the user can save it anywhere (Files, WhatsApp…).
  Future<void> _exportAudio() async {
    final url = transcript.audioUrl;
    if (url == null || url.isEmpty) {
      _showSnackBar('No audio recorded');
      return;
    }

    // progress dialog — conversion takes a moment on longer recordings
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
        ),
        content: Row(
          children: [
            CircularProgressIndicator(color: AppColors.accent),
            SizedBox(width: 20),
            Expanded(
              child: Text(
                'Preparing .mp3…',
                style: TextStyle(fontFamily: 'Inter', fontSize: 15, color: AppColors.ink),
              ),
            ),
          ],
        ),
      ),
    );

    try {
      final file = await AudioExportService.exportToMp3(
        url: url,
        fileName: transcript.displayTitle,
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // close progress
      await SharePlus.instance.share(ShareParams(files: [file], text: transcript.displayTitle));
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // close progress
      _showSnackBar("Couldn't export the audio");
    }
  }

  Future<void> _showRenameDialog() async {
    final controller = TextEditingController(text: transcript.displayTitle);
    final previousTitle = transcript.title;
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Rename recording',
          style: TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w600),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          style: const TextStyle(fontFamily: 'Inter', fontSize: 15, color: AppColors.ink),
          onChanged: (v) => v.trim(),
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: AppColors.raised,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(fontFamily: 'Inter', color: AppColors.muted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text(
              'Save',
              style: TextStyle(fontFamily: 'Inter', color: AppColors.accent),
            ),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty || newName == transcript.displayTitle) return;

    setState(() => transcript = transcript.copyWith(title: newName));
    try {
      final updated = await ApiService.renameTranscript(transcript.id, newName);
      if (!mounted) return;
      setState(() => transcript = updated);
      _showSnackBar('Renamed');
    } catch (e) {
      if (!mounted) return;
      setState(() => transcript = transcript.copyWith(title: previousTitle)); // revert
      _showSnackBar('Couldn\'t rename');
    }
  }

  void _copyToClipboard(String value, String message) {
    Clipboard.setData(ClipboardData(text: value));
    _showSnackBar(message);
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Delete recording?',
          style: TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w600),
        ),
        content: const Text(
          'This will permanently delete the recording, its transcript and summary.',
          style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.cardMuted, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(fontFamily: 'Inter', color: AppColors.muted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(fontFamily: 'Inter', color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ApiService.deleteTranscript(transcript.id);
      if (!mounted) return;
      Navigator.pop(context, 'deleted');
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Couldn\'t delete');
    }
  }

  void _showSnackBar(String message, {bool light = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            color: light ? AppColors.ink : Colors.white,
          ),
        ),
        backgroundColor: light ? AppColors.surface : AppColors.ink,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      // audio bar only on the Transcript tab; chat button always available
      bottomNavigationBar: _buildBottomBar(),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const SizedBox(height: 8),
                  _buildHeader(),
                  const SizedBox(height: 20),
                  _buildTabs(),
                  const SizedBox(height: 24),
                  _tabController.index == 0
                      ? _buildSummaryTab()
                      : _buildTranscriptBody(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final showPlayer = _tabController.index == 1 && transcript.audioUrl != null;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Row(
          children: [
            Expanded(
              child: ClipRect(
                // no animation — the bar simply shows/hides per tab
                child: SizedBox(
                  height: showPlayer ? null : 0,
                  width: double.infinity,
                  child: transcript.audioUrl != null
                      ? AudioPlayerBar(
                          url: transcript.audioUrl!,
                          visible: _playerVisible,
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 14),
            _buildChatButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildChatButton() {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ChatScreen()),
        );
      },
      child: Container(
        width: 62,
        height: 62,
        decoration: const BoxDecoration(
          color: AppColors.ink,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.forum_rounded,
          color: Colors.white,
          size: 26,
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
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
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: AppColors.muted,
                size: 18,
              ),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _toggleStar,
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
              child: Icon(
                transcript.starred ? Icons.star_rounded : Icons.star_outline,
                color: transcript.starred ? AppColors.accent : AppColors.muted,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            key: _menuButtonKey,
            onTap: _showActionsMenu,
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
              child: const Icon(
                Icons.more_horiz,
                color: AppColors.muted,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final title = transcript.displayTitle;
    final isLong = title.length > 24;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: isLong ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: isLong ? 20 : 24,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.calendar_today_outlined,
                color: AppColors.muted,
                size: 14,
              ),
              const SizedBox(width: 8),
              Text(
                transcript.dateChipLabel,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabs() {
    return TabBar(
      controller: _tabController,
      onTap: (_) {
        // leaving the transcript tab stops + rewinds the player
        _playerVisible.value = _tabController.index == 1 && transcript.audioUrl != null;
        setState(() {});
      },
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
      tabAlignment: TabAlignment.start,
      isScrollable: true,
      dividerColor: Colors.transparent,
      indicatorColor: AppColors.ink,
      indicatorSize: TabBarIndicatorSize.label,
      labelPadding: const EdgeInsets.only(right: 24),
      labelColor: AppColors.ink,
      unselectedLabelColor: AppColors.muted,
      labelStyle: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      tabs: const [
        Tab(text: 'Summary'),
        Tab(text: 'Transcript'),
      ],
    );
  }

  // ---------------- Summary tab ----------------

  Widget _buildSummaryTab() {
    if (_generating || _savingSpeakerName) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          children: [
            const CircularProgressIndicator(color: AppColors.accent),
            const SizedBox(height: 16),
            Text(
              _savingSpeakerName ? 'Saving speaker name...' : 'Generating summary...',
              style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.muted),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          children: [
            Text(
              _error!,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: AppColors.cardMuted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            _buildRetryButton(),
          ],
        ),
      );
    }

    if (_hasSummary) {
      return _buildSummaryBody();
    }

    // no summary yet and nothing is loading (shouldn't happen, but safe)
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
      ),
      child: const Text(
        'No summary available yet.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          color: AppColors.muted,
        ),
      ),
    );
  }

  Widget _buildRetryButton() {
    return GestureDetector(
      onTap: _generateSummary,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.ink,
          borderRadius: BorderRadius.circular(30),
        ),
        child: const Center(
          child: Text(
            'Try Again',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.background,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryBody() {
    // Split the title line off the bullets
    final lines = _summaryText.trim().split('\n');
    String title = '';
    List<String> bullets = [];
    for (final line in lines) {
      final l = line.trim();
      if (l.isEmpty) continue;
      if (bullets.isEmpty && l.length <= 80 && !l.startsWith('-') && !l.startsWith('•')) {
        if (title.isEmpty) {
          title = l;
          continue;
        }
      }
      bullets.add(l.replaceFirst(RegExp(r'^[-•]\s*'), ''));
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.graphic_eq_rounded, color: AppColors.accent, size: 20),
              ],
            ),
            const SizedBox(height: 16),
          ],
          ...bullets.map(
            (b) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      color: AppColors.ink,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      b,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        color: AppColors.ink,
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- Transcript tab ----------------

  Widget _buildTranscriptBody() {
    if (transcript.speakerLabels.isNotEmpty) {
      return _buildSpeakerView();
    }
    return _buildPlainView();
  }

  Widget _buildPlainView() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border.fromBorderSide(
          BorderSide(color: AppColors.homeBorder),
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Text(
        transcript.text,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 15,
          color: AppColors.ink,
          height: 1.7,
        ),
      ),
    );
  }

  Widget _buildSpeakerView() {
    return Column(
      children: transcript.speakerLabels.map((utterance) {
        final isA = utterance['speaker'] == 'A';
        return Align(
          alignment: isA ? Alignment.centerLeft : Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            constraints: const BoxConstraints(maxWidth: 280),
            decoration: BoxDecoration(
              color: isA ? AppColors.surface : AppColors.raised,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => _editSpeakerName('${utterance['speaker']}'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(child: Text(
                          transcript.speakerDisplayName('${utterance['speaker']}'),
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.accent,
                          ),
                        )),
                        const SizedBox(width: 5),
                        const Icon(Icons.edit_outlined, size: 12, color: AppColors.accent),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  utterance['text'] ?? '',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    color: AppColors.ink,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SpeakerNameDialog extends StatefulWidget {
  final String label;
  final String initialName;

  const _SpeakerNameDialog({required this.label, required this.initialName});

  @override
  State<_SpeakerNameDialog> createState() => _SpeakerNameDialogState();
}

class _SpeakerNameDialogState extends State<_SpeakerNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        'Name Speaker ${widget.label}',
        style: const TextStyle(fontFamily: 'Inter', color: AppColors.ink),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 80,
        textCapitalization: TextCapitalization.words,
        style: const TextStyle(fontFamily: 'Inter', fontSize: 15, color: AppColors.ink),
        decoration: const InputDecoration(
          hintText: 'Speaker name',
          hintStyle: TextStyle(color: AppColors.muted),
          counterStyle: TextStyle(color: AppColors.muted),
        ),
        onSubmitted: (_) => Navigator.pop(context, _controller.text.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: AppColors.muted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Save', style: TextStyle(color: AppColors.accent)),
        ),
      ],
    );
  }
}

/// The 3-dot dropdown as its own route so opening/closing is a smooth
/// scale + fade that pops out of the menu's top-left corner — anchored
/// right under the 3-dot button.
class _AnchorMenuRoute extends PopupRoute<String> {
  final Rect anchorRect;
  final bool hasAudio;

  _AnchorMenuRoute({required this.anchorRect, this.hasAudio = false});

  static const _menuWidth = 200.0;
  // 4 items x 50 + 3 hairline dividers, approximated for clamping
  static const _menuHeightApprox = 210.0;

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss menu';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 190);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 150);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final size = MediaQuery.sizeOf(context);
    final top = (anchorRect.bottom + 6)
        .clamp(8.0, size.height - _menuHeightApprox - 16);
    final right = size.width - anchorRect.right;

    final eased = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return Stack(
      children: [
        Positioned(
          top: top,
          right: right.clamp(8.0, size.width - _menuWidth - 8),
          width: _menuWidth,
          child: ScaleTransition(
            // pops out of the top-right corner of the menu (toward the button)
            alignment: Alignment.topRight,
            scale: Tween<double>(begin: 0.75, end: 1.0).animate(eased),
            child: FadeTransition(
              opacity: eased,
              child: Material(
                color: AppColors.surface,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(color: AppColors.homeBorder),
                ),
                elevation: 12,
                shadowColor: Colors.black26,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _menuItem(context, 'rename', Icons.edit_outlined, 'Rename'),
                    _hairline(),
                    _menuItem(
                      context,
                      'copy-transcript',
                      Icons.copy_rounded,
                      'Copy transcript',
                    ),
                    _hairline(),
                    _menuItem(
                      context,
                      'copy-summary',
                      Icons.summarize_outlined,
                      'Copy summary',
                    ),
                    if (hasAudio) ...[
                      _hairline(),
                      _menuItem(
                        context,
                        'export-audio',
                        Icons.file_download_outlined,
                        'Export audio',
                      ),
                    ],
                    _hairline(),
                    _menuItem(
                      context,
                      'delete',
                      Icons.delete_outline,
                      'Delete recording',
                      color: Colors.red,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _menuItem(
    BuildContext menuContext,
    String value,
    IconData icon,
    String label, {
    Color color = AppColors.ink,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.pop(menuContext, value),
      child: Container(
        width: double.infinity,
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hairline() => Container(height: 0.5, color: AppColors.homeBorder);
}
