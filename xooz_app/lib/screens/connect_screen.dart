import 'package:flutter/material.dart';
import 'dart:math';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _rotationAnimation;
  bool _isSearching = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _rotationAnimation = Tween<double>(begin: 0, end: 2 * pi).animate(
      CurvedAnimation(parent: _controller, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildWatchVisual(),
                  const SizedBox(height: 40),
                  Text(
                    _isSearching
                        ? 'Searching for devices'
                        : 'No devices found',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      color: Color(0xFF6B6460),
                    ),
                  ),
                ],
              ),
            ),
            _buildBottomActions(),
          ],
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
                color: const Color(0xFF1A1512),
                borderRadius: BorderRadius.circular(19),
              ),
              child: const Icon(
                Icons.arrow_back,
                color: Color(0xFF6B6460),
                size: 18,
              ),
            ),
          ),
          const Spacer(),
          const Text(
            'Connect',
            style: TextStyle(
              fontFamily: 'DMSerifDisplay',
              fontSize: 22,
              color: Color(0xFFE8DFD0),
            ),
          ),
          const Spacer(),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1512),
              borderRadius: BorderRadius.circular(19),
            ),
            child: const Icon(
              Icons.settings_outlined,
              color: Color(0xFF6B6460),
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWatchVisual() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // outer rotating ring
        AnimatedBuilder(
          animation: _rotationAnimation,
          builder: (_, child) {
            return Transform.rotate(
              angle: _rotationAnimation.value,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFC8B89A).withOpacity(0.15),
                    width: 1,
                  ),
                ),
                child: CustomPaint(
                  painter: _DashedCirclePainter(
                    color: const Color(0xFFC8B89A).withOpacity(0.4),
                  ),
                ),
              ),
            );
          },
        ),
        // middle ring
        Container(
          width: 180,
          height: 180,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFF1A1512),
              width: 1,
            ),
          ),
        ),
        // inner watch circle
        Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF1A1512),
            border: Border.all(
              color: const Color(0xFF252018),
              width: 2,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.watch_outlined,
                color: Color(0xFFC8B89A),
                size: 36,
              ),
              const SizedBox(height: 8),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: const Color(0xFFC8B89A).withOpacity(0.6),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
      child: Column(
        children: [
          GestureDetector(
            onTap: () {},
            child: const Text(
              'Get Xooz Watch App',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFFE8DFD0),
              ),
            ),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () {},
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(
                  Icons.info_outline,
                  color: Color(0xFF6B6460),
                  size: 16,
                ),
                SizedBox(width: 6),
                Text(
                  'Connection Guide',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    color: Color(0xFF6B6460),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  final Color color;

  _DashedCirclePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const dashCount = 16;
    const dashAngle = 2 * pi / dashCount;

    for (int i = 0; i < dashCount; i++) {
      final startAngle = i * dashAngle;
      final endAngle = startAngle + dashAngle * 0.4;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        endAngle - startAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedCirclePainter oldDelegate) => false;
}