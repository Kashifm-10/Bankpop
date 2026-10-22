import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:mon/services/profile_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// A player account, as stored in `players_profile`.
class AccountProfile {
  const AccountProfile({
    required this.id,
    required this.email,
    this.name,
    this.avatar,
  });

  /// The stable player id. This is the same id the game rows use, which is what
  /// keeps a player's games attached to their account across devices.
  final String id;
  final String email;
  final String? name;
  final String? avatar;
}

/// The outcome of a sign-up or sign-in, small enough for a screen to render
/// directly.
class AuthResult {
  const AuthResult.ok(this.profile, {this.created = false}) : error = null;
  const AuthResult.failed(String this.error)
      : profile = null,
        created = false;

  final AccountProfile? profile;
  final String? error;
  final bool created;

  bool get ok => profile != null;
}

/// Email + password accounts, kept entirely in `players_profile`.
///
/// There is deliberately no Supabase Auth and no Google sign-in here: the
/// player types an address and a password, the app derives a salted
/// PBKDF2-HMAC-SHA256 hash on the device and stores only that. Signing in
/// re-derives the hash and compares.
///
/// Signing in adopts the profile's id as this device's `playerID`. Every game
/// row is keyed by that id, so the games played under the account are still
/// listed on a new phone - which is the whole point of having an account.
class Account {
  Account._();

  /// Keys in SharedPreferences. The id is also written to `playerID`, because
  /// that is what every game screen already reads.
  static const String idKey = 'account_id';
  static const String emailKey = 'account_email';

  /// Set once the story has been shown (or the device already had an account).
  ///
  /// Signing in is optional, so this - not an account - is what decides whether
  /// the splash screen opens the introduction or goes straight to the games. It
  /// lives here because the splash screen asks both questions in one place.
  static const String onboardingDoneKey = 'onboarding_done';

