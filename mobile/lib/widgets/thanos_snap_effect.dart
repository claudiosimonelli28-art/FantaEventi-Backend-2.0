import 'dart:math';
import 'package:flutter/material.dart';

/// Effetto di disintegrazione a particelle "Schiocco di Thanos"
/// Dissolve il widget figlio trasformandolo in frammenti di cenere, fumo e scintille
/// che fluttuano verso l'alto prima di richiudere morbidamente lo spazio nella lista.
class ThanosSnapEffect extends StatefulWidget {
  final Widget child;
  final bool isDisintegrating;
  final Duration duration;
  final VoidCallback onDisintegrated;

  const ThanosSnapEffect({
    super.key,
    required this.child,
    required this.isDisintegrating,
    this.duration = const Duration(milliseconds: 1400),
    required this.onDisintegrated,
  });

  @override
  State<ThanosSnapEffect> createState() => _ThanosSnapEffectState();
}

class _ThanosSnapEffectState extends State<ThanosSnapEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _collapseAnimation;
  final List<_AshParticle> _particles = [];
  final Random _random = Random();
  bool _particlesGenerated = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    // Animazione di chiusura morbida dell'altezza negli ultimi momenti (ultimi 30%)
    _collapseAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.70, 1.0, curve: Curves.easeInOutCubic),
      ),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onDisintegrated();
      }
    });

    if (widget.isDisintegrating) {
      _startDisintegration();
    }
  }

  @override
  void didUpdateWidget(covariant ThanosSnapEffect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isDisintegrating && !oldWidget.isDisintegrating) {
      _startDisintegration();
    }
  }

  void _startDisintegration() {
    if (!_particlesGenerated) {
      _generateParticles();
      _particlesGenerated = true;
    }
    _controller.forward(from: 0.0);
  }

  void _generateParticles() {
    _particles.clear();
    const int count = 220; // Densita ottimale per fluidita costante a 60 fps

    final List<Color> palette = [
      const Color(0xFF94A3B8), // Cenere chiara
      const Color(0xFF64748B), // Cenere media
      const Color(0xFF475569), // Grigio fumo
      const Color(0xFF334155), // Carbone
      const Color(0xFF1E293B), // Cenere scura
      const Color(0xFFA855F7), // Polvere cosmica violacea FantaEventi
      const Color(0xFFC084FC), // Scintilla lilla
      const Color(0xFFF59E0B), // Scintilla dorata
      const Color(0xFFFACC15), // Bagliore ambrato
    ];

    for (int i = 0; i < count; i++) {
      final double rx = _random.nextDouble();
      final double ry = _random.nextDouble();

      // Scaglionamento da sinistra a destra: la sinistra si dissolve prima
      final double delay = (rx * 0.45) + (_random.nextDouble() * 0.15);

      _particles.add(
        _AshParticle(
          relativeX: rx,
          relativeY: ry,
          size: 1.5 + (_random.nextDouble() * 2.8),
          speedX: 35.0 + (_random.nextDouble() * 85.0), // Vento verso destra
          speedY: -(50.0 + (_random.nextDouble() * 120.0)), // Salita verso l'alto
          flutterFreq: 2.0 + (_random.nextDouble() * 4.0),
          flutterAmp: 4.0 + (_random.nextDouble() * 12.0),
          rotationSpeed: (_random.nextDouble() - 0.5) * 6.0,
          color: palette[_random.nextInt(palette.length)],
          delay: delay.clamp(0.0, 0.65),
          isSparkle: _random.nextDouble() < 0.25,
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isDisintegrating && _controller.isDismissed) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final double progress = _controller.value;

        // Dissolvenza a onda da sinistra verso destra
        final double waveFront = (progress * 1.35) - 0.15;
        const double waveWidth = 0.30;

        final double stop1 = (waveFront - waveWidth).clamp(0.0, 1.0);
        final double stop2 = waveFront.clamp(0.0, 1.0);

        // Movimento leggero di disintegrazione del corpo (deriva verso l'alto/destra)
        final double cardOffsetX = progress * 14.0;
        final double cardOffsetY = -progress * 18.0;
        final double cardOpacity = (1.0 - progress * 1.15).clamp(0.0, 1.0);

        return SizeTransition(
          sizeFactor: _collapseAnimation,
          axisAlignment: -1.0,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Corpo della Card che si sgretola ed erode da sinistra a destra
              Transform.translate(
                offset: Offset(cardOffsetX, cardOffsetY),
                child: Opacity(
                  opacity: cardOpacity,
                  child: ShaderMask(
                    shaderCallback: (Rect bounds) {
                      return LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: const [
                          Colors.transparent,
                          Colors.transparent,
                          Colors.white,
                          Colors.white,
                        ],
                        stops: [
                          0.0,
                          stop1,
                          stop2,
                          1.0,
                        ],
                      ).createShader(bounds);
                    },
                    blendMode: BlendMode.dstIn,
                    child: widget.child,
                  ),
                ),
              ),

              // Nuvola di particelle di cenere, fumo e scintille su Canvas
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _AshParticlePainter(
                      particles: _particles,
                      progress: progress,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AshParticle {
  final double relativeX;
  final double relativeY;
  final double size;
  final double speedX;
  final double speedY;
  final double flutterFreq;
  final double flutterAmp;
  final double rotationSpeed;
  final Color color;
  final double delay;
  final bool isSparkle;

  _AshParticle({
    required this.relativeX,
    required this.relativeY,
    required this.size,
    required this.speedX,
    required this.speedY,
    required this.flutterFreq,
    required this.flutterAmp,
    required this.rotationSpeed,
    required this.color,
    required this.delay,
    required this.isSparkle,
  });
}

class _AshParticlePainter extends CustomPainter {
  final List<_AshParticle> particles;
  final double progress;

  _AshParticlePainter({
    required this.particles,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (particles.isEmpty || size.width == 0 || size.height == 0) return;

    final Paint paint = Paint()..style = PaintingStyle.fill;

    for (final p in particles) {
      if (progress < p.delay) continue;

      final double particleLife = ((progress - p.delay) / (1.0 - p.delay)).clamp(0.0, 1.0);
      if (particleLife >= 1.0) continue;

      // Coordinate di partenza
      final double startX = p.relativeX * size.width;
      final double startY = p.relativeY * size.height;

      // Traiettoria fisica con vento sinusoidale
      final double flutter = sin(particleLife * p.flutterFreq * pi) * p.flutterAmp;
      final double currentX = startX + (p.speedX * particleLife) + flutter;
      final double currentY = startY + (p.speedY * particleLife);

      // Dissolvenza e rimpicciolimento progressivo
      final double alpha = (1.0 - particleLife).clamp(0.0, 1.0);
      final double currentSize = p.size * (1.0 - (particleLife * 0.45));

      paint.color = p.color.withValues(alpha: alpha);

      if (p.isSparkle) {
        // Scintilla ambrata brillante a diamante
        canvas.save();
        canvas.translate(currentX, currentY);
        canvas.rotate(particleLife * p.rotationSpeed * pi);
        final rect = Rect.fromCenter(center: Offset.zero, width: currentSize, height: currentSize);
        canvas.drawRect(rect, paint);
        canvas.restore();
      } else {
        // Granello di cenere arrotondato
        canvas.drawCircle(Offset(currentX, currentY), currentSize / 2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AshParticlePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
