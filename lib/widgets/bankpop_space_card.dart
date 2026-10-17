import 'package:flutter/material.dart';
import 'package:mon/models/bankpop_board.dart';

Future<void> showBankpopSpaceCard(
    BuildContext context, BankpopSpace space) async {
  final isStation = space.color == 'Station';
  final isUtility = space.color == 'Utility';

  // Stations get a dark brown header, Utilities get a light grey header
  final headerColor = (isStation || isUtility)
      ? const Color.fromARGB(255, 0, 0, 0)
      : Color(BankpopBoard.colorForGroup(space.color));

  await showDialog(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(20),
      backgroundColor: Colors.transparent, // Let the Container handle the shape
      child: Container(
        width: 320,
        height: 520, // FIXED HEIGHT: fits full properties perfectly
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
                    if (isStation) _buildStationDeed(space),
                    if (isUtility) _buildUtilityDeed(space),
                    if (!isStation && !isUtility)
                      _buildColorPropertyDeed(space),
                  ],
                ),
              ),
            ),

            // Close Button anchored at the bottom
            Padding(
              padding: const EdgeInsets.only(bottom: 8, right: 12, top: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close', style: TextStyle(fontSize: 15)),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// 1. Standard Color Properties Layout
Widget _buildColorPropertyDeed(BankpopSpace space) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _row('Price', '£${space.price ?? '-'}'),
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
          _row(_rentLabel(space, i), '£${space.rent![i]}'),
        if (space.houseCost != null) ...[
          const Divider(
              height: 24,
              thickness: 1,
              color: Color(0xFFC2C2C2)), // Darkened divider
          _row('House cost', '£${space.houseCost}'),
          _row('Hotel cost', '£${space.hotelCost}'),
        ],
      ],
    ],
  );
}

// 2. Station Property Layout
Widget _buildStationDeed(BankpopSpace space) {
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
      _rowDots('RENT', '£${space.rent?[0] ?? 25}'),
      _rowDots('If 2 R.R.s are owned', '£${space.rent?[1] ?? 50}'),
      _rowDots('If 3 R.R.s are owned', '£${space.rent?[2] ?? 100}'),
      _rowDots('If 4 R.R.s are owned', '£${space.rent?[3] ?? 200}'),
    ],
  );
}

// 3. Utility Property Layout
Widget _buildUtilityDeed(BankpopSpace space) {
  final isElectric = space.name.contains('Electric');
  final imagePath = isElectric
      ? 'assets/images/Electric_nbg.png'
      : 'assets/images/Water_nbg.png';
  final fallbackIcon = isElectric ? Icons.lightbulb : Icons.water_drop;

  return Column(
    children: [
      const SizedBox(height: 24),
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