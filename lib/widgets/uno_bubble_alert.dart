// lib/widgets/uno_bubble_alert.dart
import 'package:flutter/material.dart';

class UnoBubbleAlert extends StatelessWidget {
  final String message;
  final VoidCallback onTap;
  final Color accentColor;

  const UnoBubbleAlert({
    super.key,
    required this.message,
    required this.onTap,
    this.accentColor = Colors.amber,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 100, // Posicionada en la parte superior central de la mesa
      left: 0,
      right: 0,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 250),
            builder: (context, value, child) {
              return Transform.scale(
                scale: value,
                child: Opacity(
                  opacity: value,
                  child: child,
                ),
              );
            },
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E).withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline, color: accentColor, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.close, color: Colors.white54, size: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}