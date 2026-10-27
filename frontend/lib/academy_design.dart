import 'dart:math' as math;
import 'package:flutter/material.dart';

const academyEmerald = Color(0xFF145B45);
const academyInk = Color(0xFF193E32);
const academyIvory = Color(0xFFFAF8F1);
const academyGold = Color(0xFFB59857);

/// Local vector artwork: no image downloads are required at startup.
class AcademyBackdrop extends StatelessWidget {
  final Widget child;
  const AcademyBackdrop({super.key, required this.child});
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFBF1), Color(0xFFF7F8F2), Color(0xFFF0E9D9)],
      ),
    ),
    child: CustomPaint(painter: _GardenPainter(), child: child),
  );
}

class AcademyBrand extends StatelessWidget {
  final String subtitle;
  const AcademyBrand({super.key, this.subtitle = 'Online Quran Academy'});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.mosque_outlined, color: academyEmerald, size: 35),
      const SizedBox(width: 10),
      Flexible(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Al Hassan',
              style: TextStyle(
                fontFamily: 'CormorantGaramond',
                fontSize: 25,
                fontWeight: FontWeight.w700,
                color: academyInk,
              ),
            ),
            Text(
              subtitle,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: academyEmerald),
            ),
          ],
        ),
      ),
    ],
  );
}

class AcademyAvatar extends StatelessWidget {
  final String name;
  final double radius;
  const AcademyAvatar({super.key, required this.name, this.radius = 24});
  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: radius,
    backgroundColor: const Color(0xFFF1E7CD),
    child: CircleAvatar(
      radius: radius - 3,
      backgroundColor: const Color(0xFFF9F5E9),
      child: Text(
        name.trim().isEmpty ? 'A' : name.trim().substring(0, 1).toUpperCase(),
        style: TextStyle(
          color: academyEmerald,
          fontSize: radius * .8,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class AcademyIllustration extends StatelessWidget {
  const AcademyIllustration({super.key});
  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: .85,
    child: CustomPaint(
      painter: _SanctuaryPainter(),
      child: const FittedBox(
        child: SizedBox(
          width: 360,
          height: 500,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(height: 30),
              Icon(Icons.nightlight_round, color: academyGold, size: 29),
              SizedBox(height: 8),
              Icon(Icons.mosque_outlined, color: academyEmerald, size: 86),
              SizedBox(height: 14),
              Text(
                'Al Hassan',
                style: TextStyle(
                  fontFamily: 'CormorantGaramond',
                  fontSize: 39,
                  fontWeight: FontWeight.w700,
                  color: academyInk,
                ),
              ),
              Text(
                'ONLINE QURAN ACADEMY',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 2.4,
                  color: academyEmerald,
                ),
              ),
              SizedBox(height: 15),
              Text(
                'Learn  ·  Practice  ·  Grow',
                style: TextStyle(color: Color(0xFF788074), fontSize: 12),
              ),
              SizedBox(height: 35),
              Icon(Icons.menu_book_rounded, color: academyEmerald, size: 65),
            ],
          ),
        ),
      ),
    ),
  );
}

class AcademyQuickAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final Color color;
  const AcademyQuickAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.color = academyEmerald,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    width: MediaQuery.sizeOf(context).width < 370 ? 56 : 68,
    child: Column(
      children: [
        Material(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(17),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(17),
            child: SizedBox(
              width: 56,
              height: 56,
              child: Icon(icon, color: color, size: 25),
            ),
          ),
        ),
        const SizedBox(height: 9),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11,
            color: academyInk,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _GardenPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = academyGold.withValues(alpha: .055);
    for (double x = 20; x < size.width; x += 68) {
      for (double y = 20; y < size.height; y += 68) {
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(math.pi / 4);
        canvas.drawRect(const Rect.fromLTWH(-9, -9, 18, 18), paint);
        canvas.restore();
      }
    }
    for (final right in [false, true]) {
      canvas.save();
      canvas.translate(right ? size.width : 0, size.height);
      if (right) canvas.scale(-1, 1);
      final stem = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(75, -80, 30, -190);
      canvas.drawPath(
        stem,
        Paint()
          ..color = academyEmerald.withValues(alpha: .12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      for (var i = 0; i < 7; i++) {
        final y = -22.0 - i * 23;
        final leaf = Path()
          ..moveTo(35, y)
          ..quadraticBezierTo(95, y - 36, 80, y - 58)
          ..quadraticBezierTo(37, y - 48, 35, y);
        canvas.drawPath(
          leaf,
          Paint()..color = academyEmerald.withValues(alpha: .07 + i * .008),
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _GardenPainter oldDelegate) => false;
}

class _SanctuaryPainter extends CustomPainter {
  Path arch(Rect r) => Path()
    ..moveTo(r.left, r.bottom)
    ..lineTo(r.left, r.top + r.height * .34)
    ..cubicTo(
      r.left,
      r.top + r.height * .16,
      r.center.dx - r.width * .09,
      r.top + r.height * .12,
      r.center.dx,
      r.top,
    )
    ..cubicTo(
      r.center.dx + r.width * .09,
      r.top + r.height * .12,
      r.right,
      r.top + r.height * .16,
      r.right,
      r.top + r.height * .34,
    )
    ..lineTo(r.right, r.bottom)
    ..close();
  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, const Radius.circular(28)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF7EEDB), Color(0xFFFFFCF3)],
        ).createShader(bounds),
    );
    final outer = Rect.fromLTRB(
      size.width * .08,
      20,
      size.width * .92,
      size.height - 25,
    );
    canvas.drawPath(arch(outer), Paint()..color = const Color(0xFFE1D4B8));
    final inner = outer.deflate(10);
    canvas.drawPath(
      arch(inner),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFC7D7CC), Color(0xFFEAECDD), Color(0xFFFCF8EC)],
        ).createShader(inner),
    );
    canvas.drawPath(
      arch(inner.deflate(10)),
      Paint()
        ..color = const Color(0xFFE7D5A7)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
    );
    for (final x in [size.width * .12, size.width * .88]) {
      final p = Paint()
        ..color = academyGold
        ..strokeWidth = 1;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height * .26), p);
      final lantern = Rect.fromCenter(
        center: Offset(x, size.height * .28),
        width: 13,
        height: 24,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(lantern, const Radius.circular(4)),
        Paint()..color = const Color(0xFFFDF3D5),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(lantern, const Radius.circular(4)),
        p..style = PaintingStyle.stroke,
      );
    }
    _GardenPainter().paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _SanctuaryPainter oldDelegate) => false;
}
