import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum AppToastType { success, error, warning, info }

class AppToast {
  static void showSuccess(
    BuildContext context,
    String title, [
    String? message,
    Duration duration = const Duration(seconds: 3),
  ]) {
    show(
      context,
      title: title,
      message: message,
      type: AppToastType.success,
      duration: duration,
    );
  }

  static void showError(
    BuildContext context,
    String title, [
    String? message,
    Duration duration = const Duration(seconds: 4),
  ]) {
    show(
      context,
      title: title,
      message: message,
      type: AppToastType.error,
      duration: duration,
    );
  }

  static void showWarning(
    BuildContext context,
    String title, [
    String? message,
    Duration duration = const Duration(seconds: 3),
  ]) {
    show(
      context,
      title: title,
      message: message,
      type: AppToastType.warning,
      duration: duration,
    );
  }

  static void showInfo(
    BuildContext context,
    String title, [
    String? message,
    Duration duration = const Duration(seconds: 3),
  ]) {
    show(
      context,
      title: title,
      message: message,
      type: AppToastType.info,
      duration: duration,
    );
  }

  static void show(
    BuildContext context, {
    required String title,
    String? message,
    required AppToastType type,
    Duration duration = const Duration(seconds: 3),
  }) {
    Color accentColor;
    IconData icon;

    switch (type) {
      case AppToastType.success:
        accentColor = const Color(0xFF10B981);
        icon = Icons.check_circle_rounded;
        break;
      case AppToastType.error:
        accentColor = const Color(0xFFEF4444);
        icon = Icons.error_rounded;
        break;
      case AppToastType.warning:
        accentColor = const Color(0xFFFACC15);
        icon = Icons.warning_amber_rounded;
        break;
      case AppToastType.info:
        accentColor = const Color(0xFF8B5CF6);
        icon = Icons.info_rounded;
        break;
    }

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        duration: duration,
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accentColor.withValues(alpha: 0.6), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: accentColor.withValues(alpha: 0.18),
                blurRadius: 16,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accentColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                    if (message != null && message.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        message.trim(),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFFCBD5E1),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
