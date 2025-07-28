import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:mon/bank_details.dart';
import 'package:mon/main.dart';
import 'package:mon/player_details.dart';
import 'package:mon/player_screen.dart';
import 'package:responsive_sizer/responsive_sizer.dart';

class SelectRoleScreen extends StatelessWidget {
  const SelectRoleScreen({super.key});

  void _goToBanker(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BankValueScreen()),
    );
  }

  void _goToPlayer(BuildContext context) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => const PlayerQRScannerScreen(
                playerName: 'Alice',
                wallet: 1000.0,
              )),
    );

    if (result != null && result is Map<String, dynamic>) {
      print("Joined: ${result['name']} with wallet ${result['wallet']}");
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayersScreen(
              bankValue: double.parse(result['wallet'].toString()),
              gameId: result['game_id']),
        ),
      );
    } else {
      print("Join failed or timed out");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid game ID scanned')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      /*  appBar: AppBar(
        title: const Text('Select Role'),
        centerTitle: true,
        backgroundColor: Colors.white.withOpacity(0.9),
        elevation: 4,
        foregroundColor: Colors.deepPurple.shade900,
        shadowColor: Colors.deepPurple.shade100,
      ), */
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image:
                AssetImage('assets/images/background.jpeg'), // Adjust the path
            fit: BoxFit.cover,
          ),
          gradient: LinearGradient(
            colors: [
              Color(0xFFF0F2F5),
              Color(0xFFE1E5EB),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              /*   Text(
                'Choose Your Role',
                style: TextStyle(
                  fontSize: 24.sp,
                  fontWeight: FontWeight.w700,
                  color: Colors.deepPurple.shade900,
                  letterSpacing: 1.2,
                ),
              ), */
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 5.h),
                margin: EdgeInsets.symmetric(horizontal: 6.w),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(24),
                  /*   boxShadow: [
                    BoxShadow(
                      color: Colors.deepPurple.withOpacity(0.12),
                      blurRadius: 22,
                      offset: const Offset(0, 12),
                    ),
                    BoxShadow(
                      color: Colors.deepPurple.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 6),
                    ),
                  ], */
                ),
                child: Padding(
                  padding: EdgeInsets.only(bottom: 8.h),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Continue as',
                        style: TextStyle(
                          fontSize: 24.sp,
                          fontWeight: FontWeight.w700,
                          color: Colors.black45,
                          letterSpacing: 1.2,
                        ),
                      ),
                      SizedBox(height: 5.h),
                      _buildRoleButton(
                        context,
                        title: 'Banker',
                        icon: Icons.account_balance,
                        color: Colors.brown,
                        colors: [
                          const Color(0xFF5B86E5),
                          const Color(0xFF36D1DC)
                        ], // Blue gradient
                        onTap: () => _goToBanker(context),
                      ),
                      SizedBox(height: 3.h),
                      _buildRoleButton(
                        context,
                        title: 'Player',
                        icon: FontAwesomeIcons.dice,
                        color: Colors.blue.shade300,
                        colors: [
                          const Color(0xFF7F00FF),
                          const Color(0xFFE100FF)
                        ], // Purple gradient
                        onTap: () => _goToPlayer(context),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleButton(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 70.w,
      height: 7.h,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.transparent,
            /*  gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ), */
            /*   boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.6),
                blurRadius: 5,
                offset: const Offset(3, 3),
              ),
            ], */
            border: Border.all(color: color.withOpacity(.6)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 22.sp),
              const SizedBox(width: 20),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.7,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
