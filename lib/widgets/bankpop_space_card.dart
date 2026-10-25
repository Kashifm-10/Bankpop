import 'package:flutter/material.dart';
import 'package:mon/models/bankpop_board.dart';

/// The deed for one board space.
///
/// [actionWidget] is drawn in the footer next to Close, so a caller can offer an
/// action for the space it just showed ("Sell this card" in a cards game), or the
/// face and name of whoever owns it. The widget closes this dialog itself when it
/// is tapped, which lets it open its own follow-up instead of stacking another
/// route on top of the deed.
///
/// [houses] and [hotels] say what is already built: every rent row that has been
/// bought carries a tick, whether this deed was opened from the board or from the
/// player's own cards. [onBuild], which only the player's card detail passes,
/// puts a plus on the row that would be bought next; a tap approved by the banker
/// increments the counts held here, so that plus becomes a tick without the deed
/// being reopened.
Future<void> showBankpopSpaceCard(
  BuildContext context,
  BankpopSpace space, {
  Widget? actionWidget,
  int houses = 0,
  int hotels = 0,
  Future<bool> Function(int step)? onBuild,
  String currency = BoardCurrencies.fallback,
}) async {
  await showDialog(
    context: context,
    builder: (_) => _SpaceCardDialog(
      space: space,
      actionWidget: actionWidget,
      houses: houses,
      hotels: hotels,
      onBuild: onBuild,
      currency: currency,
    ),
  );
}

class _SpaceCardDialog extends StatefulWidget {
  const _SpaceCardDialog({
    required this.space,
    this.actionWidget,
    this.houses = 0,
    this.hotels = 0,
    this.onBuild,
    this.currency = BoardCurrencies.fallback,
  });

  final BankpopSpace space;
  final Widget? actionWidget;
  final int houses;
  final int hotels;
  final Future<bool> Function(int step)? onBuild;
  final String currency;

  @override
  State<_SpaceCardDialog> createState() => _SpaceCardDialogState();
}

class _SpaceCardDialogState extends State<_SpaceCardDialog> {
  late int houses = widget.houses;
  late int hotels = widget.hotels;

  /// True while a request is with the banker, so a double tap cannot ask twice.
  bool _building = false;

