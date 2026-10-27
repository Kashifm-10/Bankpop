import 'package:flutter_test/flutter_test.dart';
import 'package:mon/models/bankpop_board.dart';

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
  test('each built-in country has its own money', () {
    expect(BoardCurrencies.forBoard('india'), '₹');
    expect(BoardCurrencies.forBoard('usa'), r'$');
    expect(BoardCurrencies.forBoard('uk'), '£');
    expect(BoardCurrencies.forBoard('france'), '€');
    expect(BoardCurrencies.forBoard('japan'), '¥');
    expect(BoardCurrencies.forBoard('brazil'), r'R$');
    expect(BoardCurrencies.forBoard('uae'), 'AED');
  });

  test('an unknown board reads the default currency', () {
    expect(BoardCurrencies.forBoard('custom_unknown'), BoardCurrencies.fallback);
  });

  test('a price takes the symbol of its board', () {
    expect(BoardCurrencies.format('₹', 200), '₹200');
    expect(BoardCurrencies.format(r'$', 60), r'$60');
    expect(BoardCurrencies.format('AED', 200), 'AED 200');
    // A wallet value arrives as a double; it is printed like the board.
    expect(BoardCurrencies.format('£', 200.0), '£200');
    expect(BoardCurrencies.format('£', 12.5), '£12.5');
  });

  test('a board row without a symbol falls back to its country', () {
    expect(_board(boardId: 'india').currency, '₹');
    expect(_board().currency, r'$');
  });

  test('a stored symbol is the board\'s own', () {
    expect(_board(boardId: 'india', currency: '€').currency, '€');
    expect(_board(boardId: 'custom_1', currency: r'R$').currency, r'R$');
  });

  test('a custom board without a symbol reads the default', () {
    expect(_board(boardId: 'custom_1').currency, BoardCurrencies.fallback);
  });

  test('the symbol survives the row the cache stores', () {
    final BankpopBoard board = _board(boardId: 'custom_1', currency: 'AED');
    expect(board.toMap()['currency'], 'AED');
    expect(BankpopBoard.fromMap(board.toMap()).currency, 'AED');
  });

  test('renaming a board keeps its money unless another is given', () {
    final BankpopBoard board = _board(boardId: 'custom_1', currency: '₹');
    expect(
      board.renamed(renames: const <String, String>{}, name: 'New').currency,
      '₹',
    );
    expect(
      board
          .renamed(renames: const <String, String>{}, name: 'New', currency: '€')
          .currency,
      '€',
    );
  });
}
