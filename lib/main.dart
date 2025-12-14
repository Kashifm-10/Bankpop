import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mon/pages/banker/banker_screen.dart';
import 'package:mon/pages/player/player_screen.dart';
import 'package:mon/pages/role.dart';
import 'package:mon/pages/splash_screen.dart';
import 'package:mon/theme.dart';
import 'package:mon/theme_provider.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:vibration/vibration.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
   url: 'https://dgalohswapxuaayftwlj.supabase.co',
   anonKey: 'sb_publishable_4ynd9Wt_Hhi7bkD6O7IwsA_ns7MEK6b',
  );
  await _initPlayerID();
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.immersiveSticky,
  );
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const MyApp(),
    ),
  );
}

Future<void> _initPlayerID() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  String? playerID = prefs.getString('playerID');

  if (playerID == null) {
    String newID = const Uuid().v4(); // Generate UUID
    await prefs.setString('playerID', newID);
    print('Generated new playerID: $newID');
  } else {
    print('Existing playerID: $playerID');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return ResponsiveSizer(
      builder: (context, orientation, screenType) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Banker & Player App',
          theme: CustomTheme.lightThemeData(),
          darkTheme: CustomTheme.darkThemeData(),
          themeMode: themeProvider.themeMode, // 👈 Controlled by ProfilePage
          home: const SplashScreen(),
        );
      },
    );
  }
}
