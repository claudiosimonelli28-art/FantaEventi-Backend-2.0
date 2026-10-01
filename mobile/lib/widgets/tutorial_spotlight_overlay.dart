import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';

class InteractiveSpotlightOverlay extends StatefulWidget {
  final GlobalKey targetKey;
  final String stepTag;
  final String title;
  final String description;
  final VoidCallback? onSkip;
  final VoidCallback? onTargetTapped;
  final bool isTargetRound;
  final double padding;

  const InteractiveSpotlightOverlay({
    super.key,
    required this.targetKey,
    required this.stepTag,
    required this.title,
    required this.description,
    this.onSkip,
    this.onTargetTapped,
    this.isTargetRound = false,
    this.padding = 6.0,
  });

  @override
  State<InteractiveSpotlightOverlay> createState() => _InteractiveSpotlightOverlayState();
}

class _InteractiveSpotlightOverlayState extends State<InteractiveSpotlightOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _bounceAnimation;
  Animation<double>? _routeAnim;
  Animation<double>? _secondaryRouteAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _bounceAnimation = Tween<double>(begin: 0.0, end: 8.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleCheck());
  }

  void _scheduleCheck() {
    if (!mounted) return;
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) setState(() {});
    });
    Future.delayed(const Duration(milliseconds: 280), () {
      if (mounted) setState(() {});
    });
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      if (route.animation != _routeAnim) {
        _routeAnim?.removeListener(_onRouteTick);
        _routeAnim = route.animation;
        _routeAnim?.addListener(_onRouteTick);
      }
      if (route.secondaryAnimation != _secondaryRouteAnim) {
        _secondaryRouteAnim?.removeListener(_onRouteTick);
        _secondaryRouteAnim = route.secondaryAnimation;
        _secondaryRouteAnim?.addListener(_onRouteTick);
      }
    }
  }

  void _onRouteTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _routeAnim?.removeListener(_onRouteTick);
    _secondaryRouteAnim?.removeListener(_onRouteTick);
    _pulseController.dispose();
    super.dispose();
  }

  Rect? _calculateTargetRect() {
    final renderBox = widget.targetKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) return null;
    final size = renderBox.size;
    if (size.width < 10 || size.height < 10) return null;
    final offset = renderBox.localToGlobal(Offset.zero);
    return Rect.fromLTWH(
      offset.dx - widget.padding,
      offset.dy - widget.padding,
      size.width + (widget.padding * 2),
      size.height + (widget.padding * 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final targetRect = _calculateTargetRect();
        final screenSize = MediaQuery.of(context).size;

        // Se il target non è ancora renderizzato, attendiamo un frame
        if (targetRect == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
          return const SizedBox.shrink();
        }

        final isTargetRound = widget.isTargetRound || (targetRect.width - targetRect.height).abs() < 12;
        final double holeRadius = (targetRect.width > targetRect.height ? targetRect.width : targetRect.height) / 2;
        final Offset center = targetRect.center;
        final Rect holeRect = isTargetRound
            ? Rect.fromCircle(center: center, radius: holeRadius)
            : targetRect;

        final isTargetAtBottom = holeRect.center.dy > screenSize.height / 2;

        return SpotlightHitTestBlocker(
          targetRect: holeRect,
          isRound: isTargetRound,
          hasDirectTapHandler: widget.onTargetTapped != null,
          child: Stack(
            children: [
              // 1. MASCHERA SCURA CON RITAGLIO CIRCOLARE / ROTONDO PERFETTO (Senza fori quadrati!)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: SpotlightHolePainter(
                      targetRect: holeRect,
                      isRound: isTargetRound,
                      backdropColor: Colors.black.withValues(alpha: 0.82),
                    ),
                  ),
                ),
              ),

              // 2. CORNICE NEON PULSANTE SUL TARGET (Visiva, identica al ritaglio)
              Positioned(
                left: isTargetRound ? (center.dx - holeRadius) : targetRect.left,
                top: isTargetRound ? (center.dy - holeRadius) : targetRect.top,
                width: isTargetRound ? (holeRadius * 2) : targetRect.width,
                height: isTargetRound ? (holeRadius * 2) : targetRect.height,
                child: IgnorePointer(
                  child: ScaleTransition(
                    scale: _pulseAnimation,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: isTargetRound ? BoxShape.circle : BoxShape.rectangle,
                        borderRadius: isTargetRound ? null : BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFFACC15), width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFACC15).withValues(alpha: 0.65),
                            blurRadius: 18,
                            spreadRadius: 3,
                          ),
                          BoxShadow(
                            color: const Color(0xFF9333EA).withValues(alpha: 0.5),
                            blurRadius: 26,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // 3. FORO ATTIVO: Tap handler dedicato istantaneo sul target
              if (widget.onTargetTapped != null)
                Positioned(
                  left: isTargetRound ? (center.dx - holeRadius) : targetRect.left,
                  top: isTargetRound ? (center.dy - holeRadius) : targetRect.top,
                  width: isTargetRound ? (holeRadius * 2) : targetRect.width,
                  height: isTargetRound ? (holeRadius * 2) : targetRect.height,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onTargetTapped,
                    child: Container(color: Colors.transparent),
                  ),
                ),

              // 4. FRECCIA ANIMATA DI PUNTAMENTO VERSO IL TARGET
              Positioned(
                left: (holeRect.center.dx - 20).clamp(16.0, screenSize.width - 56.0),
                top: isTargetAtBottom
                    ? (holeRect.top - 48).clamp(0.0, screenSize.height)
                    : (holeRect.bottom + 8).clamp(0.0, screenSize.height),
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _bounceAnimation,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(0, isTargetAtBottom ? -_bounceAnimation.value : _bounceAnimation.value),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFACC15),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFACC15).withValues(alpha: 0.7),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Icon(
                        isTargetAtBottom ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                        color: const Color(0xFF0F172A),
                        size: 22,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // 5. FLOATING GUIDE CARD ELEGANTE (Posizionata in modo opposto al target)
          Positioned(
            left: 16,
            right: 16,
            top: isTargetAtBottom ? MediaQuery.of(context).padding.top + 20 : null,
            bottom: !isTargetAtBottom ? MediaQuery.of(context).padding.bottom + 24 : null,
            child: Material(
              type: MaterialType.transparency,
              child: DefaultTextStyle(
                style: const TextStyle(decoration: TextDecoration.none),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFFACC15).withValues(alpha: 0.65), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.7),
                        blurRadius: 25,
                        spreadRadius: 2,
                      ),
                      BoxShadow(
                        color: const Color(0xFF9333EA).withValues(alpha: 0.25),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFACC15).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFFACC15).withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              widget.stepTag.toUpperCase(),
                              style: GoogleFonts.poppins(
                                color: const Color(0xFFFACC15),
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                letterSpacing: 0.8,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF9333EA).withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Text('✨', style: TextStyle(fontSize: 12)),
                                const SizedBox(width: 4),
                                Text(
                                  'Guida',
                                  style: GoogleFonts.poppins(
                                    color: const Color(0xFFC084FC),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.title,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          height: 1.25,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.description,
                        style: GoogleFonts.inter(
                          color: const Color(0xFFCBD5E1),
                          fontSize: 13,
                          height: 1.45,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.touch_app_rounded, color: Color(0xFFFACC15), size: 18),
                              const SizedBox(width: 6),
                              Text(
                                'Tocca l\'icona evidenziata!',
                                style: GoogleFonts.poppins(
                                  color: const Color(0xFFFACC15),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                          if (widget.onSkip != null)
                            TextButton(
                              onPressed: widget.onSkip,
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF94A3B8),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                visualDensity: VisualDensity.compact,
                              ),
                              child: Text(
                                'Salta Tutorial',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
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

/// Disegna la maschera scura ritagliando perfettamente la forma del target (senza spigoli quadrati)
class SpotlightHolePainter extends CustomPainter {
  final Rect targetRect;
  final bool isRound;
  final Color backdropColor;

  SpotlightHolePainter({
    required this.targetRect,
    required this.isRound,
    required this.backdropColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final screenPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final Path holePath = Path();
    if (isRound) {
      holePath.addOval(targetRect);
    } else {
      holePath.addRRect(RRect.fromRectAndRadius(targetRect, const Radius.circular(16)));
    }

    final combinedPath = Path.combine(PathOperation.difference, screenPath, holePath);
    final paint = Paint()
      ..color = backdropColor
      ..style = PaintingStyle.fill;

    canvas.drawPath(combinedPath, paint);
  }

  @override
  bool shouldRepaint(covariant SpotlightHolePainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
        oldDelegate.isRound != isRound ||
        oldDelegate.backdropColor != backdropColor;
  }
}

/// Blocco hit-test che assorbe i tap fuori dal foro dello spotlight, ma lascia passare
/// liberamente i tap che colpiscono esattamente l'elemento evidenziato!
class SpotlightHitTestBlocker extends SingleChildRenderObjectWidget {
  final Rect targetRect;
  final bool isRound;
  final bool hasDirectTapHandler;

  const SpotlightHitTestBlocker({
    super.key,
    required this.targetRect,
    required this.isRound,
    required this.hasDirectTapHandler,
    super.child,
  });

  @override
  RenderSpotlightHitTestBlocker createRenderObject(BuildContext context) {
    return RenderSpotlightHitTestBlocker(
      targetRect: targetRect,
      isRound: isRound,
      hasDirectTapHandler: hasDirectTapHandler,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderSpotlightHitTestBlocker renderObject) {
    renderObject
      ..targetRect = targetRect
      ..isRound = isRound
      ..hasDirectTapHandler = hasDirectTapHandler;
  }
}

class RenderSpotlightHitTestBlocker extends RenderProxyBox {
  Rect targetRect;
  bool isRound;
  bool hasDirectTapHandler;

  RenderSpotlightHitTestBlocker({
    required this.targetRect,
    required this.isRound,
    required this.hasDirectTapHandler,
  });

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    // 1. Verifichiamo se il punto del tocco cade dentro l'apertura dello spotlight
    bool isInsideHole;
    if (isRound) {
      final center = targetRect.center;
      final radius = (targetRect.width > targetRect.height ? targetRect.width : targetRect.height) / 2;
      final distance = (position - center).distance;
      isInsideHole = distance <= radius;
    } else {
      isInsideHole = targetRect.contains(position);
    }

    if (isInsideHole) {
      if (hasDirectTapHandler) {
        // C'è un GestureDetector dedicato sul foro: inoltriamo ai figli e catturiamo l'evento
        return super.hitTestChildren(result, position: position);
      } else {
        // Nessun handler dedicato: lasciamo passare il tocco direttamente ai widget sottostanti!
        return false;
      }
    }

    // 2. Tocco fuori dallo spotlight: prima testiamo i figli interattivi (es. la card con il tasto 'Salta Tutorial')
    if (super.hitTestChildren(result, position: position)) {
      return true;
    }

    // 3. Tocco fuori dallo spotlight sul backdrop scuro: assorbiamo il tocco per proteggere il gioco
    result.add(BoxHitTestEntry(this, position));
    return true;
  }
}

/// Banner elegante da mostrare in cima alle schermate secondarie durante il tutorial
class TutorialStepBanner extends StatelessWidget {
  final String stepTag;
  final String title;
  final String description;
  final VoidCallback? onSkip;

  const TutorialStepBanner({
    super.key,
    required this.stepTag,
    required this.title,
    required this.description,
    this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: DefaultTextStyle(
        style: const TextStyle(decoration: TextDecoration.none),
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 18),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFFACC15).withValues(alpha: 0.65), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFACC15).withValues(alpha: 0.15),
                blurRadius: 14,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFACC15).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      stepTag.toUpperCase(),
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFFACC15),
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  if (onSkip != null)
                    GestureDetector(
                      onTap: onSkip,
                      child: Text(
                        'Salta',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF94A3B8),
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  height: 1.4,
                  color: const Color(0xFFCBD5E1),
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
