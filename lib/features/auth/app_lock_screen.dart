import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app/theme.dart';
import '../../services/auth/app_lock_service.dart';

class AppLockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  final bool allowBiometrics;
  final bool allowDevicePin;

  const AppLockScreen({
    super.key,
    required this.onUnlocked,
    this.allowBiometrics = true,
    this.allowDevicePin = true,
  });

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  bool _isAuthenticating = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    );

    // Auto-prompt authentication when screen appears
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerAuthentication();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _triggerAuthentication() async {
    if (_isAuthenticating) return;
    setState(() {
      _isAuthenticating = true;
    });

    final bool success = await AppLockService.authenticate(
      allowBiometrics: widget.allowBiometrics,
      allowDeviceCredentials: widget.allowDevicePin,
      reason: 'Unlock Mine',
    );

    if (!mounted) return;

    setState(() {
      _isAuthenticating = false;
    });

    if (success) {
      widget.onUnlocked();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B141B),
        body: Stack(
        children: [
          // Background ambient gradient glow
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    MineTheme.primaryTeal.withAlpha(40),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            right: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    MineTheme.accentGreen.withAlpha(25),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Central Lock Content
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(left: 32, right: 32, bottom: 250),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Animated App Icon with pulse and glow
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        final scale = 1.0 + (_pulseAnimation.value * 0.06);
                        final glowAlpha = (50 + (_pulseAnimation.value * 70)).toInt();

                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            // Outer pulsing halo ring
                            Container(
                              width: 124 * scale,
                              height: 124 * scale,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withAlpha(glowAlpha ~/ 8),
                              ),
                            ),
                            // App Icon with glow
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFE53935).withAlpha(glowAlpha),
                                    blurRadius: 28,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: Image.asset(
                                  'assets/icon.png',
                                  width: 86,
                                  height: 86,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 32),

                    // Title
                    Text(
                      'Mine is Locked',
                      style: GoogleFonts.inter(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Simple Unlock Button with Icon
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: _isAuthenticating ? null : _triggerAuthentication,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(15),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: MineTheme.accentGreen.withAlpha(150),
                              width: 1.3,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.lock_open_rounded,
                                color: MineTheme.accentGreen,
                                size: 19,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Unlock',
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
}
