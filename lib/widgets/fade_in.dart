import 'package:flutter/material.dart';

/// 入场微动效：淡入 + 轻微上移（遵循 MOTION_INTENSITY 中等的流体感）。
class FadeIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final Offset offset;

  const FadeIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 420),
    this.offset = const Offset(0, 12),
  });

  @override
  State<FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<FadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _opacity =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  late final Animation<Offset> _position =
      Tween<Offset>(begin: widget.offset, end: Offset.zero).animate(_opacity);

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _opacity,
        child: SlideTransition(position: _position, child: widget.child),
      );
}
