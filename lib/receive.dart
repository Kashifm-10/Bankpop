import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReceiveButton extends StatelessWidget {
  const ReceiveButton({super.key});

  Future<void> _showValueDialog(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final playerID = prefs.getString('playerID') ?? 'UnknownPlayer';
    final name = prefs.getString('name') ?? 'Bank';

    final TextEditingController controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.yellow.shade50,
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
                  _showQrCode(context, playerID, name, value);
                }
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _showQrCode(
      BuildContext context, String playerID, String name, String value) {
    final qrData = jsonEncode({
      'playerID': playerID,
      'name': name,
      'value': value,
    });

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.yellow.shade50,
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
              QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: 50.w,
                gapless: false,
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
    return ElevatedButton.icon(
      icon: Icon(FontAwesomeIcons.qrcode, size: 16.sp),
      onPressed: () => _showValueDialog(context),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      label: Text(
        "Receive",
        style: TextStyle(fontSize: 16.sp),
      ),
    );
  }
}
