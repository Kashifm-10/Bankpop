import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mon/routes.dart';
import 'package:mon/services/account_mail.dart';

/// Where the link in the verification mail lands.
///
/// The link is a URL, so it opens in a browser rather than in the app. The page
/// does the one thing the link is for - marks that address verified - and then
/// tells the player exactly what to do next: go back to BankPop and sign in.
/// Visiting it twice, or opening a forwarded or guessed link, says so instead
/// of quietly verifying somebody else.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key, this.token});

  final String? token;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _busy = true;
  MailResult? _result;

  @override
  void initState() {
    super.initState();
    _verify();
  }

  Future<void> _verify() async {
    final MailResult result = await AccountMail.verifyToken(widget.token);
    if (!mounted) return;
    setState(() {
      _result = result;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final MailResult? result = _result;
    final bool success = result?.ok ?? false;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8E1),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                color: const Color(0xFFFFF9C4),
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Icon(
                        _busy
                            ? Icons.mark_email_unread_outlined
                            : success
                                ? Icons.verified_outlined
                                : Icons.error_outline,
                        size: 54,
                        color: success
                            ? const Color(0xFF2E7D32)
                            : _busy
                                ? const Color(0xFF689F38)
                                : const Color(0xFFC62828),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _busy
                            ? 'Verifying your email...'
                            : success
                                ? 'Your email is verified'
                                : 'This link could not be used',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF33691E),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_busy)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF689F38),
                            ),
                          ),
                        )
                      else ...<Widget>[
                        Text(
                          result?.message ??
                              'Something went wrong. Try the link again.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.45,
                            color: Color(0xFF558B2F),
                          ),
                        ),
                        if (success) ...<Widget>[
                          const SizedBox(height: 16),
                          const Text(
                            'Return to the BankPop app to log in.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF2E7D32),
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: () => context.go(AppRoutes.auth),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF689F38),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            success ? 'Go to sign in' : 'Sign in or resend',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => context.go(AppRoutes.home),
                          child: const Text(
                            'Open BankPop',
                            style: TextStyle(color: Color(0xFF2E7D32)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