  Future<void> _buy(int step) async {
    final Future<bool> Function(int step)? onBuild = widget.onBuild;
    if (onBuild == null || _building) return;
    setState(() => _building = true);
    final bool approved = await onBuild(step);
    if (!mounted) return;
    setState(() {
      _building = false;
      if (!approved) return;
      if (step >= 5) {
        hotels = 1;
      } else {
        houses += 1;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final BankpopSpace space = widget.space;
    final bool isStation = space.color == 'Station';
    final bool isUtility = space.color == 'Utility';

    // Stations get a dark brown header, Utilities get a light grey header
    final headerColor = (isStation || isUtility)
        ? const Color.fromARGB(255, 0, 0, 0)
        : Color(BankpopBoard.colorForGroup(space.color));

    // The deed was a fixed 320x520 dialog. That is wider than the content box
    // of a 320 px phone and taller than a landscape phone window, so it now
    // shrinks to whatever the window can actually show; the body scrolls.
    final Size screen = MediaQuery.sizeOf(context);
    final double cardWidth = (screen.width - 40).clamp(180.0, 320.0);
    final double cardHeight = (screen.height - 40).clamp(220.0, 520.0);

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      backgroundColor: Colors.transparent, // Let the Container handle the shape
      child: Container(
        width: cardWidth,
        height: cardHeight,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            // Header strip
            Container(
              height: 60,
              decoration: BoxDecoration(
                color: headerColor,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              alignment: Alignment.center,
              child: Text(
                space.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

            // Expanded + ScrollView guarantees no overflow errors
            // while keeping the card size and Close button fixed.
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (isStation)
                      _buildStationDeed(space, widget.currency),
                    if (isUtility) _buildUtilityDeed(space, widget.currency),
                    if (!isStation && !isUtility)
                      _buildColorPropertyDeed(
                        space,
                        currency: widget.currency,
                        houses: houses,
                        hotels: hotels,
                        building: _building,
                        onBuy: widget.onBuild == null ? null : _buy,
                      ),
                  ],
                ),
              ),
            ),

            // Footer anchored at the bottom: optional action on the left,
            // Close on the right.
            Padding(
              padding:
                  const EdgeInsets.only(bottom: 8, left: 12, right: 12, top: 8),
              child: Row(
                children: [
                  // The action gets the space it needs to shrink when it is wide
                  // (an owner's name, say) instead of pushing Close off the row,
                  // and still starts at the left at its natural size.
                  if (widget.actionWidget != null)
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: widget.actionWidget,
                      ),
                    )
                  else
                    const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close', style: TextStyle(fontSize: 15)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 1. Standard Color Properties Layout
//
// Each rent row can carry a mark: a tick for a level that has been bought, or a
// plus for the one level that could be bought next.
Widget _buildColorPropertyDeed(
  BankpopSpace space, {
  required String currency,
  required int houses,
  required int hotels,
  required bool building,
  required Future<void> Function(int step)? onBuy,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _row(
        'Price',
        space.price == null
            ? '-'
            : BoardCurrencies.format(currency, space.price!),
      ),
      const Divider(
          height: 24,
          thickness: 1,
          color: Color(0xFFC2C2C2)), // Darkened divider slightly
      if (space.rent != null) ...[
        const Center(
          child: Text('RENT',
              style: TextStyle(
                  fontWeight: FontWeight.w600, // Made slightly bolder
                  fontSize: 15,
                  letterSpacing: 1.5,
                  color: Colors.black)), // Solid black
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < space.rent!.length; i++)
          _rentRow(
            _rentLabel(space, i),
            BoardCurrencies.format(currency, space.rent![i]),
            built: (i >= 1 && i <= 4 && houses >= i) || (i == 5 && hotels > 0),
            // One plus only: the very next level this card could take.
            buy: onBuy != null && _isNextStep(i, houses, hotels)
                ? () => onBuy(i)
                : null,
            building: building,
          ),
        if (space.houseCost != null) ...[
          const Divider(
              height: 24,
              thickness: 1,
              color: Color(0xFFC2C2C2)), // Darkened divider
          if (space.houseCost != null)
            _row('House cost', BoardCurrencies.format(currency, space.houseCost!)),
          if (space.hotelCost != null)
            _row('Hotel cost', BoardCurrencies.format(currency, space.hotelCost!)),
        ],
      ],
    ],
  );
}

/// Row `i` is the next buy when it is the level immediately above what is built:
/// house 1 when there are none, house 3 when there are two, and the hotel only
/// once all four houses are up. Rows below what is built carry their tick
/// instead, and everything else is history or out of reach.
bool _isNextStep(int i, int houses, int hotels) {
  if (hotels > 0) return false;
  if (i == 5) return houses >= 4;
  if (i < 1 || i > 4) return false;
  return houses < 4 && i == houses + 1;
}

Widget _rentRow(
  String label,
  String value, {
  required bool built,
  required VoidCallback? buy,
  required bool building,
}) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          // The label takes the slack, so the value stays hard against the right
          // edge the way every other row on the deed sits - the mark just to its
          // left rather than trailing the row.
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500),
            ),
          ),
          if (built)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child:
                  Icon(Icons.check_circle, size: 16, color: Color(0xFF689F38)),
            )
          else if (buy != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: SizedBox(
                width: 26,
                height: 26,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  iconSize: 24,
                  color: const Color(0xFF689F38),
                  tooltip: 'Ask the banker to build here',
                  onPressed: building ? null : buy,
                  icon: const Icon(Icons.add_circle),
                ),
              ),
            ),
          Text(value,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600, // Made bolder
                  color: Colors.black)),
        ],
      ),
    );

