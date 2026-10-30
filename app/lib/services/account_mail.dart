import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:mon/services/email_sender.dart';
import 'package:mon/services/email_settings.dart';
import 'package:mon/services/mail_templates.dart';
import 'package:mon/services/password.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The messages the account screens send, and the state they change.
///
/// Kept apart from [Account] because the interesting part is not the password
/// check - it is the link in the mail. A verification link is a bearer token:
/// whoever holds it can mark an address verified. So the token is 32 random
/// bytes, only its SHA-256 hash is stored, it expires after a day and it can be
/// used once. A database leak therefore does not hand anybody a working link,
/// and forwarding the same link again does nothing.
class AccountMail {
  const AccountMail._();

  static SupabaseClient get _db => Supabase.instance.client;

  /// A day is long enough to find the mail in spam and short enough that a
  /// leaked old link stops mattering.
  static const Duration _tokenLifetime = Duration(hours: 24);

  /// Resend guard: two clicks must not produce two mails.
  static const Duration _cooldown = Duration(seconds: 60);

  static Future<MailResult> sendVerification({
    required String profileId,
    required String email,
  }) async {
    try {
      final Map<String, dynamic>? profile = await _db
          .from('players_profile')
          .select('id, email, verified')
          .eq('id', profileId)
          .maybeSingle();
      if (profile == null) {
        return const MailResult.failure('That account no longer exists.');
      }
      if (profile['verified'] == true) {
        return const MailResult.ok('This email is already verified.');
      }

      final String? token = await _freshToken(profileId);
      if (token == null) {
        return const MailResult.failure(
          'Please wait a minute before asking for another verification email.',
        );
      }

      // One read of the row: `app_url` builds the link, `mail_api_url` tells
      // the sender where the Django service is, so hosting the service does not
      // need a new build.
      final EmailSettings? settings = await EmailSettings.load();
      final String? appUrl = _appUrlFrom(settings);
      if (appUrl == null) {
        await _dropToken(token);
        return const MailResult.failure(
          'This build cannot read the app_url column of email_settings. Run '
          'supabase/mail_provider.sql in the Supabase SQL editor and fill that '
          'column in (for example https://bankpop.app) so the verification '
          'link can open the app.',
        );
      }

      // A standalone page, not the app: the link has to work on a laptop that
      // has never opened BankPop, and it is `web/verify.html` (copied into the
      // build beside index.html) that marks the address verified.
      final String base = appUrl.replaceAll(RegExp(r'/+$'), '');
      final String link =
          '$base/verify.html?token=${Uri.encodeComponent(token)}';
      final EmailResult sent = await EmailSender.send(
        to: email,
        subject: 'Verify your BankPop account',
        text: MailTemplates.verificationText(actionUrl: link),
        html: MailTemplates.verificationHtml(
          actionUrl: link,
          appUrl: appUrl,
        ),
        serviceUrl: settings?.resolvedMailApiUrl ?? '',
      );

      if (!sent.ok) {
        await _dropToken(token);
        return MailResult.failure(sent.message);
      }
      return MailResult.ok('We sent a verification link to $email.');
    } catch (error) {
      debugPrint('Could not send the verification email: $error');
      return const MailResult.failure(
        'Could not send the verification email. Has supabase/email.sql been '
        'run on this project?',
      );
    }
  }

  /// The "Resend" button on the sign-in screen, where only the address is
  /// known.
  static Future<MailResult> resendVerification(String email) async {
    final String address = email.trim().toLowerCase();
    if (address.isEmpty) {
      return const MailResult.failure('Enter your email address first.');
    }
    try {
      final Map<String, dynamic>? profile = await _db
          .from('players_profile')
          .select('id, email, verified')
          .eq('email', address)
          .maybeSingle();
      if (profile == null) {
        return const MailResult.failure('No account uses that email address.');
      }
      return sendVerification(
        profileId: profile['id'].toString(),
        email: address,
      );
    } catch (error) {
      debugPrint('Could not resend the verification email: $error');
      return const MailResult.failure(
        'Could not resend the verification email. Check your connection and '
        'try again.',
      );
    }
  }

