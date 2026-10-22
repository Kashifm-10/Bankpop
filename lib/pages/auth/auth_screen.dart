import 'package:flutter/material.dart';
import 'package:mon/pages/home.dart';
import 'package:mon/pages/profile_edit.dart';
import 'package:mon/services/account.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The one place an account is created or opened.
///
/// There is no password reset flow: without a server (and without Supabase
/// Auth) there is nobody to send a reset mail. The screen says so, and the
/// account is only ever the key to that player's games, never to money.
class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    this.startWithSignUp = false,
    this.returnOnSuccess = false,
  });

  final bool startWithSignUp;

  /// Opened from a screen that stays put (the profile page): a successful
  /// sign-in pops with `true` instead of replacing the whole stack, so the
  /// player lands back where they were.
  final bool returnOnSuccess;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late bool _isSignUp = widget.startWithSignUp;
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final AuthResult result = _isSignUp
        ? await Account.signUp(
            email: _email.text,
            password: _password.text,
          )
        : await Account.signIn(
            email: _email.text,
            password: _password.text,
          );

    if (!mounted) return;

    if (!result.ok) {
      setState(() {
        _busy = false;
        _error = result.error;
      });
      return;
    }

    setState(() => _busy = false);

    // A brand new account has no name or avatar yet. The same dialog a fresh
    // install has always used collects them, and its Save writes them back to
    // the profile row.
    if (result.created) {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final bool hasName = (prefs.getString('profile_name') ?? '').isNotEmpty;
      if (!hasName && mounted) {
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) => const PopScope(
            canPop: false,
            child: ProfileDialog(first: true, prevIndex: 0),
          ),
        );
        final SharedPreferences saved = await SharedPreferences.getInstance();
        await Account.updateProfile(
          name: saved.getString('profile_name'),
          avatar: saved.getString('avatar_path'),
        );
      }
    }

    if (!mounted) return;
    await Account.markOnboarded();
    if (!mounted) return;
    if (widget.returnOnSuccess) {
      Navigator.of(context).pop(true);
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const WelcomePage()),
      (Route<dynamic> route) => false,
    );
  }

  /// The escape hatch. Signing in is a convenience - the games follow the
  /// player to another device - not a requirement, so a player who does not
  /// want an account can walk straight into the game.
  Future<void> _continueAsGuest() async {
    await Account.markOnboarded();
    if (!mounted) return;
    if (widget.returnOnSuccess) {
      Navigator.of(context).pop(false);
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const WelcomePage()),
      (Route<dynamic> route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8E1),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 4.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    _isSignUp ? 'Create your account' : 'Welcome back',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24.sp,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF33691E),
                    ),
                  ),
                  SizedBox(height: 1.h),
                  Text(
                    _isSignUp
                        ? 'Your games stay linked to this email, even after a '
                            'reinstall or on a new device.'
                        : 'Sign in to bring back your games on this device.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14.sp,
                      height: 1.35,
                      color: const Color(0xFF558B2F),
                    ),
                  ),
                  SizedBox(height: 3.h),
                  TextField(
                    controller: _email,
                    focusNode: _emailFocus,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _passwordFocus.requestFocus(),
                    decoration: _decoration(
                      label: 'Email',
                      icon: Icons.alternate_email,
                    ),
                  ),
                  SizedBox(height: 1.5.h),
                  TextField(
                    controller: _password,
                    focusNode: _passwordFocus,
                    obscureText: _obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    decoration: _decoration(
                      label: 'Password',
                      icon: Icons.lock_outline,
                      suffix: IconButton(
                        tooltip: _obscure ? 'Show password' : 'Hide password',
                        icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                          size: 20,
                          color: const Color(0xFF689F38),
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  if (_error != null) ...<Widget>[
                    SizedBox(height: 1.5.h),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: const Color(0xFFC62828),
                        fontSize: 13.sp,
                      ),
                    ),
                  ],
                  SizedBox(height: 3.h),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF689F38),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFFA5D6A7),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
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
                          : Text(
                              _isSignUp ? 'Create account' : 'Sign in',
                              style: TextStyle(
                                fontSize: 17.sp,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  SizedBox(height: 1.5.h),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _isSignUp = !_isSignUp;
                              _error = null;
                            }),
                    child: Text(
                      _isSignUp
                          ? 'I already have an account'
                          : 'New here? Create an account',
                      style: const TextStyle(color: Color(0xFF2E7D32)),
                    ),
                  ),
                  Divider(
                    height: 3.h,
                    color: const Color(0xFFDCEDC8),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _continueAsGuest,
                    child: Text(
                      widget.returnOnSuccess
                          ? 'Keep playing as a guest'
                          : 'Continue without an account',
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF33691E),
                      ),
                    ),
                  ),
                  SizedBox(height: 1.h),
                  Text(
                    'Guest games stay on this device. Clearing the app data or '
                    'uninstalling removes them, and they cannot be opened on '
                    'another device.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.sp,
                      height: 1.3,
                      color: const Color(0xFF7CB342),
                    ),
                  ),
                  SizedBox(height: 1.5.h),
                  Text(
                    'Passwords are stored as a salted PBKDF2 hash on our '
                    'database - never as plain text.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: const Color(0xFF7CB342),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration({
    required String label,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: const Color(0xFF689F38)),
      suffixIcon: suffix,
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
