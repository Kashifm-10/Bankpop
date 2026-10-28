import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mon/routes.dart';
import 'package:mon/services/account.dart';
import 'package:mon/services/account_mail.dart';
import 'package:mon/services/password.dart';
import 'package:mon/widgets/app_dialog.dart';
import 'package:mon/widgets/app_message.dart';
import 'package:mon/widgets/app_metrics.dart';

/// The one place an account is created or opened.
///
/// Accounts are rows in `players_profile`, not Supabase Auth: the address, a
/// salted PBKDF2 hash and the id that owns the games. Creating one sends a
/// verification link, and signing in is refused until that link is opened -
/// which is what makes the address worth anything if the account is ever
/// recovered.
///
/// Forgotten passwords never touch the real one. The reset mail carries a
/// temporary password held in its own columns; signing in with it is allowed
/// and takes the player straight to the new-password screen.
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
  final TextEditingController _confirm = TextEditingController();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _confirmFocus = FocusNode();

  bool _busy = false;
  bool _obscure = true;
  bool _obscureConfirm = true;
  bool _resending = false;
  String? _error;

  /// Set after a successful sign-up: the form is replaced by "check your
  /// inbox", because this account cannot sign in until the link is opened.
  String? _pendingEmail;

  /// Why the verification mail did not go out, when it did not. The account
  /// exists either way, so the screen says what failed and offers the resend
  /// instead of throwing the sign-up away.
  String? _pendingMailProblem;

  /// Set when a sign-in was refused only because the address is unverified, so
  /// the screen can offer the resend without the player retyping anything.
  String? _unverifiedEmail;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _unverifiedEmail = null;
    });

    if (_isSignUp) {
      await _signUp();
    } else {
      await _signIn();
    }
  }

  Future<void> _signUp() async {
    final String email = _email.text.trim();
    final String password = _password.text;

    final String? invalidEmail = email.isEmpty
        ? 'Enter your email address.'
        : (RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)
            ? null
            : 'Enter a valid email address.');
    if (invalidEmail != null) {
      _fail(invalidEmail);
      return;
    }
    final String? problem = PasswordRules.problem(password);
    if (problem != null) {
      _fail(problem);
      return;
    }
    if (password != _confirm.text) {
      _fail('The two passwords do not match.');
      return;
    }

    final SignUpResult result =
        await Account.signUp(email: email, password: password);
    if (!mounted) return;

    if (!result.ok) {
      _fail(result.error ?? 'Could not create the account.');
      return;
    }

    await Account.markOnboarded();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _pendingEmail = result.email ?? email;
      _pendingMailProblem = result.mailProblem;
      _password.clear();
      _confirm.clear();
    });
  }

  Future<void> _signIn() async {
    // Read before signing in: adopting the account moves `playerID` to the
    // account's id, and the guest id is gone from the device after that.
    final String? guestId = await Account.guestPlayerId();
    final bool guestPlayed =
        guestId != null && await Account.hasGames(guestId);

    final AuthResult result = await Account.signIn(
      email: _email.text,
      password: _password.text,
    );
    if (!mounted) return;

    if (!result.ok) {
      setState(() {
        _busy = false;
        // An unverified address is not an error to shout about: it gets its own
        // notice, with the address it was refused for and the resend beside it.
        _unverifiedEmail = result.needsVerification
            ? result.email ?? _email.text.trim()
            : null;
        _error = result.needsVerification ? null : result.error;
      });
      return;
    }

    await Account.markOnboarded();
    if (!mounted) return;
    setState(() => _busy = false);

    // Guest games live under the old player id, which this sign-in has just
    // replaced. Ask before they are left behind: keeping them repoints every
    // row they own at the account, so the history is one list again.
    final String accountId = result.profile?.id ?? '';
    if (guestPlayed && accountId.isNotEmpty) {
      final bool keep = await showAppConfirm(
        context,
        title: 'Keep your guest games?',
        icon: Icons.merge_type,
        confirmLabel: 'Keep them',
        cancelLabel: 'No thanks',
        message: 'This device played games before you signed in. Keeping them '
            'moves those games, their cards and their payments into this '
            'account, so your history stays in one place. They will no longer '
            'be reachable as a guest.',
      );
      if (keep) {
        await Account.adoptGuestGames(guestId: guestId, accountId: accountId);
      }
      if (!mounted) return;
    }

    // A temporary password only gets this far: the real password is chosen
    // before anything else, and the splash screen enforces the same rule if
    // the app is closed here.
    if (result.usedResetPassword) {
      context.go(AppRoutes.setPassword);
      return;
    }

    if (widget.returnOnSuccess) {
      if (context.canPop()) {
        context.pop(true);
      } else {
        context.go(AppRoutes.home);
      }
      return;
    }
    context.go(AppRoutes.home);
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  Future<void> _resend(String email) async {
    if (_resending) return;
    setState(() => _resending = true);
    final MailResult result = await AccountMail.resendVerification(email);
    if (!mounted) return;
    setState(() => _resending = false);
    await showMessage(context, result.message,
        title: result.ok ? 'Verification email' : 'Could not send the email');
  }

  Future<void> _forgotPassword() async {
    final MailResult? result = await showDialog<MailResult>(
      context: context,
      builder: (BuildContext dialogContext) =>
          _ForgotPasswordDialog(initialEmail: _email.text.trim()),
    );
    if (result == null || !mounted) return;
    await showMessage(
      context,
      result.message,
      title: result.ok ? 'Temporary password' : 'Could not reset the password',
    );
  }

  /// The escape hatch. Signing in is a convenience - the games follow the
  /// player to another device - not a requirement, so a player who does not
  /// want an account can walk straight into the game.
  ///
  /// The trade is spelled out first: a guest gets the whole game, but the
  /// things that need an identity are not there, and this is the one moment the
  /// player can decide with the list in front of them.
  Future<void> _continueAsGuest() async {
    final bool goAhead = await showAppConfirm(
      context,
      title: 'Play as a guest?',
      icon: Icons.person_outline,
      confirmLabel: 'Continue as guest',
      cancelLabel: 'Sign in instead',
      message: 'These need an account and will not be available:',
      extra: const _GuestLimits(),
    );
    if (!goAhead) return;
    await Account.markOnboarded();
    if (!mounted) return;
    if (widget.returnOnSuccess) {
      if (context.canPop()) {
        context.pop(false);
      } else {
        context.go(AppRoutes.home);
      }
      return;
    }
    context.go(AppRoutes.home);
  }

  void _switchMode() {
    setState(() {
      _isSignUp = !_isSignUp;
      _error = null;
      _unverifiedEmail = null;
      _confirm.clear();
    });
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
            child: ConstrainedBox(
              // A login form keeps a phone-like measure; on a desktop window it
              // sits as a card in the middle rather than stretching its fields.
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: _pendingEmail != null
                  ? _PendingVerification(
                      email: _pendingEmail!,
                      problem: _pendingMailProblem,
                      busy: _resending,
                      onResend: () => _resend(_pendingEmail!),
                      onBack: () => setState(() {
                        _pendingEmail = null;
                        _pendingMailProblem = null;
                        _isSignUp = false;
                        _error = null;
                      }),
                    )
                  : Column(
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
                              ? 'Your games stay linked to this email, even '
                                  'after a reinstall or on a new device.'
                              : 'Sign in to bring back your games on this '
                                  'device.',
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
                          textInputAction: _isSignUp
                              ? TextInputAction.next
                              : TextInputAction.done,
                          onSubmitted: (_) => _isSignUp
                              ? _confirmFocus.requestFocus()
                              : _submit(),
                          decoration: _decoration(
                            label: 'Password',
                            icon: Icons.lock_outline,
                            suffix: IconButton(
                              tooltip:
                                  _obscure ? 'Show password' : 'Hide password',
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                size: 20,
                                color: const Color(0xFF689F38),
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                        ),
                        if (_isSignUp) ...<Widget>[
                          SizedBox(height: 0.8.h),
                          const Text(
                            PasswordRules.hint,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF7CB342),
                            ),
                          ),
                          SizedBox(height: 1.2.h),
                          TextField(
                            controller: _confirm,
                            focusNode: _confirmFocus,
                            obscureText: _obscureConfirm,
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _submit(),
                            decoration: _decoration(
                              label: 'Type the password again',
                              icon: Icons.check_circle_outline,
                              suffix: IconButton(
                                tooltip: _obscureConfirm
                                    ? 'Show password'
                                    : 'Hide password',
                                icon: Icon(
                                  _obscureConfirm
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  size: 20,
                                  color: const Color(0xFF689F38),
                                ),
                                onPressed: () => setState(
                                    () => _obscureConfirm = !_obscureConfirm),
                              ),
                            ),
                          ),
                        ],
                        if (_error != null) ...<Widget>[
                          SizedBox(height: 1.5.h),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: const Color(0xFFC62828),
                              fontSize: 13.sp,
                              height: 1.35,
                            ),
                          ),
                        ],
                        if (_unverifiedEmail != null) ...<Widget>[
                          SizedBox(height: 1.2.h),
                          _VerificationPendingNotice(
                            email: _unverifiedEmail!,
                            busy: _resending,
                            onResend: () => _resend(_unverifiedEmail!),
                          ),
                        ],
                        if (!_isSignUp) ...<Widget>[
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _busy ? null : _forgotPassword,
                              child: const Text(
                                'Forgot password?',
                                style: TextStyle(color: Color(0xFF2E7D32)),
                              ),
                            ),
                          ),
                        ],
                        SizedBox(height: _isSignUp ? 2.2.h : 1.h),
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
                        SizedBox(height: 1.2.h),
                        TextButton(
                          onPressed: _busy ? null : _switchMode,
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
                          'Guest games stay on this device. Clearing the app '
                          'data or uninstalling removes them, and they cannot '
                          'be opened on another device.',
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

/// Shown after sign-up: the account exists, but the link has to be opened
/// before it can sign in.
class _PendingVerification extends StatelessWidget {
  const _PendingVerification({
    required this.email,
    required this.busy,
    required this.onResend,
    required this.onBack,
    this.problem,
  });

  final String email;
  final bool busy;
  final VoidCallback onResend;
  final VoidCallback onBack;

  /// Why the link did not go out, when it did not. The account is created
  /// either way, so this is a note about the mail rather than a failed sign-up.
  final String? problem;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(Icons.mark_email_unread_outlined,
            size: 58, color: Color(0xFF689F38)),
        SizedBox(height: 2.h),
        Text(
          'Check your mail to verify',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22.sp,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF33691E),
          ),
        ),
        SizedBox(height: 1.h),
        Text(
          problem == null
              ? 'Your account is created. We sent a verification link to '
                  '$email - open it to verify this address, then come back and '
                  'sign in.'
              : 'Your account is created, but the verification email could not '
                  'be sent to $email. The account is waiting for its link: '
                  'tap Resend below, or use the sign-in screen once the mail '
                  'service is back.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14.sp,
            height: 1.4,
            color: const Color(0xFF558B2F),
          ),
        ),
        if (problem != null) ...<Widget>[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFE9E9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE1B3B3)),
            ),
            child: Text(
              'Why: $problem',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: Color(0xFF8E2B2B),
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        const Text(
          'Until that link is opened, signing in to this account is refused. '
          'The link works once and expires after a day.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            color: Color(0xFF7CB342),
          ),
        ),
        SizedBox(height: 2.5.h),
        SizedBox(
          height: 50,
          child: OutlinedButton(
            onPressed: busy ? null : onResend,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF2E7D32),
              side: const BorderSide(color: Color(0xFF689F38)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            child: Text(
              busy ? 'Sending...' : 'Resend the verification email',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: busy ? null : onBack,
          child: const Text(
            'Back to sign in',
            style: TextStyle(color: Color(0xFF2E7D32)),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Nothing in your inbox? Check the spam folder - a link from a new '
          'address often lands there the first time.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11.5, color: Color(0xFF9E9E9E)),
        ),
      ],
    );
  }
}

