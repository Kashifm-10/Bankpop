import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mon/routes.dart';
import 'package:mon/services/account.dart';
import 'package:mon/services/password.dart';

/// The one screen that replaces a password.
///
/// Two ways in:
///  * after signing in with the temporary password from a reset mail
///    ([forced] true) - the app will not go any further until a real password
///    is chosen, and this is where the real password actually changes;
///  * from the profile ([forced] false) - the current password is asked for
///    first, so a phone left unlocked cannot be re-keyed.
///
/// Both ask for the new password twice, check it against [PasswordRules], and
/// refuse the two passwords the account currently accepts. Typing it twice is
/// not decoration: there is no server to send a "was that right?" mail, and a
/// typo here would lock the account out on the next launch.
class SetPasswordScreen extends StatefulWidget {
  const SetPasswordScreen({super.key, required this.forced});

  /// True when this is the step after a temporary-password sign-in.
  final bool forced;

  @override
  State<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends State<SetPasswordScreen> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _newPassword = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  bool _busy = false;
  bool _done = false;
  bool _signedIn = true;
  bool _showCurrent = false;
  bool _showNew = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final bool signedIn = await Account.isSignedIn();
    if (mounted) setState(() => _signedIn = signedIn);
  }

  @override
  void dispose() {
    _current.dispose();
    _newPassword.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;

    final String newPassword = _newPassword.text;
    final String? problem = PasswordRules.problem(newPassword);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    if (newPassword != _confirm.text) {
      setState(() => _error = 'The two passwords do not match.');
      return;
    }
    if (!widget.forced && _current.text.isEmpty) {
      setState(() => _error = 'Enter your current password.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final String? failure = widget.forced
        ? await Account.setNewPassword(newPassword: newPassword)
        : await Account.changePassword(
            currentPassword: _current.text,
            newPassword: newPassword,
          );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = failure;
      _done = failure == null;
    });
  }

  void _leave() {
    if (widget.forced) {
      context.go(AppRoutes.home);
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.profile);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8E1),
      appBar: AppBar(
        backgroundColor: const Color(0xFF689F38),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: !widget.forced,
        title: Text(
          widget.forced ? 'Choose a new password' : 'Change password',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 30),
          children: <Widget>[
            if (!_signedIn)
              const _Notice(
                icon: Icons.lock_outline,
                text: 'Sign in before changing the password.',
              )
            else if (_done)
              _Success(
                forced: widget.forced,
                onLeave: _leave,
              )
            else ...<Widget>[
              Text(
                widget.forced
                    ? 'You signed in with the temporary password from your '
                        'email. Choose the password you want to keep - your '
                        'real password changes now, and the temporary one stops '
                        'working.'
                    : 'Your current password is needed first. The new one has '
                        'to be different from the password you already use.',
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: Color(0xFF558B2F),
                ),
              ),
              const SizedBox(height: 20),
              if (!widget.forced) ...<Widget>[
                _field(
                  controller: _current,
                  label: 'Current password',
                  visible: _showCurrent,
                  onToggle: () => setState(() => _showCurrent = !_showCurrent),
                  action: TextInputAction.next,
                ),
                const SizedBox(height: 14),
              ],
              _field(
                controller: _newPassword,
                label: 'New password',
                visible: _showNew,
                onToggle: () => setState(() => _showNew = !_showNew),
                action: TextInputAction.next,
              ),
              const SizedBox(height: 8),
              const Text(
                PasswordRules.hint,
                style: TextStyle(fontSize: 11.5, color: Color(0xFF7CB342)),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _confirm,
                obscureText: _showNew,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                decoration: _decoration(
                  label: 'Type the new password again',
                  icon: Icons.check_circle_outline,
                ),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFC62828),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 22),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _busy ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF689F38),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFA5D6A7),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Save new password',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required bool visible,
    required VoidCallback onToggle,
    TextInputAction action = TextInputAction.done,
  }) {
    return TextField(
      controller: controller,
      obscureText: !visible,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: action,
      decoration: _decoration(
        label: label,
        icon: Icons.lock_outline,
      ).copyWith(
        suffixIcon: IconButton(
          tooltip: visible ? 'Hide password' : 'Show password',
          icon: Icon(
            visible ? Icons.visibility_off : Icons.visibility,
            size: 20,
            color: const Color(0xFF689F38),
          ),
          onPressed: onToggle,
        ),
      ),
    );
  }

  InputDecoration _decoration({required String label, required IconData icon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: const Color(0xFF689F38)),
      filled: true,
      fillColor: const Color(0xFFE8F5E9),
      labelStyle: const TextStyle(color: Color(0xFF2E7D32)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF689F38)),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Icon(icon, size: 46, color: const Color(0xFF689F38)),
        const SizedBox(height: 12),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: Color(0xFF558B2F)),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => context.go(AppRoutes.auth),
          child: const Text(
            'Go to sign in',
            style: TextStyle(color: Color(0xFF2E7D32)),
          ),
        ),
      ],
    );
  }
}

class _Success extends StatelessWidget {
  const _Success({required this.forced, required this.onLeave});

  final bool forced;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        const Icon(Icons.check_circle_outline,
            size: 52, color: Color(0xFF2E7D32)),
        const SizedBox(height: 12),
        const Text(
          'Password updated',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.bold,
            color: Color(0xFF33691E),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          forced
              ? 'Your real password has been replaced and the temporary one no '
                  'longer works.'
              : 'Sign in with the new password the next time you open BankPop.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13.5,
            height: 1.4,
            color: Color(0xFF558B2F),
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: onLeave,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF689F38),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            forced ? 'Continue to BankPop' : 'Back to profile',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
      ],
    );
  }
}
