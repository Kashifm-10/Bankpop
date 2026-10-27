/// How the browser address bar relates to the app's screens.
///
/// The web build uses real paths (`/game/ABC123/player`) instead of the `#/`
/// fragment, so refreshing, bookmarking or sharing a link keeps the screen it
/// names. The other platforms have no address bar, so a no-op implementation is
/// compiled instead of the web-only plugin.
///
/// A host serving this build must answer every app path with `index.html`
/// (`flutter run` already does). A static host needs the usual SPA rewrite;
/// the rules page and the README note both say so.
library;

export 'url_strategy_stub.dart'
    if (dart.library.js_interop) 'url_strategy_web.dart';
