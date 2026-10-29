import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mon/router.dart';
import 'package:mon/services/board_catalog.dart';
import 'package:mon/services/url_strategy.dart';
import 'package:mon/theme.dart';
import 'package:mon/theme_provider.dart';
import 'package:mon/widgets/app_frame.dart';
import 'package:mon/widgets/app_scroll_behavior.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Real paths in the browser's address bar. Called before the first frame so
  // the router reads `/game/ABC/player` from the URL, not a hash fragment.
  useAppUrlStrategy();

  // go_router rewrites the address bar for `go` and `pushReplacement` only:
  // `push` is a "detour" to it, so with this off the bar kept showing `/home`
  // while the app was already on `/start` or `/game/ABC/player`. Every screen
  // here is a real route with its own URL that a deep link resolves, so the
  // bar has to follow the pushed ones too - otherwise a refresh or a shared
  // link lands on the page behind the screen the player is looking at.
  GoRouter.optionURLReflectsImperativeAPIs = true;

  await Supabase.initialize(
    url: 'https://dgalohswapxuaayftwlj.supabase.co',
    anonKey: 'sb_publishable_4ynd9Wt_Hhi7bkD6O7IwsA_ns7MEK6b',
  );
  await _initPlayerID();

  // The boards this device already knows, read from disk before the first
  // screen opens: the bank form's flag row is then drawn from memory instead
  // of starting a read when the cards switch is flipped.
  unawaited(BoardCatalog.warmListings());

  // The edge-to-edge Android chrome has no meaning in a browser, and asking
  // for it there only risks a platform-channel exception at startup.
  if (!kIsWeb) {
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
    );
    // Portrait is no longer forced: tablets and foldables are routinely used
    // in landscape, and every screen now scrolls inside the app frame. The web
    // build has no orientation of its own either way.
    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

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
    debugPrint('Generated new playerID: $newID');
  } else {
    debugPrint('Existing playerID: $playerID');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'BankPop',
      routerConfig: appRouter,
      theme: CustomTheme.lightThemeData(),
      darkTheme: CustomTheme.darkThemeData(),
      themeMode: themeProvider.themeMode, // 👈 Controlled by ProfilePage
      // The web build draws a scrollbar over the app column by default; a
      // phone does not, and the frame is a phone.
      scrollBehavior: const AppScrollBehavior(),
      // Every route, dialog and sheet is drawn inside the responsive frame, so
      // no screen needs to know whether it is on a phone, a tablet or a
      // browser window.
      builder: (BuildContext context, Widget? child) =>
          AppFrame(child: child ?? const SizedBox.shrink()),
    );
  }
}
