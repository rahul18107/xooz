import '../theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
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
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
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
    final blobSize = math.min(MediaQuery.sizeOf(context).width - 48, 300.0);
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
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
                SizedBox.square(
                  dimension: blobSize,
                  child: AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) => CustomPaint(
                      painter: _RecordingBlobPainter(_pulseController.value),
                      child: Center(
                        child: Transform.scale(
                          scale:
                              1 +
                              0.035 *
                                  math.sin(
                                    _pulseController.value * 10 * math.pi,
                                  ),
                          child: child,
                        ),
                      ),
                    ),
                    child: ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        Colors.white,
                        BlendMode.srcIn,
                      ),
                      child: Lottie.asset(
                        'assets/animations/microphone.json',
                        width: 44,
                        height: 44,
                        fit: BoxFit.contain,
                        repeat: true,
                        animate: true,
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
                _statusMessage ?? (_isRecording ? 'Listening...' : ''),
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

class _RecordingBlobPainter extends CustomPainter {
  final double progress;

  const _RecordingBlobPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final unit = size.shortestSide / 264;
    final time = progress * 10 * math.pi;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(progress * 2 * math.pi);
    canvas.translate(-center.dx, -center.dy);
    Path blobPath(double spread) {
      final path = Path();
      const steps = 180;
      for (var i = 0; i <= steps; i++) {
        final angle = i * 2 * math.pi / steps;
        final scallop = math.cos(9 * angle + 0.2 + 0.12 * math.sin(time));
        final breath = 7.0 * math.sin(time + 0.2);
        final morph = 1.2 * math.sin(4 * angle - time + 0.2);
        final radius = (95.0 + 5.0 * scallop + breath + morph + spread) * unit;
        final point =
            center + Offset(math.cos(angle), math.sin(angle)) * radius;
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      path.close();
      return path;
    }

    final rippleProgress = (progress * 5) % 1;
    final spread = 24.0 * Curves.easeOutCubic.transform(rippleProgress);
    final fade = (1 - rippleProgress) * (1 - rippleProgress);
    canvas.drawPath(
      blobPath(spread),
      Paint()..color = const Color(0xFFAAAAAA).withValues(alpha: 0.8 * fade),
    );
    canvas.drawPath(blobPath(0), Paint()..color = const Color(0xFF151515));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RecordingBlobPainter oldDelegate) =>
      progress != oldDelegate.progress;
}
