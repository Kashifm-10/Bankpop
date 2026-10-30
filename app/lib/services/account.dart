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
/// first. [SignUpResult.mailProblem] reports the one thing that can go wrong
/// after the row is written - the verification mail could not be sent. The
/// account is kept when that happens, because the sign-in screen can send
/// another link the moment the mail service is back: deleting it would mean
/// typing the whole form again, and the address would be taken by a row nobody
/// could enter.
class SignUpResult {
  const SignUpResult.created(this.email, {this.mailProblem}) : error = null;
  const SignUpResult.failed(this.error)
      : email = null,
        mailProblem = null;

  final String? email;
  final String? error;

  /// Set when the account exists but its verification mail did not go out.
  final String? mailProblem;

  bool get ok => error == null;

  /// True when the account was created and the mail is on its way.
  bool get mailSent => ok && mailProblem == null;
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
        // The account stays. Signing in is refused until the address is
        // verified either way, and the sign-in screen can send a fresh link
        // (AccountMail.resendVerification) without the password - so a mail
        // service that is down no longer throws the sign-up away.
        debugPrint('The verification mail did not go out: ${mail.message}');
        return SignUpResult.created(address, mailProblem: mail.message);
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

  /// The player id this device played under while nobody was signed in, or
  /// null when an account already owns this device or nothing was ever played.
  ///
  /// Read before a sign-in, because signing in moves `playerID` to the
  /// account's id - after that the guest id is no longer on the device.
  static Future<String?> guestPlayerId() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? email = prefs.getString(emailKey);
    if (email != null && email.isNotEmpty) return null;
    final String? id = prefs.getString('playerID');
    return id == null || id.isEmpty ? null : id;
  }

  /// Whether [playerId] played at least one game on the server.
  static Future<bool> hasGames(String playerId) async {
    if (playerId.isEmpty) return false;
    try {
      final List<dynamic> rows = await Supabase.instance.client
          .from('players_test')
          .select('game_id')
          .eq('player_id', playerId)
          .limit(1);
      return rows.isNotEmpty;
    } catch (error) {
      debugPrint('Could not check the guest games: $error');
      return false;
    }
  }

  /// Points every row that belonged to a guest at the account that just signed
  /// in, so the games played before signing in show up under the account too.
  ///
  /// Returns how many game seats moved. Best effort per table: an old project
  /// may be missing some of them, and one missing table must not leave the
  /// others untouched.
  static Future<int> adoptGuestGames({
    required String guestId,
    required String accountId,
  }) async {
    if (guestId.isEmpty || accountId.isEmpty || guestId == accountId) return 0;

    // A seat is what lists the game, so this is the count worth reporting.
    int moved = 0;
    try {
      final List<dynamic> rows = await Supabase.instance.client
          .from('players_test')
          .select('game_id')
          .eq('player_id', guestId);
      moved = rows.length;
    } catch (error) {
      debugPrint('Could not count the guest seats: $error');
    }

    await _repoint('players_test', 'player_id', guestId, accountId);
    await _repoint('request_test', 'player_id', guestId, accountId);
    await _repoint('card_requests', 'player_id', guestId, accountId);
    await _repoint('deal_requests', 'from_id', guestId, accountId);
    await _repoint('deal_requests', 'to_id', guestId, accountId);
    await _repoint('game_sessions', 'banker_id', guestId, accountId);

    // transactions and player_cards keep the id inside `code` as well, and a
    // trigger refills their id columns whenever `code` changes - so the code is
    // what has to be rewritten.
    await _repointCode('transactions', guestId, accountId);
    await _repointCode('player_cards', guestId, accountId);

    return moved;
  }

  static Future<void> _repoint(
    String table,
    String column,
    String from,
    String to,
  ) async {
    try {
      await Supabase.instance.client
          .from(table)
          .update(<String, dynamic>{column: to}).eq(column, from);
    } catch (error) {
      // A table that does not exist yet (its SQL file was never run) is fine:
      // there is nothing in it to move.
      debugPrint('Could not move $table.$column from the guest id: $error');
    }
  }

  /// Rewrites `<payer>_<receiver>` codes that mention [from], one row at a
  /// time; the row's id columns follow the code through their trigger.
  static Future<void> _repointCode(
    String table,
    String from,
    String to,
  ) async {
    try {
      final List<dynamic> rows = await Supabase.instance.client
          .from(table)
          .select('id, code')
          .like('code', '%$from%');
      for (final dynamic raw in rows) {
        final Map<String, dynamic> row = (raw as Map).cast<String, dynamic>();
        final String code = row['code']?.toString() ?? '';
        if (!code.contains(from)) continue;
        await Supabase.instance.client
            .from(table)
            .update(<String, dynamic>{'code': code.replaceAll(from, to)})
            .eq('id', row['id']);
      }
    } catch (error) {
      debugPrint('Could not move the $table codes from the guest id: $error');
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
