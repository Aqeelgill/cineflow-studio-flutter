import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const kBrandGradient = LinearGradient(
  colors: [
    Color(0xFF4285F4),
    Color(0xFF9B72CB),
    Color(0xFFD96570),
    Color(0xFF34A853),
  ],
);

class HandCursorProvider {
  static MouseCursor? _cursor;
  static bool _loaded = false;

  static MouseCursor get cursor => _cursor ?? SystemMouseCursors.click;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final data = await rootBundle.load('assets/cursors/hand_black.png');
      // Fallback to system click cursor; custom bitmap cursor API is limited on
      // desktop targets, but asset is bundled and ready if supported.
      final _ = data.buffer.asUint8List();
      _cursor = SystemMouseCursors.click;
    } catch (_) {
      _cursor = SystemMouseCursors.click;
    }
  }
}

class ClickableRegion extends StatelessWidget {
  const ClickableRegion({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return MouseRegion(cursor: HandCursorProvider.cursor, child: child);
  }
}

class FocusGlow extends StatefulWidget {
  const FocusGlow({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  final Widget child;
  final BorderRadius borderRadius;

  @override
  State<FocusGlow> createState() => _FocusGlowState();
}

class _FocusGlowState extends State<FocusGlow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (v) => setState(() => _focused = v),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          border: _focused
              ? null
              : Border.all(color: const Color(0xFF263244), width: 2),
          gradient: _focused ? kBrandGradient : null,
          boxShadow: _focused
              ? const [
                  BoxShadow(
                    color: Color(0x334285F4),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: Color(0x2234A853),
                    blurRadius: 14,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.all(2),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0B1220),
            borderRadius: widget.borderRadius.subtract(
              const BorderRadius.all(Radius.circular(2)),
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class GradientTitle extends StatelessWidget {
  const GradientTitle({super.key});

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 21,
      fontWeight: FontWeight.w800,
      color: Colors.white,
    );
    Widget grad(String text) => ShaderMask(
          shaderCallback: (bounds) => kBrandGradient.createShader(
            Rect.fromLTWH(0, 0, bounds.width, bounds.height),
          ),
          blendMode: BlendMode.srcIn,
          child: Text(text, style: style),
        );
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          grad('CineFlo'),
          const SizedBox(width: 8),
          ClickableRegion(
            child: Image.asset(
              'assets/logo/cineflow_icon.png',
              width: 24,
              height: 24,
              fit: BoxFit.contain,
            ),
          ),
          grad('w Studio'),
        ],
      ),
    );
  }
}

class HoverGlow extends StatefulWidget {
  const HoverGlow({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.baseColor = const Color(0xFF111827),
    this.hoverColor = const Color(0xFF162033),
    this.borderColor = const Color(0xFF1F2937),
    this.hoverBorderColor = const Color(0xFF06B6D4),
  });

  final Widget child;
  final BorderRadius borderRadius;
  final Color baseColor;
  final Color hoverColor;
  final Color borderColor;
  final Color hoverBorderColor;

  @override
  State<HoverGlow> createState() => _HoverGlowState();
}

class _HoverGlowState extends State<HoverGlow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: HandCursorProvider.cursor,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: _hover ? widget.hoverColor : widget.baseColor,
          borderRadius: widget.borderRadius,
          border: Border.all(
            color: _hover ? widget.hoverBorderColor : widget.borderColor,
          ),
          boxShadow: _hover
              ? [
                  BoxShadow(
                    color: widget.hoverBorderColor.withValues(alpha: 0.25),
                    blurRadius: 8,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: widget.child,
      ),
    );
  }
}
