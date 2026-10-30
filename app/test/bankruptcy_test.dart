import 'package:flutter_test/flutter_test.dart';
import 'package:mon/services/bankruptcy.dart';

BankruptcyDue _due(String id, double amount) =>
    BankruptcyDue(playerId: id, name: id, amount: amount);

double _sum(List<BankruptcyPayment> payments) =>
    payments.fold(0.0, (double sum, BankruptcyPayment p) => sum + p.paid);

void main() {
  test('a solvent estate pays every debt in full', () {
    final List<BankruptcyPayment> paid = Bankruptcy.split(
      500,
      <BankruptcyDue>[_due('a', 120), _due('b', 80)],
    );

    expect(paid, hasLength(2));
    expect(paid[0].paid, 120);
    expect(paid[1].paid, 80);
    expect(_sum(paid), 200);
  });

  test('a short estate is shared in proportion to what is owed', () {
    final List<BankruptcyPayment> paid = Bankruptcy.split(
      100,
      <BankruptcyDue>[_due('a', 300), _due('b', 100)],
    );

    expect(paid[0].paid, closeTo(75, 0.001));
    expect(paid[1].paid, closeTo(25, 0.001));
    expect(_sum(paid), closeTo(100, 0.0001));
  });

  test('nobody is paid more than they are owed, and no cent is lost', () {
    final List<BankruptcyPayment> paid = Bankruptcy.split(
      10,
      <BankruptcyDue>[_due('a', 10), _due('b', 10), _due('c', 10)],
    );

    expect(_sum(paid), closeTo(10, 0.0001));
    for (final BankruptcyPayment payment in paid) {
      expect(payment.paid, lessThanOrEqualTo(payment.due));
    }
  });

  test('a player owed nothing is left out of the payments', () {
    final List<BankruptcyPayment> paid = Bankruptcy.split(
      50,
      <BankruptcyDue>[_due('a', 50), _due('b', 0)],
    );

    expect(paid, hasLength(1));
    expect(paid.single.paid, 50);
  });

  test('nothing raised means nothing paid', () {
    final List<BankruptcyPayment> paid = Bankruptcy.split(
      0,
      <BankruptcyDue>[_due('a', 30)],
    );

    expect(paid, hasLength(1));
    expect(paid.single.paid, 0);
    expect(paid.single.paidInFull, isFalse);
  });
}