// 2. Station Property Layout
Widget _buildStationDeed(BankpopSpace space, String currency) {
  String rent(int i, int fallback) =>
      BoardCurrencies.format(currency, space.rent?[i] ?? fallback);
  return Column(
    children: [
      const SizedBox(height: 24),
      Image.asset(
        'assets/images/Station_nbg.png',
        height: 170,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.train, size: 80, color: Colors.black),
      ),
      const SizedBox(height: 40),
      _rowDots('RENT', rent(0, 25)),
      _rowDots('If 2 R.R.s are owned', rent(1, 50)),
      _rowDots('If 3 R.R.s are owned', rent(2, 100)),
      _rowDots('If 4 R.R.s are owned', rent(3, 200)),
    ],
  );
}

// 3. Utility Property Layout
Widget _buildUtilityDeed(BankpopSpace space, String currency) {
  final isElectric = space.name.contains('Electric');
  final imagePath = isElectric
      ? 'assets/images/Electric_nbg.png'
      : 'assets/images/Water_nbg.png';
  final fallbackIcon = isElectric ? Icons.lightbulb : Icons.water_drop;

  return Column(
    children: [
      const SizedBox(height: 24),
      if (space.price != null && space.price! > 0)
        _row('Price', BoardCurrencies.format(currency, space.price!)),
      Image.asset(
        imagePath,
        height: 170,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            Icon(fallbackIcon, size: 80, color: Colors.black),
      ),
      const SizedBox(height: 40),
      const Text(
        "If one \"Utility\" is owned,\nrent is 4 times amount\nshown on dice.",
        textAlign: TextAlign.center,
        style: TextStyle(
            fontSize: 14,
            height: 1.4,
            color: Colors.black,
            fontWeight: FontWeight.w500), // Darkened
      ),
      const SizedBox(height: 16),
      const Text(
        "If both \"Utilities\" are\nowned, rent is 10 times\namount shown on dice.",
        textAlign: TextAlign.center,
        style: TextStyle(
            fontSize: 14,
            height: 1.4,
            color: Colors.black,
            fontWeight: FontWeight.w500), // Darkened
      ),
    ],
  );
}

String _rentLabel(BankpopSpace space, int i) {
  switch (i) {
    case 0:
      return 'Rent';
    case 1:
      return 'With 1 House';
    case 2:
      return 'With 2 Houses';
    case 3:
      return 'With 3 Houses';
    case 4:
      return 'With 4 Houses';
    case 5:
      return 'With HOTEL';
  }
  return 'Rent $i';
}

Widget _row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Darkened label from black54 to black87
          Text(label,
              style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500)),
          // Darkened value to solid black
          Text(value,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600, // Made bolder
                  color: Colors.black)),
        ],
      ),
    );

// Helper for the dots in the Station deed
Widget _rowDots(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          // Darkened label
          Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '. . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .',
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.black54), // Darkened dots from grey.shade400
            ),
          ),
          const SizedBox(width: 4),
          // Darkened value
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black)),
        ],
      ),
    );

Future<void> showBankpopSpecialInfo(BuildContext context, String name) async {
  String? imagePath;

  // Match exactly with your asset file names
  switch (name) {
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

  // Catch Income Tax and Luxury Tax
  if (name.contains('Tax')) {
    imagePath = 'assets/images/Tax.png';
  }

  await showDialog(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(20),
      backgroundColor: Colors.transparent,
      child: Container(
        width: 320,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        // ClipRRect ensures the image doesn't bleed over the rounded corners
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Column(
            mainAxisSize: MainAxisSize.min, // Hugs the content perfectly
            children: [
              // 1. Show edge-to-edge image if available
              if (imagePath != null)
                Image.asset(
                  imagePath,
                  width: 320,
                  fit: BoxFit.contain, // Fills the dialog width cleanly
                  errorBuilder: (context, error, stackTrace) => const Padding(
                    padding: EdgeInsets.all(40.0),
                    child: Icon(Icons.error_outline,
                        size: 80, color: Colors.black),
                  ),
                )
              // 2. Fallback for any other missing special space
              else
                Padding(
                  padding: const EdgeInsets.all(40.0),
                  child: Text(
                    name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
