import '../theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;
import '../services/audio_service.dart';
import '../services/api_service.dart';

class RecordingScreen extends StatefulWidget {
  /// Called when an upload succeeds after this screen was already closed
  /// (user hit the cross mid-transcription) so the home list can refresh.
  final VoidCallback? onUploadFinished;

  const RecordingScreen({super.key, this.onUploadFinished});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen>
    with SingleTickerProviderStateMixin {
  bool _isRecording = false;
  bool _isUploading = false;
  Duration _duration = Duration.zero;
  Timer? _timer;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _startRecording();
  }

  Future<void> _startRecording() async {
    final hasPermission = await AudioService.hasPermission();
    if (!hasPermission) {
      setState(() => _statusMessage = 'Microphone permission denied');
      return;
    }
    await AudioService.startRecording();
    setState(() {
      _isRecording = true;
      _statusMessage = null;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _duration += const Duration(seconds: 1));
    });
  }

  Future<void> _stopAndUpload() async {
    _timer?.cancel();
    _pulseController.stop();

    setState(() {
      _isRecording = false;
      _isUploading = true;
      _statusMessage = 'Transcribing...';
    });

    try {
      final file = await AudioService.stopRecording();
      if (file == null) throw Exception('No audio recorded');
      if (_duration < const Duration(seconds: 1) ||
          !await file.exists() ||
          await file.length() < 2048) {
        throw Exception('Recording is empty or too short. Please try again.');
      }

      await ApiService.uploadAudio(file, duration: _duration);

      if (!mounted) {
        // user already closed the screen mid-transcription — the transcript
        // was still saved on the server; refresh the list behind us
        widget.onUploadFinished?.call();
        // upload finished, the temp file is safe to remove now
        await AudioService.deletePendingFile();
        return;
      }
      setState(() => _statusMessage = 'Done');
      await Future.delayed(const Duration(milliseconds: 800));

      if (mounted) Navigator.pop(context);
    } catch (e) {
      // upload failed with the screen already closed — the recording was
      // never sent, so discard the temp file quietly
      if (!mounted) {
        await AudioService.deletePendingFile();
        return;
      }
      setState(() {
        _isUploading = false;
        _statusMessage = 'Failed: ${e.toString()}';
      });
    }
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    _pulseController.stop();
    if (!mounted) return;
    final wasUploading = _isUploading;
    // leave instantly — don't wait for the recorder to shut down
    Navigator.pop(context);
    // discard the recording — but never delete a file that an active
    // upload is still reading, or the transcript would be lost
    await AudioService.cancelRecording(deleteFile: !wasUploading);
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 20),
              Row(
                children: [
                  GestureDetector(
                    onTap: _cancel,
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
                        Icons.close,
                        color: AppColors.muted,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (_isRecording)
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: CustomPaint(
                    foregroundPainter: _RecordingDialPainter(),
                    child: Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        border: const Border.fromBorderSide(
                          BorderSide(color: AppColors.homeBorder),
                        ),
                        borderRadius: BorderRadius.circular(90),
                      ),
                      child: const Icon(
                        Icons.mic_none_rounded,
                        color: AppColors.ink,
                        size: 60,
                      ),
                    ),
                  ),
                )
              else if (_isUploading)
                const CircularProgressIndicator(color: AppColors.accent),
              const SizedBox(height: 32),
              if (_isRecording)
                Text(
                  _formatDuration(_duration),
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 48,
                    color: AppColors.ink,
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                _statusMessage ?? (_isRecording ? 'Recording...' : ''),
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  color: AppColors.muted,
                ),
              ),
              const Spacer(),
              if (_isRecording)
                GestureDetector(
                  onTap: _stopAndUpload,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.ink,
                      borderRadius: BorderRadius.circular(36),
                    ),
                    child: const Icon(
                      Icons.stop_rounded,
                      color: AppColors.background,
                      size: 32,
                    ),
                  ),
                ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordingDialPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final paint = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var tick = 0; tick < 48; tick++) {
      final angle = tick * math.pi / 24 - math.pi / 2;
      final direction = Offset(math.cos(angle), math.sin(angle));
      paint.color = tick >= 28 && tick <= 38
          ? AppColors.accent
          : AppColors.raised;
      canvas.drawLine(
        center + direction * (radius - 12),
        center + direction * (radius - 4),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RecordingDialPainter oldDelegate) => false;
}