  /// Consumes a token from a verification link.
  ///
  /// The link may be opened on a phone that is signed in as somebody else, so
  /// this changes only the profile the token was issued for and never touches
  /// this device's account.
  static Future<MailResult> verifyToken(String? rawToken) async {
    final String token = (rawToken ?? '').trim();
    if (token.isEmpty) {
      return const MailResult.failure(
        'This verification link is missing its code. Open the link from your '
        'email again.',
      );
    }

    final String hash = _sha256(token);
    try {
      final DateTime now = DateTime.now().toUtc();
      final Map<String, dynamic>? row = await _db
          .from('email_tokens')
          .select('id, profile_id, expires_at, used_at')
          .eq('token_hash', hash)
          .eq('purpose', 'verify')
          .isFilter('used_at', null)
          .maybeSingle();
      if (row == null) {
        return const MailResult.failure(
          'This link has already been used or is not valid. Ask for a new '
          'verification email from the sign-in screen.',
        );
      }
      final DateTime? expires =
          DateTime.tryParse(row['expires_at']?.toString() ?? '')?.toUtc();
      if (expires == null || expires.isBefore(now)) {
        return const MailResult.failure(
          'This link has expired. Ask for a new verification email from the '
          'sign-in screen.',
        );
      }

      await _db.from('players_profile').update(<String, dynamic>{
        'verified': true,
        'updated_at': now.toIso8601String(),
      }).eq('id', row['profile_id'].toString());
      await _db
          .from('email_tokens')
          .update(<String, dynamic>{'used_at': now.toIso8601String()}).eq(
              'id', row['id']);
      return const MailResult.ok(
        'Your email is verified. Return to the BankPop app and sign in.',
      );
    } catch (error) {
      debugPrint('Could not verify the email token: $error');
      return const MailResult.failure(
        'Could not verify this link. Has supabase/email.sql been run on this '
        'project?',
      );
    }
  }

