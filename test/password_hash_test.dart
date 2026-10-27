import 'package:flutter_test/flutter_test.dart';
import 'package:mon/services/account.dart';

/// The password path has no server to check it: the hash written at sign-up is
/// the only thing a later sign-in can compare against. These tests pin the two
/// properties that makes work - same input, same hash; different salt,
/// different hash - without needing a database.
void main() {
  test('the same password and salt derive the same hash', () {
    final String first = Account.deriveForTesting('hunter2', 'salt-a', 50);
    final String second = Account.deriveForTesting('hunter2', 'salt-a', 50);

    expect(second, first);
  });

  test('a different salt gives a different hash for the same password', () {
    final String first = Account.deriveForTesting('hunter2', 'salt-a', 50);
    final String second = Account.deriveForTesting('hunter2', 'salt-b', 50);

    expect(second, isNot(first));
  });

  test('a different password gives a different hash', () {
    final String first = Account.deriveForTesting('hunter2', 'salt-a', 50);
    final String second = Account.deriveForTesting('hunter3', 'salt-a', 50);

    expect(second, isNot(first));
  });

  test('changing the work factor changes the hash', () {
    final String first = Account.deriveForTesting('hunter2', 'salt-a', 50);
    final String second = Account.deriveForTesting('hunter2', 'salt-a', 51);

    expect(second, isNot(first));
  });

  test('the default work factor is strong enough to be worth storing', () {
    expect(Account.iterations, greaterThanOrEqualTo(20000));
  });
}
