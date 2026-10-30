import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/theme.dart';

BankpopBoard _board({
  String boardId = 'usa',
  String currency = '',
}) {
  return BankpopBoard.fromMap(<String, dynamic>{
    'board_id': boardId,
    'name': 'Test Land',
    'flag': '',
    if (currency.isNotEmpty) 'currency': currency,
    'spaces': const <Map<String, dynamic>>[],
    'cards': const <String, dynamic>{},
  });
}

void main() {
  const String mark = BoardCurrencies.mark;

  test('the sign is the BankPop mark, not a national currency', () {
    expect(mark, '\uE000');
    expect(BoardCurrencies.fallback, mark);
    expect(BoardCurrencies.choices, <String>[mark]);
  });

  test('the light cut is the same sign in its own glyph', () {
    // One family, two characters: the heavy sign for prices, the light one for
    // small print. Both are one character long, so an amount stays a string.
    expect(BoardCurrencies.markLight, '\uE001');
    expect(BoardCurrencies.markLight.length, 1);
    expect(BoardCurrencies.formatLight(60), '${BoardCurrencies.markLight}60');
  });

  testWidgets('every text style falls back to the sign\'s font',
      (WidgetTester tester) async {
    for (final Brightness brightness in Brightness.values) {
      final TextTheme theme = CustomTheme.textThemeFor(brightness);
      for (final TextStyle? style in <TextStyle?>[
        theme.displayLarge,
        theme.titleLarge,
        theme.bodyMedium,
        theme.labelSmall,
      ]) {
        expect(style?.fontFamilyFallback, contains(CustomTheme.markFamily));
      }
    }
    // The family the pubspec declares for assets/fonts/BankpopMark.ttf.
    expect(CustomTheme.markFamily, 'BankpopMark');
  });

  test('every board is quoted in the same sign', () {
    expect(BoardCurrencies.forBoard('india'), mark);
    expect(BoardCurrencies.forBoard('usa'), mark);
    expect(BoardCurrencies.forBoard('uk'), mark);
    expect(BoardCurrencies.forBoard('france'), mark);
    expect(BoardCurrencies.forBoard('japan'), mark);
    expect(BoardCurrencies.forBoard('brazil'), mark);
    expect(BoardCurrencies.forBoard('uae'), mark);
    expect(BoardCurrencies.forBoard('custom_unknown'), mark);
  });

  test('a price takes the sign of its board', () {
    expect(BoardCurrencies.format(mark, 200), '${mark}200');
    // A wallet value arrives as a double; it is printed like the board.
    expect(BoardCurrencies.format(mark, 200.0), '${mark}200');
    expect(BoardCurrencies.format(mark, 12.5), '${mark}12.5');
  });

  test('a board row reads the mark, with or without a stored sign', () {
    expect(_board(boardId: 'india').currency, mark);
    expect(_board().currency, mark);
    expect(_board(boardId: 'custom_1').currency, mark);
  });

  test('a sign stored by an older board is replaced, not printed', () {
    expect(_board(boardId: 'india', currency: '\u20B9').currency, mark);
    expect(_board(boardId: 'custom_1', currency: r'R$').currency, mark);
  });

  test('the row the cache stores carries the mark', () {
    final BankpopBoard board = _board(boardId: 'custom_1');
    expect(board.toMap()['currency'], mark);
    expect(BankpopBoard.fromMap(board.toMap()).currency, mark);
  });

  test('renaming a board keeps the mark', () {
    final BankpopBoard board = _board(boardId: 'custom_1', currency: '\u20B9');
    expect(
      board.renamed(renames: const <String, String>{}, name: 'New').currency,
      mark,
    );
  });

  test('board copy is rewritten to the one sign', () {
    expect(BoardCurrencies.write('Collect \u00A350'), 'Collect ${mark}50');
    expect(BoardCurrencies.write('Pay \u20B9200'), 'Pay ${mark}200');
    expect(
      BoardCurrencies.write('Advance to Go (Collect \u20AC200)'),
      'Advance to Go (Collect ${mark}200)',
    );
    // Text with no money in it is left exactly as it is.
    expect(BoardCurrencies.write('Go to Jail'), 'Go to Jail');
  });
}
