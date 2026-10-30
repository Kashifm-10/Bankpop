import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mon/widgets/amount_keypad.dart';

/// The one keypad behind both payment flows. The old pair of dialogs had drifted
/// apart, so these tests pin the behaviour they now share: the amount is
/// validated before anything is charged, a refusal keeps the dialog open with
/// its sentence, and success closes it with true.
Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a valid amount is handed to the payment callback',
      (WidgetTester tester) async {
    double? charged;
    bool? result;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => Center(
            child: TextButton(
              onPressed: () async {
                result = await showAmountKeypad(
                  context,
                  title: 'Pay Ameen',
                  payee: 'Ameen',
                  holderName: 'Nadeem',
                  cardDigits: '1234',
                  onPay: (double amount) async {
                    charged = amount;
                    return null;
                  },
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await _open(tester);
    expect(find.text('Pay Ameen'), findsOneWidget);
    expect(find.text('Paying Ameen'), findsOneWidget);

    await tester.tap(find.text('1'));
    await tester.tap(find.text('2'));
    // The decimal point is a key of its own now, beside zero and backspace.
    await tester.tap(find.text('.'));
    await tester.tap(find.text('5'));
    await tester.pumpAndSettle();
    expect(find.text('12.5'), findsOneWidget);

    await tester.tap(find.text('PAY'));
    await tester.pumpAndSettle();

    expect(charged, 12.5);
    expect(result, isTrue);
    expect(find.text('Pay Ameen'), findsNothing);
  });

  testWidgets('an empty or zero amount never reaches the payment callback',
      (WidgetTester tester) async {
    int calls = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => Center(
            child: TextButton(
              onPressed: () => showAmountKeypad(
                context,
                title: 'Pay the bank',
                payee: 'the bank',
                holderName: 'Nadeem',
                cardDigits: '1234',
                onPay: (double amount) async {
                  calls++;
                  return null;
                },
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await _open(tester);

    // Nothing entered yet.
    await tester.tap(find.text('PAY'));
    await tester.pumpAndSettle();
    expect(find.text('Enter an amount above 0'), findsOneWidget);

    // A zero is not a payment either.
    await tester.tap(find.widgetWithText(ElevatedButton, '0'));
    await tester.tap(find.text('PAY'));
    await tester.pumpAndSettle();
    expect(find.text('Enter an amount above 0'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('a failed payment keeps the dialog open with its reason',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => Center(
            child: TextButton(
              onPressed: () => showAmountKeypad(
                context,
                title: 'Pay Ameen',
                payee: 'Ameen',
                holderName: 'Nadeem',
                cardDigits: '1234',
                onPay: (double amount) async => 'Insufficient balance',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await _open(tester);
    await tester.tap(find.text('5'));
    await tester.tap(find.text('PAY'));
    await tester.pumpAndSettle();

    expect(find.text('Insufficient balance'), findsOneWidget);
    expect(find.text('Pay Ameen'), findsOneWidget);
  });

  testWidgets('cancel closes without paying', (WidgetTester tester) async {
    bool? result;
    int calls = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => Center(
            child: TextButton(
              onPressed: () async {
                result = await showAmountKeypad(
                  context,
                  title: 'Pay Ameen',
                  payee: 'Ameen',
                  holderName: 'Nadeem',
                  cardDigits: '1234',
                  onPay: (double amount) async {
                    calls++;
                    return null;
                  },
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await _open(tester);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(result, isFalse);
    expect(calls, 0);
    expect(find.text('Pay Ameen'), findsNothing);
  });
}
