/// The board is captured for the download from inside an overlay entry, where
/// there is no `Material` above it. Flutter's fallback default text style then
/// reaches every `Text` in the board, and that fallback is underlined in
/// yellow - which is what put a line under each printed card name while the
/// same board on screen had none. These pin the frame the download draws in.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mon/services/board_image.dart';
import 'package:mon/theme.dart';

void main() {
  testWidgets('the download frame carries no underline into the board',
      (WidgetTester tester) async {
    TextStyle? seen;
    await tester.pumpWidget(
      MaterialApp(
        theme: CustomTheme.lightThemeData(),
        home: Builder(
          builder: (BuildContext context) {
            final OverlayEntry entry = OverlayEntry(
              builder: (BuildContext overlayContext) {
                return BoardImage.frame(
                  overlayContext,
                  Builder(
                    builder: (BuildContext inner) {
                      seen = DefaultTextStyle.of(inner).style;
                      return const SizedBox(width: 40, height: 40);
                    },
                  ),
                );
              },
            );
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Overlay.of(context, rootOverlay: true).insert(entry);
            });
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(seen, isNotNull, reason: 'the frame was never built');
    expect(
      seen!.decoration ?? TextDecoration.none,
      isNot(TextDecoration.underline),
      reason: 'the board would print a line under every name',
    );
    expect(seen!.decorationColor, isNot(const Color(0xFFFF00)));
    // The screen draws the board with the theme's own text style, so the
    // download has to inherit the same family rather than a fallback font.
    expect(
      seen!.fontFamily,
      CustomTheme.lightThemeData().textTheme.bodyMedium!.fontFamily,
    );
  });
}
