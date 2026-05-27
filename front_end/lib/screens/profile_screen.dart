import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _photoUrlCtrl = TextEditingController();

  User? get _user => AuthService.currentUser;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _photoUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _changeName() async {
    HapticFeedback.selectionClick();
    _nameCtrl.text = AuthService.displayName;
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change name'),
        content: TextField(
          controller: _nameCtrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Display name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              HapticFeedback.mediumImpact();
              Navigator.pop(dialogContext, _nameCtrl.text);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    await AuthService.updateDisplayName(name);
    if (mounted) setState(() {});
  }

  Future<void> _changePhotoUrl() async {
    HapticFeedback.selectionClick();
    _photoUrlCtrl.text = AuthService.photoUrl ?? '';
    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Profile picture'),
        content: TextField(
          controller: _photoUrlCtrl,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Image URL',
            hintText: 'https://example.com/photo.jpg',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              HapticFeedback.mediumImpact();
              Navigator.pop(dialogContext, _photoUrlCtrl.text);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (url == null || url.trim().isEmpty) return;
    await AuthService.updatePhotoUrl(url);
    if (mounted) setState(() {});
  }

  Future<void> _sendPasswordReset() async {
    HapticFeedback.mediumImpact();
    final email = _user?.email;
    if (email == null || email.isEmpty) {
      _showSnack('This account does not have an email address.');
      return;
    }
    await AuthService.sendPasswordReset(email);
    _showSnack('Password reset email sent to $email.');
  }

  Future<void> _signOut() async {
    HapticFeedback.mediumImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will be returned to the login screen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirm == true) await AuthService.signOut();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = _user;
    final email = user?.email ?? 'No email connected';
    final createdAt = user?.metadata.creationTime;
    final lastSignIn = user?.metadata.lastSignInTime;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _ProfileHeader(
          name: AuthService.displayName,
          email: email,
          photoUrl: AuthService.photoUrl,
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Account',
          children: [
            _ProfileTile(
              icon: Icons.badge_outlined,
              title: 'Display name',
              subtitle: AuthService.displayName,
              onTap: _changeName,
            ),
            _ProfileTile(
              icon: Icons.alternate_email_rounded,
              title: 'Email',
              subtitle: email,
            ),
            _ProfileTile(
              icon: Icons.verified_user_outlined,
              title: 'Sign-in provider',
              subtitle: _providerLabel(user),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _Section(
          title: 'Personalization',
          children: [
            _ProfileTile(
              icon: Icons.add_a_photo_outlined,
              title: 'Profile picture',
              subtitle: AuthService.photoUrl == null
                  ? 'Add a hosted image link'
                  : 'Update hosted image link',
              onTap: _changePhotoUrl,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _Section(
          title: 'Security',
          children: [
            _ProfileTile(
              icon: Icons.lock_reset_rounded,
              title: 'Change password',
              subtitle: 'Send password reset email',
              onTap: _sendPasswordReset,
            ),
            _ProfileTile(
              icon: Icons.logout_rounded,
              title: 'Sign out',
              subtitle: 'Leave this device',
              iconColor: scheme.error,
              onTap: _signOut,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _Section(
          title: 'Details',
          children: [
            _ProfileTile(
              icon: Icons.calendar_month_outlined,
              title: 'Account created',
              subtitle: _dateLabel(createdAt),
            ),
            _ProfileTile(
              icon: Icons.schedule_outlined,
              title: 'Last sign-in',
              subtitle: _dateLabel(lastSignIn),
            ),
            _ProfileTile(
              icon: Icons.fingerprint_rounded,
              title: 'User ID',
              subtitle: user?.uid ?? 'Unavailable',
            ),
          ],
        ),
      ],
    );
  }

  String _providerLabel(User? user) {
    final providers =
        user?.providerData.map((info) => info.providerId).toList();
    if (providers == null || providers.isEmpty) return 'Email';
    if (providers.any((provider) => provider.contains('google'))) {
      return 'Google';
    }
    if (providers.any((provider) => provider.contains('password'))) {
      return 'Email and password';
    }
    return providers.join(', ');
  }

  String _dateLabel(DateTime? date) {
    if (date == null) return 'Unavailable';
    return '${date.month}/${date.day}/${date.year}';
  }
}

class _ProfileHeader extends StatelessWidget {
  final String name;
  final String email;
  final String? photoUrl;

  const _ProfileHeader({
    required this.name,
    required this.email,
    required this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: const Color(0xFF534AB7).withValues(alpha: 0.12),
            backgroundImage: photoUrl == null ? null : NetworkImage(photoUrl!),
            child: photoUrl == null
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'U',
                    style: const TextStyle(
                      color: Color(0xFF534AB7),
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.55),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              color: scheme.onSurface.withValues(alpha: 0.45),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.45)),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? iconColor;
  final VoidCallback? onTap;

  const _ProfileTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: iconColor ?? const Color(0xFF534AB7)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: onTap == null
          ? null
          : Icon(
              Icons.chevron_right_rounded,
              color: scheme.onSurface.withValues(alpha: 0.35),
            ),
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
    );
  }
}
