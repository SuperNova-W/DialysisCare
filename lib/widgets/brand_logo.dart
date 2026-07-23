import 'package:flutter/material.dart';
import '../theme.dart';

/// The DialysisCare brand mark — the mascot logo rendered as a rounded
/// (or circular) chip.
///
/// Mirrors the `.mark` in the design system's `guidelines/brand-logo.card.html`:
/// a square image at `--radius-md` (10px), `object-fit: cover`, with a branded
/// icon fallback if `assets/images/logo.png` fails to load.
///
/// Use the default constructor for the squared mark (app-bar mark r10, drawer
/// header r12, session-loading pulse r16) and [BrandLogo.circle] for the
/// circular assistant avatar.
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    this.size = 36,
    this.radius = 10,
    this.fallbackIcon = Icons.medical_services,
  }) : circle = false;

  /// Circular variant used for the assistant avatar.
  const BrandLogo.circle({
    super.key,
    this.size = 36,
    this.fallbackIcon = Icons.smart_toy,
  }) : radius = 0,
       circle = true;

  /// Edge length of the (square) mark in logical pixels.
  final double size;

  /// Corner radius when [circle] is false. Defaults to `--radius-md` (10px).
  final double radius;

  /// When true the mark is clipped to a perfect circle (avatar treatment).
  final bool circle;

  /// Icon shown on the branded fallback tile if the logo asset is missing.
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      'assets/images/logo.png',
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Container(
        width: size,
        height: size,
        color: Brand.tealDeep,
        alignment: Alignment.center,
        child: Icon(fallbackIcon, color: Brand.green, size: size * 0.52),
      ),
    );

    return SizedBox(
      width: size,
      height: size,
      child: circle
          ? ClipOval(child: image)
          : ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: image,
            ),
    );
  }
}

/// The DialysisCare logo lockup — the [BrandLogo] mark paired with the
/// "DialysisCare" wordmark and "AI Support for PKD" tagline.
///
/// Mirrors the lockup in `guidelines/brand-logo.card.html`: an 18px / w600 /
/// -0.3px name over a 12px steel sub-label, which flips to white / on-dark-muted
/// on dark surfaces ([onDark]). Defaults reproduce the card's specimen; the
/// drawer header overrides the sizes for its larger vertical treatment.
class BrandLockup extends StatelessWidget {
  const BrandLockup({
    super.key,
    this.onDark = false,
    this.axis = Axis.horizontal,
    this.markSize = 36,
    this.markRadius = 10,
    this.nameSize = 18,
    this.nameWeight = FontWeight.w600,
    this.nameSpacing = -0.3,
    this.subSize = 12,
    this.gap = 12,
  });

  /// Flip text colors for navy surfaces (app-bar stays light, drawer is dark).
  final bool onDark;

  /// Lay the mark beside the text (app bar) or above it (drawer header).
  final Axis axis;

  final double markSize;
  final double markRadius;
  final double nameSize;
  final FontWeight nameWeight;
  final double nameSpacing;
  final double subSize;

  /// Space between the mark and the text block.
  final double gap;

  @override
  Widget build(BuildContext context) {
    final isRow = axis == Axis.horizontal;
    final nameColor = onDark ? Brand.onDark : Brand.ink;
    final subColor = onDark ? Brand.onDarkMuted : Brand.steel;

    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DialysisCare',
          style: brandText(
            nameSize,
            nameWeight,
            1.2,
            spacing: nameSpacing,
            color: nameColor,
          ),
        ),
        SizedBox(height: isRow ? 0 : 4),
        Text(
          'AI Support for PKD',
          style: brandText(subSize, FontWeight.w400, 1.3, color: subColor),
        ),
      ],
    );

    final mark = BrandLogo(size: markSize, radius: markRadius);

    if (isRow) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [mark, SizedBox(width: gap), text],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [mark, SizedBox(height: gap), text],
    );
  }
}