  /// The PBKDF2 work factor. High enough that a stolen hash is not a password,
  /// low enough that a phone (or a browser compiling Dart to JavaScript) can
  /// derive it in well under a second.
  static const int iterations = 20000;

  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static Future<bool> isSignedIn() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? email = prefs.getString(emailKey);
    return email != null && email.isNotEmpty;
  }

  /// Marks the introduction as seen, so a guest is not walked through it on
  /// every launch.
  static Future<void> markOnboarded() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(onboardingDoneKey, true);
  }

  static Future<String?> signedInEmail() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(emailKey);
  }

  /// Creates the account for [email] and adopts its id on this device.
  ///
  /// A device that already played games before signing up keeps its existing
  /// player id, so those games become this account's games instead of being
  /// abandoned by the new profile.
  static Future<AuthResult> signUp({
    required String email,
    required String password,
  }) async {
    final String address = email.trim().toLowerCase();
    final String? invalid = _validate(address, password);
    if (invalid != null) return AuthResult.failed(invalid);

    final SupabaseClient supabase = Supabase.instance.client;
    try {
      final Map<String, dynamic>? existing = await supabase
          .from('players_profile')
          .select('id')
          .eq('email', address)
          .maybeSingle();
      if (existing != null) {
        return const AuthResult.failed(
            'An account with this email already exists. Sign in instead.');
      }

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String id = prefs.getString('playerID') ?? const Uuid().v4();
      final String salt = _newSalt();
      final String hash = _derive(password, salt, iterations);

      final Map<String, dynamic> row = <String, dynamic>{
        'id': id,
        'email': address,
        'password_hash': hash,
        'password_salt': salt,
        'iterations': iterations,
        'name': prefs.getString('profile_name'),
        'avatar': prefs.getString('avatar_path'),
      };
      await supabase.from('players_profile').insert(row);

      await _adopt(
        prefs,
        AccountProfile(
          id: id,
          email: address,
          name: row['name'] as String?,
          avatar: row['avatar'] as String?,
        ),
      );
      return AuthResult.ok(
        AccountProfile(
          id: id,
          email: address,
          name: row['name'] as String?,
          avatar: row['avatar'] as String?,
        ),
        created: true,
      );
    } on PostgrestException catch (error) {
      // A racing sign-up hits the unique index first; both clients should see
      // the same sentence.
      if (error.code == '23505') {
        return const AuthResult.failed(
            'An account with this email already exists. Sign in instead.');
      }
      debugPrint('Sign-up failed: $error');
      return AuthResult.failed(_migrationHint(error));
    } catch (error) {
      debugPrint('Sign-up failed: $error');
      return const AuthResult.failed(
          'Could not create the account. Check your connection and try again.');
    }
  }

  /// Signs in and adopts the profile's id (and name/avatar) on this device.
  static Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    final String address = email.trim().toLowerCase();
    if (address.isEmpty || password.isEmpty) {
      return const AuthResult.failed('Enter your email and password.');
    }

    try {
      final Map<String, dynamic>? row = await Supabase.instance.client
          .from('players_profile')
          .select()
          .eq('email', address)
          .maybeSingle();
      if (row == null) {
        return const AuthResult.failed('Email or password is incorrect.');
      }

      final String salt = row['password_salt']?.toString() ?? '';
      final int rounds = (row['iterations'] as num?)?.toInt() ?? iterations;
      final String expected = row['password_hash']?.toString() ?? '';
      final String actual = _derive(password, salt, rounds);
      if (expected.isEmpty || !_constantTimeEquals(expected, actual)) {
        return const AuthResult.failed('Email or password is incorrect.');
      }

      final AccountProfile profile = AccountProfile(
        id: row['id']?.toString() ?? '',
        email: address,
        name: row['name']?.toString(),
        avatar: row['avatar']?.toString(),
      );
      if (profile.id.isEmpty) {
        return const AuthResult.failed(
            'This account is missing its player id. Contact support.');
      }

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await _adopt(prefs, profile);
      return AuthResult.ok(profile);
    } on PostgrestException catch (error) {
      debugPrint('Sign-in failed: $error');
      return AuthResult.failed(_migrationHint(error));
    } catch (error) {
      debugPrint('Sign-in failed: $error');
      return const AuthResult.failed(
          'Could not sign in. Check your connection and try again.');
    }
  }

  /// A missing table is an install problem, not something the player can fix by
  /// retrying, so it gets its own sentence naming the file to run.
  static String _migrationHint(PostgrestException error) {
    // 42P01 is Postgres' "undefined_table"; PGRST205 is PostgREST saying the
    // table is not in its schema cache. Either one means the SQL file has not
    // been run on this project yet.
    if (error.code == '42P01' ||
        error.code == 'PGRST205' ||
        error.message.contains('schema cache')) {
      return 'Accounts are not set up on this database yet. Run '
          'supabase/accounts.sql in the Supabase SQL editor, then try again.';
    }
    return 'Could not reach the account service. Check your connection and try '
        'again.';
  }

  /// Writes the account's name/avatar back to its profile row.
  ///
  /// Best effort: editing a profile must never fail because the network is
  /// down, and the local copy is already saved by the caller.
  static Future<void> updateProfile({String? name, String? avatar}) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? id = prefs.getString(idKey);
    if (id == null || id.isEmpty) return;
    final Map<String, dynamic> update = <String, dynamic>{
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (name != null && name.isNotEmpty) update['name'] = name;
    if (avatar != null && avatar.isNotEmpty) update['avatar'] = avatar;
    if (update.length == 1) return;
    try {
      await Supabase.instance.client
          .from('players_profile')
          .update(update)
          .eq('id', id);
    } catch (error) {
      debugPrint('Could not update the profile: $error');
    }
  }

  /// Clears the account from this device. The player id is kept, so the games
  /// this device played stay reachable until someone else signs in.
  static Future<void> signOut() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(idKey);
    await prefs.remove(emailKey);
  }

  static Future<void> _adopt(
      SharedPreferences prefs, AccountProfile profile) async {
    // A different account on this device must not inherit the previous one's
    // "last game", or the app would reopen somebody else's table.
    final String? previousId = prefs.getString('playerID');
    if (previousId != null && previousId != profile.id) {
      await prefs.remove('gameID');
    }
    await prefs.setString(idKey, profile.id);
    await prefs.setString(emailKey, profile.email);
    // Every game screen keys off playerID, so signing in has to move it to the
    // account's id for the old games to come back.
    await prefs.setString('playerID', profile.id);
    final String? name = profile.name;
    if (name != null && name.isNotEmpty) {
      await prefs.setString('profile_name', name);
    }
    final String? avatar = profile.avatar;
    if (avatar != null && avatar.isNotEmpty) {
      final int index = ProfileAvatar.choices.indexOf(avatar);
      await prefs.setString('avatar_path', avatar);
      if (index >= 0) await prefs.setInt('selected_avatar_index', index);
    }
  }

  static String _newSalt() {
    final Random random = Random.secure();
    final List<int> bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  /// Exposed so a test can prove the derivation itself is stable and salted;
  /// nothing in the app calls it directly.
  @visibleForTesting
  static String deriveForTesting(String password, String salt, int rounds) =>
      _derive(password, salt, rounds);

  /// PBKDF2-HMAC-SHA256. One 100-byte block is all SHA-256 needs for a 32-byte
  /// key, so the loop is the straightforward version rather than a general one.
  static String _derive(String password, String salt, int rounds) {
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

  /// The comparison itself is not a secret-dependent branch that could leak a
  /// usable prefix over the network - it is local - but comparing every byte
  /// keeps the shape of the check constant.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  static String? _validate(String email, String password) {
    if (!_emailPattern.hasMatch(email)) {
      return 'Enter a valid email address.';
    }
    if (password.length < 6) {
      return 'Password must be at least 6 characters.';
    }
    return null;
  }
}
