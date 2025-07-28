import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:mon/banker_screen.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BankValueScreen extends StatefulWidget {
  const BankValueScreen({super.key});

  @override
  State<BankValueScreen> createState() => _BankValueScreenState();
}

class _BankValueScreenState extends State<BankValueScreen> {
  bool _isLoading = false;

  final TextEditingController _bankValueController = TextEditingController();
  final TextEditingController _playerAmountController = TextEditingController();
  final TextEditingController _advanceAmountController =
      TextEditingController();

  String generateGameId(int length) {
    const characters =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    Random random = Random();
    String result = '';

    for (int i = 0; i < length; i++) {
      result += characters[random.nextInt(characters.length)];
    }

    return result;
  }

  void _startGame() async {
    final bankValueText = _bankValueController.text.trim();
    final playerAmountText = _playerAmountController.text.trim();
    final advanceAmountText = _advanceAmountController.text.trim();

    if (bankValueText.isEmpty ||
        playerAmountText.isEmpty ||
        advanceAmountText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all')),
      );
      return;
    }
    setState(() {
      _isLoading = true;
    });
    final bankValue = double.tryParse(_bankValueController.text.trim());
    final playerValue = double.tryParse(_playerAmountController.text.trim());
    final advanceValue = double.parse(_advanceAmountController.text.trim());
    if (bankValue == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid bank value')),
      );
      return;
    }

    // Example data
    String gameId = generateGameId(5);
    String role = 'banker'; // You can adjust this based on context
    String playerName = 'banker'; // Replace with actual input if needed
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('playerValue', playerValue!);
    await prefs.setDouble('advance', advanceValue);
    String? playerID = prefs.getString('playerID');
    await Supabase.instance.client.from('players_test').insert({
      'game_id': gameId,
      'role': role,
      'name': playerName,
      'wallet': bankValue,
      'player_id': playerID
    });

    // Proceed to next screen
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => LeaderboardScreen(
          bankValue: bankValue,
          gameId: gameId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.yellow.shade50,
        appBar: AppBar(
          leading: IconButton(
              onPressed: () async {
                Navigator.of(context)
                    .pop(); // or your custom logic to leave the game
              },
              icon: Icon(
                CupertinoIcons.chevron_back,
                size: 22.sp,
              )),
          backgroundColor: Colors.yellow.shade50,
          title: const Text(
            'Enter Bank Value',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: Padding(
          padding: EdgeInsets.all(4.w),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildBrownTextField(
                controller: _bankValueController,
                label: 'Bank Value',
              ),
              SizedBox(height: 2.h),
              _buildBrownTextField(
                controller: _playerAmountController,
                label: 'Amount to Each Player',
              ),
              SizedBox(height: 2.h),
              _buildBrownTextField(
                controller: _advanceAmountController,
                label: 'Set Advance Value',
              ),
              SizedBox(height: 4.h),
              SizedBox(
                width: 50.w,
                height: 6.h,
                child: ElevatedButton(
                  onPressed: _startGame,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.brown.shade600,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                    shadowColor: Colors.brown.shade200,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                            strokeWidth: 2,
                          ),
                        )
                      : Text('Start Game', style: TextStyle(fontSize: 18.sp)),
                ),
              ),
            ],
          ),
        ));
  }
}

Widget _buildBrownTextField({
  required TextEditingController controller,
  required String label,
}) {
  return TextField(
    controller: controller,
    keyboardType: TextInputType.number,
    style: TextStyle(color: Colors.brown.shade900),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.brown.shade800),
      filled: true,
      fillColor: Colors.brown.shade50,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.brown.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.brown.shade700, width: 1.5),
      ),
    ),
  );
}
