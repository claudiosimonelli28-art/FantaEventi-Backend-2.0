import 'package:flutter/material.dart';
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
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Rect? _calculateTargetRect() {
    final renderBox = widget.targetKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) return null;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    return Rect.fromLTWH(
      offset.dx - widget.padding,
      offset.dy - widget.padding,
      size.width + (widget.padding * 2),
      size.height + (widget.padding * 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final targetRect = _calculateTargetRect();
    final screenSize = MediaQuery.of(context).size;

    // Se il target non è ancora renderizzato, attendiamo un frame
    if (targetRect == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return const SizedBox.shrink();
    }

    final isTargetAtBottom = targetRect.center.dy > screenSize.height / 2;

    return Stack(
      children: [
        // 1. I 4 BOX OSCURANTI ATTUATORI (Lasciano il target scoperto al 100% per i tap!)
        // Box Superiore
        Positioned(
          left: 0,
          top: 0,
          width: screenSize.width,
          height: targetRect.top.clamp(0.0, screenSize.height),
          child: _buildBackdropBlock(),
        ),
        // Box Inferiore
        Positioned(
          left: 0,
          top: targetRect.bottom.clamp(0.0, screenSize.height),
          width: screenSize.width,
          height: (screenSize.height - targetRect.bottom).clamp(0.0, screenSize.height),
          child: _buildBackdropBlock(),
        ),
        // Box Sinistro
        Positioned(
          left: 0,
          top: targetRect.top.clamp(0.0, screenSize.height),
          width: targetRect.left.clamp(0.0, screenSize.width),
          height: targetRect.height,
          child: _buildBackdropBlock(),
        ),
        // Box Destro
        Positioned(
          left: targetRect.right.clamp(0.0, screenSize.width),
          top: targetRect.top.clamp(0.0, screenSize.height),
          width: (screenSize.width - targetRect.right).clamp(0.0, screenSize.width),
          height: targetRect.height,
          child: _buildBackdropBlock(),
        ),

        // 2. CORNICE NEON PULSANTE SUL TARGET (Visiva, lascia passare il tocco al pulsante)
        Positioned(
          left: targetRect.left,
          top: targetRect.top,
          width: targetRect.width,
          height: targetRect.height,
          child: IgnorePointer(
            child: ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(
                    widget.isTargetRound || targetRect.width == targetRect.height ? 100 : 16,
                  ),
                  border: Border.all(color: const Color(0xFFFACC15), width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFACC15).withValues(alpha: 0.6),
                      blurRadius: 16,
                      spreadRadius: 3,
                    ),
                    BoxShadow(
                      color: const Color(0xFF9333EA).withValues(alpha: 0.5),
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // 3. FRECCIA ANIMATA DI PUNTAMENTO VERSO IL TARGET
        Positioned(
          left: (targetRect.center.dx - 20).clamp(16.0, screenSize.width - 56.0),
          top: isTargetAtBottom
              ? (targetRect.top - 46).clamp(0.0, screenSize.height)
              : (targetRect.bottom + 6).clamp(0.0, screenSize.height),
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

        // 4. FLOATING GUIDE CARD ELEGANTE (Posizionata in modo opposto al target)
        Positioned(
          left: 16,
          right: 16,
          top: isTargetAtBottom ? MediaQuery.of(context).padding.top + 20 : null,
          bottom: !isTargetAtBottom ? MediaQuery.of(context).padding.bottom + 24 : null,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFFACC15), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 25,
                  spreadRadius: 4,
                ),
                BoxShadow(
                  color: const Color(0xFF9333EA).withValues(alpha: 0.35),
                  blurRadius: 18,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tag fase
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFACC15).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFACC15)),
                      ),
                      child: Text(
                        widget.stepTag.toUpperCase(),
                        style: GoogleFonts.poppins(
                          color: const Color(0xFFFACC15),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const Text('🎮 GUIDA ATTIVA', style: TextStyle(fontSize: 12, color: Color(0xFFC084FC), fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  widget.title,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.description,
                  style: GoogleFonts.inter(
                    color: const Color(0xFFCBD5E1),
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
                // Azione o Salta
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
      ],
    );
  }

  Widget _buildBackdropBlock() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(milliseconds: 1500),
            backgroundColor: const Color(0xFF1E293B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFFACC15))),
            content: Row(
              children: [
                const Icon(Icons.touch_app_rounded, color: Color(0xFFFACC15), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Tocca l\'elemento evidenziato per proseguire!',
                    style: GoogleFonts.poppins(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      child: Container(
        color: const Color(0xFF0F172A).withValues(alpha: 0.85),
      ),
    );
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
    return Container(
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
        border: Border.all(color: const Color(0xFFFACC15), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFACC15).withValues(alpha: 0.2),
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
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: GoogleFonts.inter(
              fontSize: 12,
              height: 1.4,
              color: const Color(0xFFCBD5E1),
            ),
          ),
        ],
      ),
    );
  }
}
