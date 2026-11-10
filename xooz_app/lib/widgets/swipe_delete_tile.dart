import 'package:flutter/material.dart';

class SwipeDeleteTile extends StatefulWidget {
  const SwipeDeleteTile({
    super.key,
    required this.id,
    required this.onDismissed,
    required this.child,
  });

  final String id;
  final VoidCallback onDismissed;
  final Widget child;

  @override
  State<SwipeDeleteTile> createState() => _SwipeDeleteTileState();
}

class _SwipeDeleteTileState extends State<SwipeDeleteTile> {
  final ValueNotifier<double> _swipeProgress = ValueNotifier(0);

  @override
  void dispose() {
    _swipeProgress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('swipe-delete-${widget.id}'),
      direction: DismissDirection.endToStart,
      onUpdate: (details) => _swipeProgress.value = details.progress,
      onDismissed: (_) => widget.onDismissed(),
      background: LayoutBuilder(
        builder: (context, constraints) => ValueListenableBuilder<double>(
          valueListenable: _swipeProgress,
          builder: (context, progress, _) {
            final width = constraints.maxWidth * progress;
            return Align(
              alignment: Alignment.centerRight,
              child: Container(
                width: width,
                margin: const EdgeInsets.only(bottom: 10),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: const Color(0xFFAB5463),
                  borderRadius: BorderRadius.circular(24),
                ),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 24),
                child: width >= 56
                    ? const Icon(
                        Icons.delete_rounded,
                        color: Color(0xFF29141A),
                        size: 24,
                      )
                    : null,
              ),
            );
          },
        ),
      ),
      child: widget.child,
    );
  }
}
