import 'package:flutter/material.dart';
import 'dart:async';
import '../services/audio_service.dart';
import '../services/api_service.dart';

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});

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

      final transcript = await ApiService.uploadAudio(file);

      setState(() => _statusMessage = 'Done');
      await Future.delayed(const Duration(milliseconds: 800));

      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _isUploading = false;
        _statusMessage = 'Failed: ${e.toString()}';
      });
    }
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    await AudioService.cancelRecording();
    if (mounted) Navigator.pop(context);
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
      backgroundColor: const Color(0xFF0A0A0A),
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
              const Spacer(),
              if (_isRecording)
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1512),
                      borderRadius: BorderRadius.circular(90),
                      border: Border.all(
                        color: const Color(0xFFC8B89A).withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.mic,
                      color: Color(0xFFE8DFD0),
                      size: 60,
                    ),
                  ),
                )
              else if (_isUploading)
                const CircularProgressIndicator(
                  color: Color(0xFFC8B89A),
                ),
              const SizedBox(height: 32),
              if (_isRecording)
                Text(
                  _formatDuration(_duration),
                  style: const TextStyle(
                    fontFamily: 'DMSerifDisplay',
                    fontSize: 48,
                    color: Color(0xFFE8DFD0),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                _statusMessage ??
                    (_isRecording ? 'Recording...' : ''),
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  color: Color(0xFF6B6460),
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
                      color: const Color(0xFFE8DFD0),
                      borderRadius: BorderRadius.circular(36),
                    ),
                    child: const Icon(
                      Icons.stop_rounded,
                      color: Color(0xFF0A0A0A),
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