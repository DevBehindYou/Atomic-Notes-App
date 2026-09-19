import 'dart:math' as math;

import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:atomic_notes/theme/editorial.dart';
import 'package:flutter/material.dart';

/// A confirmation that cannot happen by accident: the user drags the thumb
/// along the track. Letting go before the end snaps it back and nothing runs.
///
/// Used for actions that destroy data. A tap can be a slip; a deliberate slide
/// across the whole control cannot.
class SlideToConfirm extends StatefulWidget {
  /// What the slide does, shown on the track ("Wipe cloud notes").
  final String label;

  /// Runs once the thumb reaches the end. The thumb stays at the end, showing
  /// progress, until this completes.
  final Future<void> Function() onConfirmed;

  /// Share of the track that counts as "all the way".
  static const double confirmAt = 0.92;

  /// For tests.
  static const Key thumbKey = Key('slide-to-confirm-thumb');

  const SlideToConfirm({
    required this.label,
    required this.onConfirmed,
    super.key,
  });

  @override
  State<SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<SlideToConfirm> {
  static const double _thumbSize = 54;
  static const double _trackHeight = 58;
  static const double _inset = 2;

  double _offset = 0;
  bool _dragging = false;
  bool _running = false;

  Future<void> _release(double travel) async {
    if (_offset / travel >= SlideToConfirm.confirmAt) {
      setState(() {
        _offset = travel;
        _dragging = false;
        _running = true;
      });
      try {
        await widget.onConfirmed();
      } finally {
        if (mounted) {
          setState(() {
            _running = false;
            _offset = 0;
          });
        }
      }
    } else {
      setState(() {
        _dragging = false;
        _offset = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final double travel =
            math.max(1.0, box.maxWidth - _thumbSize - _inset * 2);
        final double progress = math.min(1.0, _offset / travel);
        // Snap back smoothly, but follow the finger exactly while dragging.
        final Duration follow =
            _dragging ? Duration.zero : const Duration(milliseconds: 180);

        return Semantics(
          button: true,
          label: 'Slide to ${widget.label}',
          child: Container(
            height: _trackHeight,
            decoration: BoxDecoration(
              color: AppColors.errorContainer,
              borderRadius: AppRadius.std,
              border:
                  Border.all(color: AppColors.error, width: AppStroke.hairline),
            ),
            child: ClipRRect(
              borderRadius: AppRadius.std,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // The red fill that follows the thumb.
                  AnimatedContainer(
                    duration: follow,
                    width: _offset + _thumbSize + _inset * 2,
                    color: AppColors.error,
                  ),
                  // The instruction fades as the thumb covers it.
                  Center(
                    child: Opacity(
                      opacity: 1 - progress,
                      child: Padding(
                        padding: const EdgeInsets.only(left: _thumbSize),
                        child: MonoLabel(
                          _running ? 'Working…' : 'Slide to ${widget.label}',
                          color: AppColors.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                  AnimatedPositioned(
                    duration: follow,
                    left: _offset + _inset,
                    child: GestureDetector(
                      key: SlideToConfirm.thumbKey,
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart:
                          _running ? null : (_) => setState(() => _dragging = true),
                      onHorizontalDragUpdate: _running
                          ? null
                          : (details) => setState(() {
                                _offset = math.max(
                                    0.0,
                                    math.min(travel, _offset + details.delta.dx));
                              }),
                      onHorizontalDragEnd:
                          _running ? null : (_) => _release(travel),
                      onHorizontalDragCancel: _running
                          ? null
                          : () => setState(() {
                                _dragging = false;
                                _offset = 0;
                              }),
                      child: Container(
                        width: _thumbSize,
                        height: _trackHeight - _inset * 2 - 3,
                        decoration: const BoxDecoration(
                          color: AppColors.ink,
                          borderRadius: AppRadius.std,
                        ),
                        child: _running
                            ? const Padding(
                                padding: EdgeInsets.all(15),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      AppColors.paper),
                                ),
                              )
                            : const Icon(Icons.keyboard_double_arrow_right,
                                color: AppColors.paper, size: 26),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
