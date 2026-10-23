import 'package:flutter/foundation.dart';
import 'package:mon/services/account_mail.dart';
import 'package:mon/services/password.dart';
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
    this.verified = false,
  });

  /// The stable player id. This is the same id the game rows use, which is what
  /// keeps a player's games attached to their account across devices.
  final String id;
  final String email;
  final String? name;
  final String? avatar;

  /// False until the link in the verification mail has been opened. Accounts
  /// created before verification existed are marked verified by the migration
  /// in supabase/email.sql.
  final bool verified;
}

/// The outcome of a sign-in, small enough for a screen to render directly.
class AuthResult {
  const AuthResult.ok(this.profile, {this.usedResetPassword = false})
      : error = null,
        needsVerification = false,
        email = null;

  const AuthResult.failed(
    String this.error, {
    this.needsVerification = false,
    this.email,
  })  : profile = null,
        usedResetPassword = false;

  final AccountProfile? profile;
  final String? error;

  /// The password was the temporary one from a reset mail. The caller must
  /// send the player to the new-password screen before anything else.
  final bool usedResetPassword;

  /// The address is right and the password was right, but the account has not
  /// opened its verification link yet - the sign-in screen offers a resend.
  final bool needsVerification;

  /// The address the verification mail should go to, when [needsVerification].
  final String? email;

  bool get ok => profile != null;
}

/// The outcome of creating an account.
///
/// A created account is not signed in: the verification link has to be opened
/// first. [SignUpResult.failed] is also what a player sees when the account row
/// was written but the verification mail could not be sent - the row is then
/// removed, so a retry starts clean instead of leaving an account nobody can
/// enter.
class SignUpResult {
  const SignUpResult.created(this.email) : error = null;
  const SignUpResult.failed(this.error) : email = null;

  final String? email;
  final String? error;

  bool get ok => error == null;
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

  /// True between signing in with a temporary password and choosing a new one.
  /// The splash screen reads it so closing the app mid-way does not skip the
  /// step.
  static const String passwordChangeKey = 'password_change_required';

  /// The PBKDF2 work factor. High enough that a stolen hash is not a password,
  /// low enough that a phone (or a browser compiling Dart to JavaScript) can
  /// derive it in well under a second.
  static const int iterations = PasswordHash.iterations;

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

