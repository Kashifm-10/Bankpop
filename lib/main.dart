import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mon/banker_screen.dart';
import 'package:mon/player_screen.dart';
import 'package:mon/role.dart';
import 'package:mon/splash_screen.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:vibration/vibration.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url:
        'https://ldfzcbvbgkfmwkywctfh.supabase.co', // Replace with your Supabase URL
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxkZnpjYnZiZ2tmbXdreXdjdGZoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDc1MDk1ODksImV4cCI6MjA2MzA4NTU4OX0.T4PscSKy__BRNptpTkrK5RQDgqdUuy8iW-qFwAIU4rw', // Replace with your Supabase anon key
  );
  await _initPlayerID();

  runApp(const MyApp());
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
    return ResponsiveSizer(
      builder: (context, orientation, screenType) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Banker & Player App',
          theme: ThemeData(primarySwatch: Colors.teal),
          home: const SplashScreen(), // Set splash as initial screen
        );
      },
    );
  }
}
