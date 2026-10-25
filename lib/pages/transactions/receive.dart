import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mon/widgets/game_controls.dart';
import 'package:mon/widgets/qr_box.dart';
import 'package:mon/widgets/app_metrics.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReceiveButton extends StatelessWidget {
  const ReceiveButton({super.key});

  Future<void> _showValueDialog(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final playerID = prefs.getString('playerID') ?? 'UnknownPlayer';

    // Name shown in the QR must match the roster:
    //  - banker row is stored in the DB as 'Bank'
    //  - player row is stored as their profile_name
    // Both are mirrored into prefs at game start / join, so no DB read here.
    final name = prefs.getString('display_name') ??
        prefs.getString('profile_name') ??
        'Bank';

    // Which side of the payment this device is on. Baked into the QR so the
    // scanner can call transfer_money with the correct toRole.
    final role = prefs.getString('role') ?? 'player';

    if (!context.mounted) return;
    final TextEditingController controller = TextEditingController();

    // ignore: use_build_context_synchronously
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Enter Value'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: 'Enter amount'),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isNotEmpty) {
                  Navigator.of(context).pop(); // Close dialog
                  _showQrCode(context, playerID, name, value, role);
                }
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _showQrCode(BuildContext context, String playerID, String name,
      String value, String role) {
    final qrData = jsonEncode({
      'playerID': playerID,
      'name': name,
      'value': value,
      'role': role,
    });

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          name,
          style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        content: SizedBox(
          width: 60.w,
          height: 70.w,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QrBox(
                data: qrData,
                size: 50.w,
              ),
              SizedBox(height: 2.h),
              Text('Value: $value',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 16.sp)),
            ],
          ),
        ),
        /*  actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text("Close", style: TextStyle(fontSize: 16.sp)),
        )
      ], */
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The same sticker tile the rest of the game screens use: the label lives
    // in the tooltip and in the info sheet, not in the button.
    return GameIconButton(
      control: GameControls.receive,
      onPressed: () => _showValueDialog(context),
    );
  }
}
