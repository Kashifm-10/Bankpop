// "Take rent" used to open the barrier and nothing else: qr_flutter's
// QrImageView lays itself out with a LayoutBuilder, and Flutter's Dialog
// measures its children with an IntrinsicWidth, which is not allowed to ask a
// LayoutBuilder for a size. The dialog threw while laying out - so the screen
// was dimmed, stuck, with no code on it. These pin the window opening with its
// code, and closing on its Close control.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mon/widgets/app_frame.dart';
import 'package:mon/widgets/qr_box.dart';
import 'package:mon/widgets/rent_qr_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{'playerID': 'p1'});
    // A URL that refuses connections: the wallet read fails, is caught, and the
    // dialog keeps the code it drew before any data arrived.
    await Supabase.initialize(
      url: 'http://127.0.0.1:9',
      anonKey: 'test-anon-key',
    );
  });

  testWidgets('the rent window opens with its code and its figure',
      (WidgetTester tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            AppFrame(child: child ?? const SizedBox.shrink()),
        home: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () async {
              result = await showRentQrDialog(
                context,
                gameId: 'ABC12',
                playerId: 'p1',
                playerName: 'Ameen',
                cardName: 'Riverside Walk',
                currency: '¥',
                amount: 200,
              );
            },
            child: const Text('rent'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('rent'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The dialog is up, with the card, the figure and the code on it - and it
    // laid out without the assertion the LayoutBuilder used to raise.
    expect(tester.takeException(), isNull);
    // The title and the caption both name the card.
    expect(find.textContaining('Riverside Walk'), findsWidgets);
    expect(find.text('¥200'), findsOneWidget);
    expect(find.byType(QrBox), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('the code is drawn where the dialog puts it',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: QrBox(
              data: '{"type":"pay"}',
              size: 200,
              padding: EdgeInsets.all(8),
            ),
          ),
        ),
      ),
    );

    final QrBox box = tester.widget<QrBox>(find.byType(QrBox));
    expect(tester.getSize(find.byType(QrBox)),
        const Size(200, 200));
    expect(box.data, '{"type":"pay"}');
    expect(tester.takeException(), isNull);
  });
}
