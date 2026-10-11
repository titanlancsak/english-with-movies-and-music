import 'dart:math';

import 'package:flutter/material.dart';

/// The app's look, the same as the Mac version (Sources/EnglishWithMovies/Theme.swift):
/// a deep dark background lit by soft glows in the icon's colors (indigo, violet, orange),
/// translucent "glass" panels and gradient accents.
class AppColors {
  static const background = Color(0xFF09090F);
  static const surface = Color(0x0EFFFFFF); // white 5.5%
  static const surfaceHover = Color(0x17FFFFFF); // white 9%
  static const stroke = Color(0x17FFFFFF);
  static const textDim = Color(0x8CFFFFFF); // white 55%

  static const indigo = Color(0xFF6366F1);
  static const violet = Color(0xFFA855F7);
  static const orange = Color(0xFFF97316);
  static const pink = Color(0xFFEC4899);
  static const green = Color(0xFF34D399);
  static const yellow = Color(0xFFFBBF24);
  static const red = Color(0xFFF87171);
  static const blue = Color(0xFF60A5FA);

  /// Buttons, highlights, the current word.
  static const brand = LinearGradient(colors: [indigo, violet], begin: Alignment.topLeft, end: Alignment.bottomRight);

  /// Titles and "special" accents.
  static const warm = LinearGradient(colors: [violet, pink, orange]);
}

const appRadius = 16.0;

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.violet, brightness: Brightness.dark).copyWith(
    primary: AppColors.violet,
    surface: const Color(0xFF15151F),
  );
  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    useMaterial3: true,
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFF13131C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: AppColors.stroke)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: const Color(0xFF26263A), borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: const Color(0xFF1A1A26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.stroke)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// The window background: dark, with three soft glows.
class AuroraBackground extends StatelessWidget {
  const AuroraBackground({super.key});

  @override
  Widget build(BuildContext context) {
    Widget glow(Color color, double opacity, Alignment center, double radius) => Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: center,
                radius: radius,
                colors: [color.withValues(alpha: opacity), color.withValues(alpha: 0)],
              ),
            ),
          ),
        );
    return IgnorePointer(
      child: Stack(children: [
        const Positioned.fill(child: ColoredBox(color: AppColors.background)),
        glow(AppColors.indigo, 0.30, const Alignment(-0.9, -1.1), 1.0),
        glow(AppColors.violet, 0.20, const Alignment(1.1, -0.6), 0.9),
        glow(AppColors.orange, 0.10, const Alignment(0.3, 1.3), 0.9),
      ]),
    );
  }
}

/// A translucent rounded panel with a hairline border.
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding, this.radius = appRadius, this.highlighted = false, this.color});
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final bool highlighted;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? (highlighted ? AppColors.surfaceHover : AppColors.surface),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.stroke),
      ),
      child: child,
    );
  }
}

/// Text filled with a gradient.
class GradientText extends StatelessWidget {
  const GradientText(this.text, {super.key, required this.style, this.gradient = AppColors.warm, this.maxLines, this.textAlign});
  final String text;
  final TextStyle style;
  final Gradient gradient;
  final int? maxLines;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => gradient.createShader(Offset.zero & bounds.size),
      child: Text(text, style: style, maxLines: maxLines, overflow: maxLines == null ? null : TextOverflow.ellipsis, textAlign: textAlign),
    );
  }
}

/// Large gradient title with a dim subtitle, used at the top of each screen.
class ScreenTitle extends StatelessWidget {
  const ScreenTitle(this.title, {super.key, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      GradientText(title, style: TextStyle(fontSize: compact ? 26 : 30, fontWeight: FontWeight.w900)),
      if (subtitle != null) ...[
        const SizedBox(height: 4),
        Text(subtitle!, style: const TextStyle(color: AppColors.textDim)),
      ],
    ]);
  }
}

/// Small uppercase title above a section.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: AppColors.textDim));
}

/// Small rounded label, e.g. "noun", "CC", "Revisar agora".
class TagChip extends StatelessWidget {
  const TagChip(this.text, {super.key, this.icon, this.color = Colors.white});
  final String text;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 4)],
        Flexible(
          child: Text(text,
              overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ),
      ]),
    );
  }
}

/// Main action: gradient capsule with a glow.
class PrimaryButton extends StatefulWidget {
  const PrimaryButton({super.key, required this.label, this.icon, this.onPressed, this.gradient = AppColors.brand, this.expand = false});
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Gradient gradient;
  final bool expand;

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            decoration: BoxDecoration(
              gradient: widget.gradient,
              borderRadius: BorderRadius.circular(99),
              boxShadow: [
                if (enabled)
                  BoxShadow(color: AppColors.violet.withValues(alpha: _hovered ? 0.6 : 0.4), blurRadius: _hovered ? 20 : 14, offset: const Offset(0, 4)),
              ],
            ),
            child: Row(
              mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[Icon(widget.icon, size: 18, color: Colors.white), const SizedBox(width: 8)],
                Text(widget.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Secondary action: glass capsule.
class GlassButton extends StatefulWidget {
  const GlassButton({super.key, required this.label, this.icon, this.onPressed});
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: _hovered ? AppColors.surfaceHover : AppColors.surface,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: AppColors.stroke),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (widget.icon != null) ...[Icon(widget.icon, size: 17, color: Colors.white), const SizedBox(width: 8)],
              Text(widget.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Round icon button on glass.
class GlassIconButton extends StatefulWidget {
  const GlassIconButton({super.key, required this.icon, required this.tooltip, this.onPressed, this.size = 34, this.color = Colors.white});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final Color color;

  @override
  State<GlassIconButton> createState() => _GlassIconButtonState();
}

class _GlassIconButtonState extends State<GlassIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _hovered ? AppColors.surfaceHover : AppColors.surface,
              border: Border.all(color: AppColors.stroke),
            ),
            child: Icon(widget.icon, size: widget.size * 0.5, color: widget.color.withValues(alpha: enabled ? 1 : 0.35)),
          ),
        ),
      ),
    );
  }
}

/// A thin progress bar filled with the warm gradient.
class GradientProgress extends StatelessWidget {
  const GradientProgress({super.key, required this.value, this.height = 6});
  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(children: [
          Container(decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(99))),
          Container(
            width: max(height, constraints.maxWidth * value.clamp(0, 1)),
            decoration: BoxDecoration(gradient: AppColors.warm, borderRadius: BorderRadius.circular(99)),
          ),
        ]),
      ),
    );
  }
}

/// A square icon tile with a gradient, e.g. in stat cards and the sidebar.
class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, required this.color, this.size = 32, this.glow = false});
  final IconData icon;
  final Color color;
  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: LinearGradient(colors: [color, Color.lerp(color, Colors.black, 0.25)!], begin: Alignment.topCenter, end: Alignment.bottomCenter),
        boxShadow: glow ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 12)] : null,
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.48),
    );
  }
}

/// A large icon filled with the brand gradient.
class EmptyStateIcon extends StatelessWidget {
  const EmptyStateIcon(this.icon, {super.key, this.size = 52});
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => AppColors.brand.createShader(Offset.zero & bounds.size),
        child: Icon(icon, size: size),
      );
}

/// Icon, title and explanation for an empty screen.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title, text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => AppColors.brand.createShader(Offset.zero & bounds.size),
            child: Icon(icon, size: 44),
          ),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textDim)),
        ]),
      ),
    );
  }
}