/// What the sign-in form shows when the password was right but the address has
/// not been verified yet: the address it was refused for, what to do about it,
/// and the resend that sends another link without asking for anything else.
class _VerificationPendingNotice extends StatelessWidget {
  const _VerificationPendingNotice({
    required this.email,
    required this.busy,
    required this.onResend,
  });

  final String email;
  final bool busy;
  final VoidCallback onResend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3CD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0C97F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.mark_email_unread_outlined,
                  size: 18, color: Color(0xFF8D6E00)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Verification pending',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF7A5F00),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'This account cannot sign in until $email is verified. Open the '
            'link we mailed to it, then sign in again. No link, or it has '
            'expired? Send a fresh one:',
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: Color(0xFF7A5F00),
            ),
          ),
          TextButton.icon(
            onPressed: busy ? null : onResend,
            icon: Icon(
              busy ? Icons.hourglass_top : Icons.forward_to_inbox,
              size: 18,
              color: const Color(0xFF2E7D32),
            ),
            label: Text(
              busy ? 'Sending...' : 'Resend the verification email',
              style: const TextStyle(
                color: Color(0xFF2E7D32),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The forgot-password form.
///
/// It closes with the [MailResult] rather than showing its own message, so the
/// same message box is used whether the mail went out or the address had no
/// account - and the wording stays deliberately identical, so the form cannot
/// be used to discover which addresses are registered.
class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog({required this.initialEmail});

  final String initialEmail;

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialEmail);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final MailResult result =
        await AccountMail.requestPasswordReset(_controller.text);
    if (!mounted) return;
    if (result.ok) {
      Navigator.of(context).pop(result);
      return;
    }
    setState(() {
      _busy = false;
      _error = result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFFFFF9C4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text(
        'Forgot password?',
        style: TextStyle(color: Color(0xFF33691E)),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'We will email a temporary password. Your usual password stays as '
            'it is until you have signed in with the temporary one and chosen '
            'a new one.',
            style:
                TextStyle(fontSize: 13, height: 1.4, color: Color(0xFF558B2F)),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            autofocus: true,
            onSubmitted: (_) => _send(),
            decoration: InputDecoration(
              labelText: 'Email',
              prefixIcon:
                  const Icon(Icons.alternate_email, color: Color(0xFF689F38)),
              filled: true,
              fillColor: const Color(0xFFE8F5E9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(
                color: Color(0xFFC62828),
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _busy ? null : _send,
          child: Text(
            _busy ? 'Sending...' : 'Send',
            style: const TextStyle(
              color: Color(0xFF2E7D32),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

/// What a guest gives up, in the one place they can still choose otherwise.
///
/// The app keeps working without an account - this is not a warning that
/// something is broken, but the list of what an email would have bought.
class _GuestLimits extends StatelessWidget {
  const _GuestLimits();

  static const List<String> _lines = <String>[
    'Your games are listed on this device only - reinstalling the app or '
        'clearing the browser data removes them.',
    'A game played as a guest cannot be opened on another phone, tablet or '
        'browser.',
    'Creating and sharing your own boards needs an account.',
    'If you sign in later, your guest games are not merged automatically - '
        'you have to choose to keep them.',
    'Nobody can recover a guest profile: there is no email to verify and no '
        'password to reset.',
  ];

  @override
  Widget build(BuildContext context) {
    final AppDialogPalette palette = AppDialogPalette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final String line in _lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.remove_circle_outline,
                    size: 16, color: palette.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    line,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: palette.body,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