  /// Whether the splash screen has to detour through "choose a new password".
  static Future<bool> passwordChangeRequired() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(passwordChangeKey) ?? false;
  }

  /// Creates the account for [email] and sends its verification mail.
  ///
  /// A device that already played games before signing up keeps its existing
  /// player id, so those games become this account's games once the address is
  /// verified and the account is signed in.
  static Future<SignUpResult> signUp({
    required String email,
    required String password,
  }) async {
    final String address = email.trim().toLowerCase();
    final String? invalid = _validate(address, password);
    if (invalid != null) return SignUpResult.failed(invalid);

    final SupabaseClient supabase = Supabase.instance.client;
    try {
      final Map<String, dynamic>? existing = await supabase
          .from('players_profile')
          .select('id')
          .eq('email', address)
          .maybeSingle();
      if (existing != null) {
        return const SignUpResult.failed(
            'An account with this email already exists. Sign in instead.');
      }

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String id = prefs.getString('playerID') ?? const Uuid().v4();
      final String salt = PasswordHash.newSalt();
      final String hash = PasswordHash.derive(password, salt, iterations);

      final Map<String, dynamic> row = <String, dynamic>{
        'id': id,
        'email': address,
        'password_hash': hash,
        'password_salt': salt,
        'iterations': iterations,
        'name': prefs.getString('profile_name'),
        'avatar': prefs.getString('avatar_path'),
        'verified': false,
      };

      bool supportsVerification = true;
      try {
        await supabase.from('players_profile').insert(row);
      } on PostgrestException catch (error) {
        if (!_isMissingColumn(error)) rethrow;
        // supabase/email.sql has not been run yet. The account is still worth
        // creating; it simply cannot be verified until the columns exist.
        supportsVerification = false;
        row.remove('verified');
        await supabase.from('players_profile').insert(row);
      }

      if (!supportsVerification) {
        // The row was written by the retry above. Reporting a failure while
        // leaving it behind would make the next attempt collide with an
        // account nobody can sign in to.
        await supabase.from('players_profile').delete().eq('id', id);
        return const SignUpResult.failed(
          'Verification is not set up on this database yet. Run '
          'supabase/email.sql in the Supabase SQL editor, then create the '
          'account again.',
        );
      }

      final MailResult mail = await AccountMail.sendVerification(
        profileId: id,
        email: address,
      );
      if (!mail.ok) {
        // No mail means no way to verify, so the account would be a dead end.
        // Removing it lets the player try again once the mail is fixed.
        try {
          await supabase.from('players_profile').delete().eq('id', id);
        } catch (cleanupError) {
          debugPrint(
              'Could not remove the unverifiable account: $cleanupError');
        }
        return SignUpResult.failed(mail.message);
      }

      return SignUpResult.created(address);
    } on PostgrestException catch (error) {
      // A racing sign-up hits the unique index first; both clients should see
      // the same sentence.
      if (error.code == '23505') {
        return const SignUpResult.failed(
            'An account with this email already exists. Sign in instead.');
      }
      debugPrint('Sign-up failed: $error');
      return SignUpResult.failed(_migrationHint(error));
    } catch (error) {
      debugPrint('Sign-up failed: $error');
      return const SignUpResult.failed(
          'Could not create the account. Check your connection and try again.');
    }
  }

  /// Signs in and adopts the profile's id (and name/avatar) on this device.
  ///
  /// Two passwords are accepted: the real one, and the temporary one a reset
  /// mail carried. The temporary one signs the player in but reports
  /// [AuthResult.usedResetPassword], so the screen can force a new password
  /// before the app is used - which is also the moment the real password is
  /// replaced and the temporary one cleared.
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
      final bool realPassword = PasswordHash.matches(
        password: password,
        salt: salt,
        rounds: rounds,
        expected: expected,
      );

      bool temporaryPassword = false;
      if (!realPassword) {
        temporaryPassword = PasswordHash.matches(
          password: password,
          salt: row['reset_password_salt']?.toString() ?? '',
          rounds:
              (row['reset_password_iterations'] as num?)?.toInt() ?? iterations,
          expected: row['reset_password_hash']?.toString() ?? '',
        );
        if (!temporaryPassword) {
          return const AuthResult.failed('Email or password is incorrect.');
        }
      }

      // The column is absent on a project that has not run email.sql, and an
      // account made before it existed is treated as verified.
      if (!temporaryPassword && row['verified'] == false) {
        return AuthResult.failed(
          'Verify your email before signing in. We sent a link to $address - '
          'tap it, then come back.',
          needsVerification: true,
          email: address,
        );
      }

      final AccountProfile profile = AccountProfile(
        id: row['id']?.toString() ?? '',
        email: address,
        name: row['name']?.toString(),
        avatar: row['avatar']?.toString(),
        verified: row['verified'] == true,
      );
      if (profile.id.isEmpty) {
        return const AuthResult.failed(
            'This account is missing its player id. Contact support.');
      }

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await _adopt(prefs, profile);
      await prefs.setBool(passwordChangeKey, temporaryPassword);
      return AuthResult.ok(profile, usedResetPassword: temporaryPassword);
    } on PostgrestException catch (error) {
      debugPrint('Sign-in failed: $error');
      return AuthResult.failed(_migrationHint(error));
    } catch (error) {
      debugPrint('Sign-in failed: $error');
      return const AuthResult.failed(
          'Could not sign in. Check your connection and try again.');
    }
  }

  /// Replaces the account's password.
  ///
  /// Used by two screens: changing it from the profile (which passes the
  /// current password) and finishing a reset (which does not - the temporary
  /// password already proved the address). Either way the new password must
  /// satisfy [PasswordRules] and must not be one of the two passwords the
  /// account currently accepts, so "change" cannot put the same secret back.
  static Future<String?> setNewPassword({
    required String newPassword,
    String? currentPassword,
  }) async {
    final String? invalid = PasswordRules.problem(newPassword);
    if (invalid != null) return invalid;

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? id = prefs.getString(idKey);
    if (id == null || id.isEmpty) {
      return 'Sign in before changing the password.';
    }

    try {
      final Map<String, dynamic>? row = await Supabase.instance.client
          .from('players_profile')
          .select()
          .eq('id', id)
          .maybeSingle();
      if (row == null) return 'This account no longer exists.';

      if (currentPassword != null) {
        final bool currentOk = PasswordHash.matches(
          password: currentPassword,
          salt: row['password_salt']?.toString() ?? '',
          rounds: (row['iterations'] as num?)?.toInt() ?? iterations,
          expected: row['password_hash']?.toString() ?? '',
        );
        if (!currentOk) return 'Your current password is incorrect.';
      }

      final bool sameAsReal = PasswordHash.matches(
        password: newPassword,
        salt: row['password_salt']?.toString() ?? '',
        rounds: (row['iterations'] as num?)?.toInt() ?? iterations,
        expected: row['password_hash']?.toString() ?? '',
      );
      final bool sameAsTemporary = PasswordHash.matches(
        password: newPassword,
        salt: row['reset_password_salt']?.toString() ?? '',
        rounds:
            (row['reset_password_iterations'] as num?)?.toInt() ?? iterations,
        expected: row['reset_password_hash']?.toString() ?? '',
      );
      if (sameAsReal || sameAsTemporary) {
        return 'Choose a password you have not used on this account before.';
      }

      final String salt = PasswordHash.newSalt();
      final String hash =
          PasswordHash.derive(newPassword, salt, PasswordHash.iterations);
      await Supabase.instance.client
          .from('players_profile')
          .update(<String, dynamic>{
        'password_hash': hash,
        'password_salt': salt,
        'iterations': PasswordHash.iterations,
        // The temporary password has done its job.
        'reset_password_hash': null,
        'reset_password_salt': null,
        'reset_password_iterations': null,
        'reset_requested_at': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);
      await prefs.setBool(passwordChangeKey, false);
      return null;
    } catch (error) {
      debugPrint('Could not change the password: $error');
      return 'Could not save the new password. Check your connection and try '
          'again.';
    }
  }

  /// Changing the password from the profile: the current one has to be typed
  /// first, so a phone left unlocked cannot be re-keyed by anyone holding it.
  static Future<String?> changePassword({
    required String currentPassword,
    required String newPassword,
  }) =>
      setNewPassword(
        newPassword: newPassword,
        currentPassword: currentPassword,
      );

  /// Whether this device's account has opened its verification link. Null when
  /// nobody is signed in or the column has not been added yet.
  static Future<bool?> verificationState() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? id = prefs.getString(idKey);
    if (id == null || id.isEmpty) return null;
    try {
      final Map<String, dynamic>? row = await Supabase.instance.client
          .from('players_profile')
          .select('verified')
          .eq('id', id)
          .maybeSingle();
      final dynamic value = row?['verified'];
      return value is bool ? value : null;
    } catch (error) {
      debugPrint('Could not read the verification state: $error');
      return null;
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

  /// 42703 is "undefined_column"; PGRST204 is PostgREST saying the column is
  /// not in its schema cache.
  static bool _isMissingColumn(PostgrestException error) =>
      error.code == '42703' ||
      error.code == 'PGRST204' ||
      error.message.contains('schema cache');

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
    await prefs.setBool(passwordChangeKey, false);
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

  /// Exposed so a test can prove the derivation itself is stable and salted;
  /// nothing in the app calls it directly.
  @visibleForTesting
  static String deriveForTesting(String password, String salt, int rounds) =>
      PasswordHash.derive(password, salt, rounds);

  static String? _validate(String email, String password) {
    if (!_emailPattern.hasMatch(email)) {
      return 'Enter a valid email address.';
    }
    return PasswordRules.problem(password);
  }
}
