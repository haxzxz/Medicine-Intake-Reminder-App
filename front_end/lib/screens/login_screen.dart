import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  bool _loadingGoogle = false;
  bool _loadingEmail = false;
  bool _creatingAccount = false;
  bool _showPassword = false;
  String? _errorMsg;
  String? _infoMsg;
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
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
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _loadingGoogle = true;
      _errorMsg = null;
      _infoMsg = null;
    });
    try {
      final cred = await AuthService.signInWithGoogle();
      if (cred == null && mounted) {
        setState(() => _loadingGoogle = false);
      }
    } on FirebaseAuthException catch (e) {
      _showError(_friendlyError(e.code));
    } catch (_) {
      _showError('Google sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _loadingGoogle = false);
    }
  }

  Future<void> _submitEmail() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      _showError('Enter your email and password.');
      return;
    }
    if (_creatingAccount && password.length < 6) {
      _showError('Password must be at least 6 characters.');
      return;
    }

    setState(() {
      _loadingEmail = true;
      _errorMsg = null;
      _infoMsg = null;
    });

    try {
      if (_creatingAccount) {
        await AuthService.createAccountWithEmail(
          email: email,
          password: password,
          displayName: _nameCtrl.text,
        );
      } else {
        await AuthService.signInWithEmail(email: email, password: password);
      }
    } on FirebaseAuthException catch (e) {
      _showError(_friendlyError(e.code));
    } catch (_) {
      _showError('Email sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _loadingEmail = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      _showError('Enter your email first, then tap reset.');
      return;
    }
    setState(() {
      _loadingEmail = true;
      _errorMsg = null;
      _infoMsg = null;
    });
    try {
      await AuthService.sendPasswordReset(email);
      if (mounted) {
        setState(() => _infoMsg = 'Password reset email sent.');
      }
    } on FirebaseAuthException catch (e) {
      _showError(_friendlyError(e.code));
    } catch (_) {
      _showError('Could not send reset email. Please try again.');
    } finally {
      if (mounted) setState(() => _loadingEmail = false);
    }
  }

  void _showError(String msg) {
    if (mounted) {
      setState(() {
        _errorMsg = msg;
        _infoMsg = null;
      });
    }
  }

  String _friendlyError(String code) {
    switch (code) {
      case 'account-exists-with-different-credential':
        return 'An account already exists with this email. Try a different sign-in method.';
      case 'email-already-in-use':
        return 'An account already exists for this email. Try signing in instead.';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'invalid-credential':
      case 'wrong-password':
        return 'Email or password is incorrect.';
      case 'network-request-failed':
        return 'No internet connection. Please check your network.';
      case 'too-many-requests':
        return 'Too many attempts. Wait a bit, then try again.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
        return 'No account found for this email.';
      case 'weak-password':
        return 'Use a stronger password.';
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
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: size.height -
                    MediaQuery.of(context).padding.top -
                    MediaQuery.of(context).padding.bottom,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    const SizedBox(height: 40),

                    // ── Logo & branding ─────────────────────────────────────
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF534AB7).withValues(alpha: 0.12),
                        border: Border.all(
                          color:
                              const Color(0xFF534AB7).withValues(alpha: 0.25),
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
                          color: scheme.onSurface.withValues(alpha: 0.5)),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 28),

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

                    const SizedBox(height: 32),

                    // ── Sign-in buttons ─────────────────────────────────────
                    Text('Sign in to continue',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.4),
                            letterSpacing: 0.5)),
                    const SizedBox(height: 16),

                    _buildEmailForm(scheme),
                    const SizedBox(height: 16),

                    Row(children: [
                      Expanded(
                        child: Divider(
                          color: scheme.outlineVariant.withValues(alpha: 0.6),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'or',
                          style: TextStyle(
                            color: scheme.onSurface.withValues(alpha: 0.4),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Divider(
                          color: scheme.outlineVariant.withValues(alpha: 0.6),
                        ),
                      ),
                    ]),
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
                    if (_errorMsg != null || _infoMsg != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: _errorMsg != null
                              ? scheme.errorContainer
                              : const Color(0xFFEAF7F1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(children: [
                          Icon(
                            _errorMsg != null
                                ? Icons.error_outline
                                : Icons.mark_email_read_outlined,
                            size: 16,
                            color: _errorMsg != null
                                ? scheme.onErrorContainer
                                : const Color(0xFF1D9E75),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_errorMsg ?? _infoMsg!,
                                style: TextStyle(
                                    color: _errorMsg != null
                                        ? scheme.onErrorContainer
                                        : const Color(0xFF1D9E75),
                                    fontSize: 13)),
                          ),
                        ]),
                      ),
                    ],

                    const SizedBox(height: 28),

                    // Terms note
                    Text(
                      'By continuing, you agree to our Terms of Service\nand Privacy Policy.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.35),
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

  Widget _buildEmailForm(ColorScheme scheme) {
    final busy = _loadingEmail || _loadingGoogle;
    return Column(children: [
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: _creatingAccount
            ? Padding(
                key: const ValueKey('name'),
                padding: const EdgeInsets.only(bottom: 10),
                child: _AuthField(
                  controller: _nameCtrl,
                  hintText: 'Name',
                  icon: Icons.person_outline,
                  textInputAction: TextInputAction.next,
                  enabled: !busy,
                ),
              )
            : const SizedBox.shrink(key: ValueKey('no-name')),
      ),
      _AuthField(
        controller: _emailCtrl,
        hintText: 'Email',
        icon: Icons.mail_outline,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        enabled: !busy,
      ),
      const SizedBox(height: 10),
      _AuthField(
        controller: _passwordCtrl,
        hintText: 'Password',
        icon: Icons.lock_outline,
        obscureText: !_showPassword,
        enabled: !busy,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _loadingEmail ? null : _submitEmail(),
        trailing: IconButton(
          tooltip: _showPassword ? 'Hide password' : 'Show password',
          onPressed: () => setState(() => _showPassword = !_showPassword),
          icon: Icon(
            _showPassword ? Icons.visibility_off : Icons.visibility,
            size: 20,
            color: scheme.onSurface.withValues(alpha: 0.45),
          ),
        ),
      ),
      const SizedBox(height: 12),
      _SocialButton(
        onTap: busy ? null : _submitEmail,
        isLoading: _loadingEmail,
        label: _creatingAccount ? 'Create account' : 'Sign in with email',
        logo: Icon(
          _creatingAccount
              ? Icons.person_add_alt_1_rounded
              : Icons.login_rounded,
          color: Colors.white,
          size: 20,
        ),
        backgroundColor: const Color(0xFF534AB7),
        textColor: Colors.white,
        borderColor: const Color(0xFF534AB7),
        shadow: false,
      ),
      const SizedBox(height: 10),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: busy
                ? null
                : () {
                    setState(() {
                      _creatingAccount = !_creatingAccount;
                      _errorMsg = null;
                      _infoMsg = null;
                    });
                  },
            child: Text(
              _creatingAccount ? 'Use existing account' : 'Create account',
            ),
          ),
          TextButton(
            onPressed: busy ? null : _resetPassword,
            child: const Text('Reset password'),
          ),
        ],
      ),
    ]);
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
        color: const Color(0xFF534AB7).withValues(alpha: 0.08),
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
  final bool shadow;

  const _SocialButton({
    required this.onTap,
    required this.isLoading,
    required this.label,
    required this.logo,
    required this.backgroundColor,
    required this.textColor,
    required this.borderColor,
    this.shadow = true,
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
            boxShadow: shadow
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
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

class _AuthField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final bool enabled;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Widget? trailing;

  const _AuthField({
    required this.controller,
    required this.hintText,
    required this.icon,
    this.enabled = true,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: trailing,
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
    canvas.drawLine(Offset(cx, cy), Offset(cx + r - 1.75, cy), barPaint);
  }

  @override
  bool shouldRepaint(_) => false;
}
