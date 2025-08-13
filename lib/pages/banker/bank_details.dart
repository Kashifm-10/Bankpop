import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:mon/pages/banker/banker_screen.dart';
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
  String _selectedOption = '';

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
    String playerName = 'Bank'; // Replace with actual input if needed
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('playerValue', playerValue!);
    await prefs.setDouble('advance', advanceValue);
    String? playerID = prefs.getString('playerID');
    await Supabase.instance.client.from('players_test').insert({
      'game_id': gameId,
      'role': role,
      'name': playerName,
      'wallet': bankValue,
      'player_id': playerID,
      'SP/IP': _selectedOption
    });
    await prefs.setString('name', 'banker');
    await prefs.setString('gameID', gameId);

    // Proceed to next screen
    // ignore: use_build_context_synchronously
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => BankerGameScreen(
          bankValue: bankValue,
          gameId: gameId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          leading: IconButton(
            onPressed: () async {
              Navigator.of(context).pop();
            },
            icon: Icon(
              CupertinoIcons.chevron_back,
              size: 22.sp,
              color: Color(0xFF689F38), // deep green icon
            ),
          ),
          backgroundColor: Colors.transparent, // fresh green
          elevation: 0,
          title: const Text(
            'Enter Bank Value',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF689F38), // deep green text
            ),
          ),
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFFFFF8E1), // soft light green
                Color(0xFFFFF8E1), // slightly darker soft green
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(4.w),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 15.0),
                  child: SizedBox(
                    height: 50.sp,
                    child: Lottie.asset(
                      "assets/lottie/money_bag.json",
                      fit: BoxFit.contain,
                      repeat: true,
                    ),
                  ),
                ),
                _buildGreenTextField(
                  controller: _bankValueController,
                  label: 'Bank Total Value',
                ),
                Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(5.0),
                    child: Text(
                      'Fill the total value of Bank.',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w400,
                        color: const Color(0xFF33691E), // medium green
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 1.5.h),
                _buildGreenTextField(
                  controller: _playerAmountController,
                  label: 'Per Player',
                ),
                Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(5.0),
                    child: Text(
                      'Fill the value to be distributed to each player',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w400,
                        color: const Color(0xFF33691E), // medium green
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 1.5.h),
                _buildGreenTextField(
                  controller: _advanceAmountController,
                  label: 'Advance Value',
                ),
                Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(5.0),
                    child: Text(
                      'Fill the value which will be granted to player at completion of each round',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w400,
                        color: const Color(0xFF33691E), // medium green
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 2.h),
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      // ScanPay Card
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedOption = 'ScanPay';
                          });
                        },
                        child: Card(
                          color: _selectedOption == 'ScanPay'
                              ? const Color(
                                  0xFFC5E1A5) // light green for selected
                              : Colors.white,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(
                              color: _selectedOption == 'ScanPay'
                                  ? Color(0xFF689F38)
                                      .withOpacity(0.4) // medium green
                                  : Colors.grey.shade300,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 16),
                            child: Column(
                              children: [
                                SizedBox(
                                  height: 30.sp,
                                  child: Lottie.asset(
                                    "assets/lottie/scan.json",
                                    fit: BoxFit.contain,
                                    repeat: true,
                                  ),
                                ),
                                Text(
                                  'ScanPay',
                                  style: TextStyle(
                                    color: _selectedOption == 'ScanPay'
                                        ? const Color(0xFF2E7D32) // calm green
                                        : Colors.black87,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 20),

                      // InstantPay Card
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedOption = 'InstantPay';
                          });
                        },
                        child: Card(
                          color: _selectedOption == 'InstantPay'
                              ? const Color(0xFFC5E1A5)
                              : Colors.white,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(
                              color: _selectedOption == 'InstantPay'
                                  ? Color(0xFF689F38).withOpacity(0.4)
                                  : Colors.grey.shade300,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 16),
                            child: Column(
                              children: [
                                SizedBox(
                                  height: 30.sp,
                                  child: Lottie.asset(
                                    "assets/lottie/instant.json",
                                    fit: BoxFit.contain,
                                    repeat: true,
                                  ),
                                ),
                                Text(
                                  'InstantPay',
                                  style: TextStyle(
                                    color: _selectedOption == 'InstantPay'
                                        ? const Color(0xFF2E7D32)
                                        : Colors.black87,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.center,
                  child: Padding(
                    padding: const EdgeInsets.all(5.0),
                    child: Text(
                      'Choose the payment type to continue',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w400,
                        color: const Color(0xFF33691E), // medium green
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 4.h),
                SizedBox(
                  width: 50.w,
                  height: 6.h,
                  child: ElevatedButton(
                    onPressed: () {
                      if (_selectedOption == 'InstantPay' ||
                          _selectedOption == 'ScanPay') {
                        _startGame();
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Please select payment type')),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF689F38), // button green
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                      shadowColor: const Color(0xFFB2D8A1), // soft green shadow
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
          ),
        ),
      ),
    );
  }
}

Widget _buildGreenTextField({
  required TextEditingController controller,
  required String label,
}) {
  return TextField(
    controller: controller,
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFF2E7D32)), // calm green
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFF689F38), width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFF81C784), width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      filled: true,
      fillColor: const Color.fromARGB(255, 255, 255, 255), // light green fill
    ),
    keyboardType: TextInputType.number,
  );
}
