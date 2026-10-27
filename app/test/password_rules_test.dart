import 'package:flutter_test/flutter_test.dart';
import 'package:mon/services/password.dart';

/// The rules and the hash are what sign-up, a forced reset and a password
/// change all share. These tests pin the sentences a screen can show and the
/// comparison that decides whether a typed password opens an account.
void main() {
  group('PasswordRules', () {
    test('accepts a password with letters, digits and enough length', () {
      expect(PasswordRules.problem('gameNight2026'), isNull);
    });

    test('refuses a short password', () {
      expect(PasswordRules.problem('abc123'), 'Use at least 8 characters.');
    });

    test('refuses a password without a letter', () {
      expect(PasswordRules.problem('12345678'), 'Include at least one letter.');
    });

    test('refuses a password without a digit', () {
      expect(
          PasswordRules.problem('onlyletters'), 'Include at least one number.');
    });

    test('the hint names both requirements', () {
      expect(PasswordRules.hint, contains('8 characters'));
      expect(PasswordRules.hint, contains('letter'));
      expect(PasswordRules.hint, contains('number'));
    });
  });

  group('PasswordHash', () {
    test('matches a password it derived itself', () {
      final String salt = PasswordHash.newSalt();
      final String hash = PasswordHash.derive('hunter22', salt, 50);

      expect(
        PasswordHash.matches(
          password: 'hunter22',
          salt: salt,
          rounds: 50,
          expected: hash,
        ),
        isTrue,
      );
    });

    test('refuses the wrong password', () {
      final String salt = PasswordHash.newSalt();
      final String hash = PasswordHash.derive('hunter22', salt, 50);

      expect(
        PasswordHash.matches(
          password: 'hunter23',
          salt: salt,
          rounds: 50,
          expected: hash,
        ),
        isFalse,
      );
    });

    test('refuses an account with no reset password', () {
      expect(
        PasswordHash.matches(
          password: 'anything',
          salt: '',
          rounds: 20000,
          expected: '',
        ),
        isFalse,
      );
    });

    test('two accounts with the same password do not share a hash', () {
      final String saltA = PasswordHash.newSalt();
      final String saltB = PasswordHash.newSalt();
      expect(
        PasswordHash.derive('hunter22', saltA, 50),
        isNot(PasswordHash.derive('hunter22', saltB, 50)),
      );
    });
  });
}
