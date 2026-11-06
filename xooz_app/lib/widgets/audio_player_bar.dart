import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../theme/app_theme.dart';

/// Playback bar for the stored recording — play/pause, timeline, remaining time.
class AudioPlayerBar extends StatefulWidget {
  final String url;

  /// Notify with `false` when the bar is hidden (e.g. user switched tab) —
  /// playback stops and the position resets to the beginning.
  final ValueNotifier<bool>? visible;

  const AudioPlayerBar({super.key, required this.url, this.visible});

  @override
  State<AudioPlayerBar> createState() => _AudioPlayerBarState();
}

class _AudioPlayerBarState extends State<AudioPlayerBar> {
  final AudioPlayer _player = AudioPlayer();
  bool _initialized = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.visible?.addListener(_onVisibilityChanged);
    _loadAudio();
  }

  @override
  void didUpdateWidget(AudioPlayerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      oldWidget.visible?.removeListener(_onVisibilityChanged);
      widget.visible?.addListener(_onVisibilityChanged);
    }
  }

  void _onVisibilityChanged() {
    if (widget.visible?.value == false) _stopAndRewind();
  }

  /// Hidden — stop playback and rewind to the beginning.
  Future<void> _stopAndRewind() async {
    try {
      if (_player.playing) await _player.pause();
      await _player.seek(Duration.zero);
    } catch (_) {
      // stopping is best effort
    }
    if (mounted) setState(() {}); // refresh play icon
  }

  Future<void> _loadAudio() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _player.setUrl(widget.url);
      if (!mounted) return;
      setState(() {
        _initialized = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load recording: $e';
      });
    }
  }

  @override
  void dispose() {
    widget.visible?.removeListener(_onVisibilityChanged);
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_loading) return;
    if (!_initialized) {
      await _loadAudio();
      if (!_initialized) return;
    }
    try {
      // restart from the beginning once finished
      if (_player.duration != null && _player.position >= _player.duration!) {
        await _player.seek(Duration.zero);
      }
      if (_player.playing) {
        await _player.pause();
      } else {
        // play() completes when playback ends; do not hold the UI loading
        // state until then.
        unawaited(
          _player.play().catchError((Object e) {
            if (mounted) setState(() => _error = 'Playback failed: $e');
          }),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Playback failed: $e';
        });
      }
    }
    if (mounted) setState(() {}); // refresh icon state
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Seek from the dotted timeline's tap/drag position (0..1).
  Future<void> _seekFraction(double fraction) async {
    final d = _player.duration;
    if (d == null || d <= Duration.zero || !_initialized) return;
    try {
      await _player.seek(
        Duration(milliseconds: (d.inMilliseconds * fraction.clamp(0.0, 1.0)).round()),
      );
    } catch (_) {
      // seeking is best effort
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border.fromBorderSide(
          BorderSide(color: AppColors.homeBorder),
        ),
        borderRadius: BorderRadius.circular(32),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StreamBuilder<Duration?>(
            stream: _player.durationStream,
            builder: (context, durationSnap) {
              final duration =
                  durationSnap.data ?? _player.duration ?? Duration.zero;

              return StreamBuilder<Duration>(
                stream: _player.positionStream,
                builder: (context, positionSnap) {
                  final position = positionSnap.data ?? Duration.zero;
                  final remaining = duration > position
                      ? duration - position
                      : Duration.zero;
                  final isPlaying = _player.playing;

                  return Row(
                    children: [
                      // play / pause
                      GestureDetector(
                        onTap: _togglePlay,
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: AppColors.ink,
                            borderRadius: BorderRadius.circular(21),
                          ),
                          child: _loading
                              ? const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  _error != null
                                      ? Icons.refresh
                                      : isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // timeline
                      Expanded(
                        child: _DottedTimeline(
                          fraction: duration > Duration.zero
                              ? (position.inMilliseconds / duration.inMilliseconds)
                                    .clamp(0.0, 1.0)
                              : 0.0,
                          onChanged: _seekFraction,
                        ),
                      ),
                      const SizedBox(width: 6),
                      // remaining time
                      SizedBox(
                        width: 44,
                        child: Text(
                          '-${_fmt(remaining)}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
          if (_error != null)
            Text(
              _error!,
              style: const TextStyle(color: AppColors.ink, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

/// Dotted timeline matching the design — tap or drag anywhere on it to seek.
class _DottedTimeline extends StatelessWidget {
  final double fraction; // 0..1 how much has played
  final ValueChanged<double> onChanged;

  const _DottedTimeline({required this.fraction, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = (constraints.maxWidth ~/ 10).clamp(10, 30);
        void seek(Offset local) => onChanged(local.dx / constraints.maxWidth);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => seek(d.localPosition),
          onHorizontalDragStart: (d) => seek(d.localPosition),
          onHorizontalDragUpdate: (d) => seek(d.localPosition),
          child: Row(
            children: List.generate(count, (i) {
              final played = (i / count) < fraction;
              return Expanded(
                child: Center(
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: played ? AppColors.ink : AppColors.muted,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