  /// Emails a temporary password, leaving the real one untouched.
  ///
  /// The temporary password is generated here, stored only as a hash in the
  /// `reset_password_*` columns and mailed in the clear (which is what a
  /// password in an email is). Signing in with it sets a flag, and the app
  /// asks for a new password before it goes any further - where writing it
  /// into `password_hash` replaces the real password and clears the temporary
  /// one.
  static Future<MailResult> requestPasswordReset(String email) async {
    final String address = email.trim().toLowerCase();
    if (address.isEmpty) {
      return const MailResult.failure('Enter your email address first.');
    }

    try {
      final Map<String, dynamic>? profile = await _db
          .from('players_profile')
          .select('id, email, reset_requested_at')
          .eq('email', address)
          .maybeSingle();
      // The same sentence for an unknown address: a reset form should not be a
      // way to find out which addresses have accounts.
      if (profile == null) {
        return MailResult.ok(
            'If an account uses $address, a temporary password is on its way.');
      }

      final DateTime? lastRequested =
          DateTime.tryParse(profile['reset_requested_at']?.toString() ?? '')
              ?.toUtc();
      if (lastRequested != null &&
          DateTime.now().toUtc().difference(lastRequested) < _cooldown) {
        return const MailResult.failure(
          'A temporary password was sent a moment ago. Check your inbox, or '
          'wait a minute before trying again.',
        );
      }

      final String temporaryPassword = _temporaryPassword();
      final String salt = PasswordHash.newSalt();
      final String hash = PasswordHash.derive(
        temporaryPassword,
        salt,
        PasswordHash.iterations,
      );

      await _db.from('players_profile').update(<String, dynamic>{
        'reset_password_hash': hash,
        'reset_password_salt': salt,
        'reset_password_iterations': PasswordHash.iterations,
        'reset_requested_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', profile['id'].toString());

      // A reset needs no link, so a missing app_url is not the failure here
      // that it is for a verification mail - the mark just stops linking. The
      // same row carries the mail service's address.
      final EmailSettings? settings = await EmailSettings.load();
      final EmailResult sent = await EmailSender.send(
        to: address,
        subject: 'Your BankPop temporary password',
        text: MailTemplates.resetText(temporaryPassword: temporaryPassword),
        html: MailTemplates.resetHtml(
          temporaryPassword: temporaryPassword,
          appUrl: _appUrlFrom(settings) ?? '',
        ),
        serviceUrl: settings?.resolvedMailApiUrl ?? '',
      );

      if (!sent.ok) {
        // Put the account back the way it was, so a failed send does not leave
        // a temporary password nobody knows.
        await _db.from('players_profile').update(<String, dynamic>{
          'reset_password_hash': null,
          'reset_password_salt': null,
          'reset_password_iterations': null,
          'reset_requested_at': null,
        }).eq('id', profile['id'].toString());
        return MailResult.failure(sent.message);
      }

      return MailResult.ok(
          'A temporary password is on its way to $address. Sign in with it, '
          'and the app will ask you to choose a new password.');
    } catch (error) {
      debugPrint('Could not start a password reset: $error');
      return const MailResult.failure(
        'Could not start a password reset. Check your connection and try '
        'again.',
      );
    }
  }

  /// Creates a token row and returns the raw token, or null while the last one
  /// is still inside the cooldown.
  static Future<String?> _freshToken(String profileId) async {
    final DateTime now = DateTime.now().toUtc();
    final List<dynamic> recent = await _db
        .from('email_tokens')
        .select('created_at')
        .eq('profile_id', profileId)
        .eq('purpose', 'verify')
        .order('created_at', ascending: false)
        .limit(1);
    if (recent.isNotEmpty) {
      final DateTime? created = DateTime.tryParse(
              (recent.first as Map)['created_at']?.toString() ?? '')
          ?.toUtc();
      if (created != null && now.difference(created) < _cooldown) {
        return null;
      }
    }

    final String token = _randomToken();
    await _db.from('email_tokens').insert(<String, dynamic>{
      'profile_id': profileId,
      'purpose': 'verify',
      'token_hash': _sha256(token),
      'expires_at': now.add(_tokenLifetime).toIso8601String(),
    });
    return token;
  }

  static Future<void> _dropToken(String token) async {
    try {
      await _db.from('email_tokens').delete().eq('token_hash', _sha256(token));
    } catch (error) {
      debugPrint('Could not drop the unused token: $error');
    }
  }

  /// Where the app's own links open: the row's `app_url`, or - when the row
  /// cannot be read - the browser's own origin. A phone has no origin to fall
  /// back to, which is why the column has to be filled in for Android and iOS.
  static String? _appUrlFrom(EmailSettings? settings) {
    final String url =
        settings?.resolvedAppUrl ?? (kIsWeb ? Uri.base.origin : '');
    return url.isEmpty ? null : url;
  }

  static String _randomToken() {
    final Random random = Random.secure();
    final List<int> bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  /// A password a person can retype from a mail: no 0/O or 1/l/I.
  static String _temporaryPassword() {
    const String alphabet =
        'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final Random random = Random.secure();
    String result = '';
    for (int i = 0; i < 12; i++) {
      result += alphabet[random.nextInt(alphabet.length)];
    }
    // The rules require a digit; the alphabet has one only by chance.
    if (!result.contains(RegExp(r'[0-9]'))) {
      result = '${result.substring(0, result.length - 1)}'
          '${random.nextInt(10)}';
    }
    return result;
  }

  static String _sha256(String value) =>
      sha256.convert(utf8.encode(value)).toString();
}

/// The sentence an account screen shows after trying to send a mail.
class MailResult {
  const MailResult.ok(this.message) : ok = true;
  const MailResult.failure(this.message) : ok = false;

  final bool ok;
  final String message;
}
