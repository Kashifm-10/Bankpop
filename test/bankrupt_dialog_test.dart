// The bankruptcy dialog asks the one thing the bank cannot know - who the
// player owes - and has to fit a small phone, a landscape window and a desktop
// browser before it can ask it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mon/services/bankruptcy.dart';
import 'package:mon/widgets/app_frame.dart';
import 'package:mon/widgets/bankrupt_dialog.dart';

const BankruptcyPreview _preview = BankruptcyPreview(
  cash: 40,
  cards: 2,
  houses: 3,
  hotels: 0,
  buildingsValue: 75,
  mortgageValue: 60,
);

const List<BankruptcyCreditor> _creditors = <BankruptcyCreditor>[
  BankruptcyCreditor(playerId: 'a', name: 'Ameen'),
  BankruptcyCreditor(playerId: 'b', name: 'Priya'),
];

Widget _host(void Function(List<BankruptcyDue>?)? onResult) {
  return MaterialApp(
    builder: (BuildContext context, Widget? child) =>
        AppFrame(child: child ?? const SizedBox.shrink()),
    home: Builder(
      builder: (BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async {
              final List<BankruptcyDue>? result = await showBankruptcyDialog(
                context,
                creditors: _creditors,
                preview: _preview,
              );
              onResult?.call(result);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('no dues returns an empty list and nothing to pay',
      (WidgetTester tester) async {
    List<BankruptcyDue>? result;
    await tester.pumpWidget(_host((List<BankruptcyDue>? value) => result = value));
    await _open(tester);

    expect(find.text('Declare bankrupt?'), findsOneWidget);
    expect(find.text('₹175.00'), findsOneWidget); // 40 + 75 + 60

    await tester.tap(find.text('No dues'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result, isEmpty);
  });

  testWidgets('dues are collected per player and returned',
      (WidgetTester tester) async {
    List<BankruptcyDue>? result;
    await tester.pumpWidget(_host((List<BankruptcyDue>? value) => result = value));
    await _open(tester);

    await tester.tap(find.text('I owe players'));
    await tester.pumpAndSettle();
    expect(find.text('Who do you owe?'), findsOneWidget);

    // Nothing ticked: the dialog explains instead of closing.
    await tester.tap(find.text('Declare bankrupt'));
    await tester.pump();
    expect(find.textContaining('Pick at least one player'), findsOneWidget);
    expect(result, isNull);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '120');
    await tester.tap(find.byType(Checkbox).last);
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, '80');
    await tester.pump();

    expect(find.text('₹200.00'), findsOneWidget); // what is owed
    expect(find.textContaining('written off'), findsOneWidget);

    await tester.tap(find.text('Declare bankrupt'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result, hasLength(2));
    expect(result!.first.playerId, 'a');
    expect(result!.first.amount, 120);
    expect(result!.last.amount, 80);
  });

  testWidgets('the dialog fits a small phone, landscape and a desktop window',
      (WidgetTester tester) async {
    for (final Size size in <Size>[
      const Size(320, 568),
      const Size(800, 400),
      const Size(1440, 900),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_host(null));
      await _open(tester);
      expect(tester.takeException(), isNull,
          reason: 'the question overflowed at ${size.width}x${size.height}');

      await tester.tap(find.text('I owe players'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'the dues step overflowed at ${size.width}x${size.height}');
      expect(find.text('Who do you owe?'), findsOneWidget);

      // Drop the dialog so the next size starts from a clean route stack.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}
