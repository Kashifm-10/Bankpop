import 'package:flutter_web_plugins/url_strategy.dart';

/// `/game/ABC123/player` rather than `/#/game/ABC123/player`.
void useAppUrlStrategy() => usePathUrlStrategy();
