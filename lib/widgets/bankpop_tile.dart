import 'dart:math';
import 'package:flutter/material.dart';
import 'package:mon/models/bankpop_board.dart';

enum BoardSide { bottom, left, top, right, corner }

class BankpopTile extends StatelessWidget {
  final BankpopSpace space;
  final BoardSide side;
  final double width;
  final double height;
  final VoidCallback onTap;

  /// Name of the player holding this card.
  final String? ownerName;

  /// Buildings on the card.
  final int houses;
  final int hotels;

  /// True if the card is mortgaged.
  final bool mortgaged;

  const BankpopTile({
    super.key,
    required this.space,
    required this.side,
    required this.width,
    required this.height,
    required this.onTap,
    this.ownerName,
    this.houses = 0,
    this.hotels = 0,
    this.mortgaged = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool isTopEdge = space.index >= 20 && space.index <= 30;
    final bool isLeftEdge = space.index >= 10 && space.index <= 20;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFF4E0BF),
          border: Border(
            top: isTopEdge
                ? BorderSide.none
                : const BorderSide(color: Colors.black, width: 1.0),
            left: isLeftEdge
                ? BorderSide.none
                : const BorderSide(color: Colors.black, width: 1.0),
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildContent(),
            if (mortgaged)
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: const Text(
                    'M',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final Widget body = _buildTileBody();
    if (ownerName == null) return body;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        body,
        Center(child: _ownerChip()),
      ],
    );
  }

  Widget _ownerChip() {
    final double minDim = min(width, height);
    return RotatedBox(
      quarterTurns: _quarterTurns(side),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: (width > height ? width : height) * 0.92,
          maxHeight: height * 0.94,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        decoration: BoxDecoration(
          color: mortgaged
              ? Colors.red.shade100.withValues(alpha: 0.9)
              : Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(
          ownerName!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: (minDim * 0.30).clamp(6.0, 11.0).toDouble(),
            height: 1.1,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildTileBody() {
    if (side == BoardSide.corner) {
      return _buildCornerContent();
    }

    final bool hasStrip = space.isProperty &&
        space.color != null &&
        space.color != 'Station' &&
        space.color != 'Utility';

    final double minDim = min(width, height);
    final double iconSize = minDim * 0.6;

    Widget iconWidget = _rotatedIcon(side, iconSize);

    if (!hasStrip) {
      return iconWidget;
    }

    final stripColor = Color(BankpopBoard.colorForGroup(space.color));

    switch (side) {
      case BoardSide.bottom:
        return Column(
          children: [
            _buildStrip(stripColor, true),
            Expanded(child: iconWidget),
          ],
        );
      case BoardSide.top:
        return Column(
          children: [
            Expanded(child: iconWidget),
            _buildStrip(stripColor, true),
          ],
        );
      case BoardSide.left:
        return Row(
          children: [
            Expanded(child: iconWidget),
            _buildStrip(stripColor, false),
          ],
        );
      case BoardSide.right:
        return Row(
          children: [
            _buildStrip(stripColor, false),
            Expanded(child: iconWidget),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildStrip(Color color, bool isHorizontal) {
    BoxBorder border;
    switch (side) {
      case BoardSide.bottom:
        border = const Border(bottom: BorderSide(color: Colors.black, width: 1.0));
        break;
      case BoardSide.top:
        border = const Border(top: BorderSide(color: Colors.black, width: 1.0));
        break;
      case BoardSide.left:
        border = const Border(left: BorderSide(color: Colors.black, width: 1.0));
        break;
      case BoardSide.right:
        border = const Border(right: BorderSide(color: Colors.black, width: 1.0));
        break;
      default:
        border = const Border();
    }

    if (isHorizontal) {
      return Container(
        height: 14,
        width: double.infinity,
        decoration: BoxDecoration(color: color, border: border),
        child: _stripMarks(horizontal: true),
      );
    } else {
      return Container(
        width: 14,
        height: double.infinity,
        decoration: BoxDecoration(color: color, border: border),
        child: _stripMarks(horizontal: false),
      );
    }
  }

  Widget? _stripMarks({required bool horizontal}) {
    if (houses <= 0 && hotels <= 0) return null;

    final Widget dot = Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hotels > 0 ? Colors.red.shade700 : Colors.green.shade800,
      ),
    );
    final List<Widget> marks = hotels > 0
        ? <Widget>[dot]
        : <Widget>[for (int i = 0; i < houses; i++) dot];

    final Widget stack = horizontal
        ? Row(mainAxisSize: MainAxisSize.min, children: marks)
        : Column(mainAxisSize: MainAxisSize.min, children: marks);
    return Center(
      child: FittedBox(fit: BoxFit.scaleDown, child: stack),
    );
  }

  int _quarterTurns(BoardSide side) {
    switch (side) {
      case BoardSide.left:
        return 1;
      case BoardSide.top:
        return 2;
      case BoardSide.right:
        return 3;
      case BoardSide.bottom:
      case BoardSide.corner:
        return 0;
    }
  }

  Widget _rotatedIcon(BoardSide side, double size) {
    final int quarterTurns = _quarterTurns(side);

    Widget? content;
    bool isFullFill = false;
    String? imagePath;

    if (space.name.contains('Chance')) {
      imagePath = 'assets/images/Chance.png';
    } else if (space.name.contains('Community Chest')) {
      imagePath = 'assets/images/Community_Chest.png';
    } else if (space.name.contains('Station')) {
      imagePath = 'assets/images/Station.png';
    } else if (space.name.contains('Electric')) {
      imagePath = 'assets/images/Electric.png';
    } else if (space.name.contains('Water')) {
      imagePath = 'assets/images/Water.png';
    } else if (space.name.contains('Tax')) {
      imagePath = 'assets/images/Tax.png';
    }

    if (imagePath != null) {
      isFullFill = true;
      content = Image.asset(
        imagePath,
        fit: BoxFit.fill,
        errorBuilder: (context, error, stackTrace) {
          final fallbackIcon = _getIconForSpace(space.name) ?? Icons.broken_image;
          return Center(
              child: Icon(fallbackIcon, size: size, color: Colors.black87));
        },
      );
    } else {
      final icon = _getIconForSpace(space.name);
      if (icon != null) {
        content = Icon(icon, size: size, color: Colors.black87);
      }
    }

    if (content == null) return const SizedBox.shrink();

    return RotatedBox(
      quarterTurns: quarterTurns,
      child: isFullFill ? SizedBox.expand(child: content) : Center(child: content),
    );
  }

  IconData? _getIconForSpace(String name) {
    if (name.contains('Station')) return Icons.train;
    if (name.contains('Water')) return Icons.water_drop;
    if (name.contains('Electric')) return Icons.lightbulb;
    if (name.contains('Community Chest')) return Icons.card_giftcard;
    if (name.contains('Chance')) return Icons.question_mark;
    if (name.contains('Tax')) return Icons.money_off;
    return null;
  }

  Widget _buildCornerContent() {
    String? imagePath;

    switch (space.name) {
      case 'GO':
        imagePath = 'assets/images/Go.png';
        break;
      case 'Jail':
        imagePath = 'assets/images/Jail.png';
        break;
      case 'Free Parking':
        imagePath = 'assets/images/Free_Parking.png';
        break;
      case 'Go To Jail':
        imagePath = 'assets/images/Go_To_Jail.png';
        break;
    }

    if (imagePath != null) {
      return Image.asset(
        imagePath,
        width: width,
        height: height,
        fit: BoxFit.fill,
        errorBuilder: (context, error, stackTrace) => const Center(
          child: Icon(Icons.error_outline, color: Colors.red),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}