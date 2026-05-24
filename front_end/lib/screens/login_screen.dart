import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  bool _loadingGoogle = false;
  String? _errorMsg;
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() { _loadingGoogle = true; _errorMsg = null; });
    try {
      final cred = await AuthService.signInWithGoogle();
      if (cred != null && mounted) _goHome();
    } on FirebaseAuthException catch (e) {
      _showError(_friendlyError(e.code));
    } catch (_) {
      _showError('Google sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _loadingGoogle = false);
    }
  }

  void _goHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  void _showError(String msg) {
    if (mounted) setState(() => _errorMsg = msg);
  }

  String _friendlyError(String code) {
    switch (code) {
      case 'account-exists-with-different-credential':
        return 'An account already exists with this email. Try a different sign-in method.';
      case 'network-request-failed':
        return 'No internet connection. Please check your network.';
      case 'user-disabled':
        return 'This account has been disabled.';
      default:
        return 'Sign-in failed ($code). Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          child: SingleChildScrollView(
            child: SizedBox(
              height: size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    const Spacer(flex: 2),

                    // ── Logo & branding ─────────────────────────────────────
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF534AB7).withOpacity(0.12),
                        border: Border.all(
                          color: const Color(0xFF534AB7).withOpacity(0.25),
                          width: 1.5,
                        ),
                      ),
                      child: const Center(
                        child: Text('Z',
                            style: TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF534AB7))),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('Zam',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurface)),
                    const SizedBox(height: 6),
                    Text(
                      'Your AI medicine reminder assistant',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurface.withOpacity(0.5)),
                      textAlign: TextAlign.center,
                    ),

                    const Spacer(flex: 2),

                    // ── Pill illustration ───────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _PillChip('💊 Smart reminders'),
                        const SizedBox(width: 8),
                        _PillChip('🎙️ Voice input'),
                        const SizedBox(width: 8),
                        _PillChip('🤖 AI powered'),
                      ],
                    ),

                    const Spacer(flex: 3),

                    // ── Sign-in buttons ─────────────────────────────────────
                    Text('Sign in to continue',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface.withOpacity(0.4),
                            letterSpacing: 0.5)),
                    const SizedBox(height: 16),

                    // Google
                    _SocialButton(
                      onTap: _loadingGoogle ? null : _signInWithGoogle,
                      isLoading: _loadingGoogle,
                      label: 'Continue with Google',
                      logo: _GoogleLogo(),
                      backgroundColor: Colors.white,
                      textColor: const Color(0xFF1F1F1F),
                      borderColor: const Color(0xFFDADADA),
                    ),

                    // Error message
                    if (_errorMsg != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(children: [
                          Icon(Icons.error_outline,
                              size: 16, color: scheme.onErrorContainer),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_errorMsg!,
                                style: TextStyle(
                                    color: scheme.onErrorContainer,
                                    fontSize: 13)),
                          ),
                        ]),
                      ),
                    ],

                    const Spacer(flex: 2),

                    // Terms note
                    Text(
                      'By continuing, you agree to our Terms of Service\nand Privacy Policy.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withOpacity(0.35),
                          fontSize: 11),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
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

// ── Helpers ────────────────────────────────────────────────────────────────

class _PillChip extends StatelessWidget {
  final String label;
  const _PillChip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF534AB7).withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF534AB7))),
    );
  }
}

class _SocialButton extends StatelessWidget {
  final VoidCallback? onTap;
  final bool isLoading;
  final String label;
  final Widget logo;
  final Color backgroundColor;
  final Color textColor;
  final Color borderColor;

  const _SocialButton({
    required this.onTap,
    required this.isLoading,
    required this.label,
    required this.logo,
    required this.backgroundColor,
    required this.textColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: onTap == null ? 0.6 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: isLoading
              ? Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: textColor,
                    ),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    logo,
                    const SizedBox(width: 10),
                    Text(label,
                        style: TextStyle(
                            color: textColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
        ),
      ),
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    final segments = [
      (0.0, 0.5, const Color(0xFF4285F4)),
      (0.5, 0.75, const Color(0xFF34A853)),
      (0.75, 0.875, const Color(0xFFFBBC05)),
      (0.875, 1.0, const Color(0xFFEA4335)),
    ];

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    for (final seg in segments) {
      paint.color = seg.$3;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r - 1.75),
        seg.$1 * 2 * 3.14159,
        (seg.$2 - seg.$1) * 2 * 3.14159,
        false,
        paint,
      );
    }

    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        Offset(cx, cy), Offset(cx + r - 1.75, cy), barPaint);
  }

  @override
  bool shouldRepaint(_) => false;
}
