import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/widgets/bankpop_space_card.dart';

const BankpopSpace _beggarAlley = BankpopSpace(
  index: 1,
  name: "Beggar's Alley",
  type: 'Property',
  price: 60,
  rent: <int>[2, 10, 30, 90, 160, 250],
  color: 'Brown',
  houseCost: 50,
  hotelCost: 50,
);

/// The deed is opened from a dialog, so the tests need a screen with a button
/// that does what the banker screen does.
Widget _opener(Future<void> Function(BuildContext) onPressed, String label) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (BuildContext context) => Center(
          child: TextButton(
            onPressed: () => onPressed(context),
            child: Text(label),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('the deed runs the card action the caller passes in',
      (WidgetTester tester) async {
    bool sold = false;

    await tester.pumpWidget(_opener((BuildContext context) {
      return showBankpopSpaceCard(
        context,
        _beggarAlley,
        actionWidget: Builder(
          builder: (BuildContext deedContext) => TextButton(
            onPressed: () {
              sold = true;
              // The action closes the deed itself, so its own follow-up opens
              // over the screen instead of on top of the deed.
              Navigator.of(deedContext).pop();
            },
            child: const Text('Show QR'),
          ),
        ),
      );
    }, 'open'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The deed itself is unchanged, with the price still on it.
    expect(find.text('£60'), findsOneWidget);
    expect(find.text('Show QR'), findsOneWidget);

    await tester.tap(find.text('Show QR'));
    await tester.pumpAndSettle();

    expect(sold, isTrue);
    expect(find.text('Show QR'), findsNothing);
  });

  testWidgets('a deed without an action shows only Close',
      (WidgetTester tester) async {
    await tester.pumpWidget(_opener((BuildContext context) {
      return showBankpopSpaceCard(context, _beggarAlley);
    }, 'open'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Show QR'), findsNothing);
    expect(find.text('Assign to player'), findsNothing);
  });
}
