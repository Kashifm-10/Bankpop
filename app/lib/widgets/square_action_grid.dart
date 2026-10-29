import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Sizes a grid of square cells from the height it is given.
///
/// The game screens put their action stickers beside a card - the player's
/// wallet, the bank's own - and those stickers have to be squares of one size
/// that add up to the card's height. Only the card knows that height, so this
/// widget reports no intrinsic height of its own beyond the smallest tappable
/// stickers: the card decides how tall the row is, and this widget turns that
/// height into one cell side and claims exactly the width the columns need.
///
/// Use it as the second half of an [IntrinsicHeight] + [Row] whose
/// `crossAxisAlignment` is [CrossAxisAlignment.stretch]:
///
/// ```dart
/// IntrinsicHeight(
///   child: Row(
///     crossAxisAlignment: CrossAxisAlignment.stretch,
///     children: <Widget>[
///       Expanded(child: card),
///       const SizedBox(width: 4),
///       SquareActionGrid(columns: 2, rows: 2, gap: 12, sectionWidth: width,
///         child: gridOfButtons),
///       const SizedBox(width: 16),
///     ],
///   ),
/// )
/// ```
class SquareActionGrid extends SingleChildRenderObjectWidget {
  const SquareActionGrid({
    super.key,
    required this.columns,
    required this.rows,
    required this.gap,
    required this.sectionWidth,
    required super.child,
  });

  final int columns;
  final int rows;

  /// The gutter between cells.
  final double gap;

  /// The width of the whole section, so the grid can leave the card a readable
  /// minimum instead of eating it alive.
  final double sectionWidth;

  @override
  RenderSquareActionGrid createRenderObject(BuildContext context) =>
      RenderSquareActionGrid(
        columns: columns,
        rows: rows,
        gap: gap,
        sectionWidth: sectionWidth,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSquareActionGrid renderObject,
  ) {
    renderObject
      ..columns = columns
      ..rows = rows
      ..gap = gap
      ..sectionWidth = sectionWidth;
  }
}

/// The cells of a [SquareActionGrid]: equal rows of equal columns.
///
/// The block is what makes the cells square - [SquareActionGrid] hands it a
/// width and a height that are already in the cells' proportion - so the rows
/// and the columns just divide it up. A grid with a cell to spare leaves it
/// empty rather than stretching the last sticker across two columns.
class SquareActionCells extends StatelessWidget {
  const SquareActionCells({
    super.key,
    required this.buttons,
    required this.columns,
    required this.rows,
    required this.gap,
  });

  final List<Widget> buttons;
  final int columns;
  final int rows;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: gap,
      children: <Widget>[
        for (int row = 0; row < rows; row++)
          Expanded(
            child: Row(
              spacing: gap,
              children: <Widget>[
                for (int column = 0; column < columns; column++)
                  Expanded(
                    child: row * columns + column < buttons.length
                        ? buttons[row * columns + column]
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The measurements of the sticker grid: one cell side, and the block those
/// cells add up to.
class _SquareGeometry {
  const _SquareGeometry({
    required this.side,
    required this.width,
    required this.height,
  });

  final double side;
  final double width;
  final double height;
}

/// Lays the sticker grid out as squares sized from the height it is given.
class RenderSquareActionGrid extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  RenderSquareActionGrid({
    required int columns,
    required int rows,
    required double gap,
    required double sectionWidth,
  })  : _columns = columns,
        _rows = rows,
        _gap = gap,
        _sectionWidth = sectionWidth;

  /// The card's own vertical margin, which the grid lines up with so both
  /// halves of the row share the same visible top and bottom.
  static const double _inset = 10;

  /// The gutter between the card and the grid, and the margin after the grid.
  static const double _gutterBefore = 4;
  static const double _marginAfter = 16;

  /// The card never drops below this, however much the squares would like.
  static const double _minCardWidth = 300;

  /// Below this a sticker is too small to tap; above it, bigger than any
  /// control here needs. The cap only bites on a very tall window, where a
  /// lone sticker would otherwise grow past the card beside it.
  static const double _minSide = 40;
  static const double _maxSide = 160;

  int get columns => _columns;
  int _columns;
  set columns(int value) {
    if (_columns == value) return;
    _columns = value;
    markNeedsLayout();
  }

  int get rows => _rows;
  int _rows;
  set rows(int value) {
    if (_rows == value) return;
    _rows = value;
    markNeedsLayout();
  }

  double get gap => _gap;
  double _gap;
  set gap(double value) {
    if (_gap == value) return;
    _gap = value;
    markNeedsLayout();
  }

  double get sectionWidth => _sectionWidth;
  double _sectionWidth;
  set sectionWidth(double value) {
    if (_sectionWidth == value) return;
    _sectionWidth = value;
    markNeedsLayout();
  }

  /// A cell is a square whose side comes from the row's height, since that is
  /// the side the whole block has to match. The width is only a floor: the grid
  /// gives way to the card's minimum rather than squeezing it.
  _SquareGeometry _geometry(double height) {
    final double byHeight = (height - (_rows - 1) * _gap) / _rows;
    final double byWidth = (_sectionWidth -
            _minCardWidth -
            _gutterBefore -
            _marginAfter -
            (_columns - 1) * _gap) /
        _columns;
    double side = byHeight < byWidth ? byHeight : byWidth;
    if (side > _maxSide) side = _maxSide;
    if (side < _minSide) side = _minSide;
    return _SquareGeometry(
      side: side,
      width: _columns * side + (_columns - 1) * _gap,
      height: _rows * side + (_rows - 1) * _gap,
    );
  }

  /// The band the cells may use: the row's height less the card's margins.
  double _innerHeight(BoxConstraints constraints) {
    final double natural = _rows * _minSide + (_rows - 1) * _gap;
    if (!constraints.hasBoundedHeight) return natural;
    final double inner = constraints.maxHeight - _inset * 2;
    return inner > 0 ? inner : 0;
  }

  double get _childTop {
    final double inner = size.height - _inset * 2;
    final double gridHeight = child?.size.height ?? 0;
    return _inset + (inner - gridHeight) / 2;
  }

  /// The row is at least tall enough for the smallest tappable stickers, so a
  /// short card stretches to meet them instead of squeezing them into a strip.
  /// This is the only intrinsic the grid reports: the card still decides the
  /// height whenever it needs more than this.
  @override
  double computeMaxIntrinsicHeight(double width) =>
      _rows * _minSide + (_rows - 1) * _gap + _inset * 2;

  @override
  double computeMinIntrinsicHeight(double width) =>
      computeMaxIntrinsicHeight(width);

  @override
  void performLayout() {
    final _SquareGeometry geometry = _geometry(_innerHeight(constraints));
    child?.layout(
      BoxConstraints.tightFor(
        width: geometry.width,
        height: geometry.height,
      ),
      parentUsesSize: true,
    );
    size = constraints.constrain(
      Size(geometry.width, geometry.height + _inset * 2),
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final _SquareGeometry geometry = _geometry(_innerHeight(constraints));
    return constraints.constrain(
      Size(geometry.width, geometry.height + _inset * 2),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    context.paintChild(child!, offset + Offset(0, _childTop));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final RenderBox? child = this.child;
    if (child == null) return false;
    return result.addWithPaintOffset(
      offset: Offset(0, _childTop),
      position: position,
      hitTest: (BoxHitTestResult result, Offset transformed) =>
          child.hitTest(result, position: transformed),
    );
  }
}
