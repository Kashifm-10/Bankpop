import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// The password rules, in one place.
///
/// Sign-up, setting a password after a reset, and changing it from the profile
/// all ask the same question, so they cannot drift into three different ideas
/// of what a password is. Sign-in deliberately does not check the rules: an
/// account made before they existed keeps working, and is asked to pick a
/// compliant one the next time it changes its password.
class PasswordRules {
  const PasswordRules._();

  static const int minLength = 8;
  static const int maxLength = 128;

  /// Null when [password] may be used, otherwise one sentence naming what is
  /// missing - the text a screen shows under the field.
  static String? problem(String password) {
    if (password.length < minLength) {
      return 'Use at least $minLength characters.';
    }
    if (password.length > maxLength) {
      return 'Use at most $maxLength characters.';
    }
    if (!password.contains(RegExp(r'[A-Za-z]'))) {
      return 'Include at least one letter.';
    }
    if (!password.contains(RegExp(r'[0-9]'))) {
      return 'Include at least one number.';
    }
    return null;
  }

  /// The rules as a short line shown under the field, in the order they are
  /// checked.
  static const String hint =
      'At least $minLength characters, with a letter and a number.';
}

/// Salted PBKDF2-HMAC-SHA256, exactly as `players_profile` stores it.
///
/// The app is the only thing that derives this (accounts live in a table, not
/// in Supabase Auth), so the derivation has to be stable across releases: a
/// password set today must still sign in after an update. The reset-password
/// fields use the same derivation, which is what lets one table hold both the
/// real password and the temporary one without either being readable.
class PasswordHash {
  const PasswordHash._();

  static const int iterations = 20000;

  /// A fresh 16-byte salt, base64url, so the same password on two accounts
  /// produces two different hashes.
  static String newSalt() {
    final Random random = Random.secure();
    final List<int> bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  static String derive(String password, String salt, int rounds) {
    final Hmac hmac = Hmac(sha256, utf8.encode(password));
    final List<int> block = <int>[
      ...utf8.encode(salt),
      0,
      0,
      0,
      1,
    ];
    List<int> u = hmac.convert(block).bytes;
    final List<int> result = List<int>.from(u);
    for (int i = 1; i < rounds; i++) {
      u = hmac.convert(u).bytes;
      for (int j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }
    return base64Encode(result);
  }

  /// Constant-shape comparison: every byte is compared even after a mismatch,
  /// so the check does not leak how much of the hash was right.
  static bool matches({
    required String password,
    required String salt,
    required int rounds,
    required String expected,
  }) {
    if (expected.isEmpty || salt.isEmpty || rounds <= 0) return false;
    final String actual = derive(password, salt, rounds);
    return constantTimeEquals(expected, actual);
  }

  static bool constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
