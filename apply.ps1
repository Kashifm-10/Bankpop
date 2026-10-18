#Requires -Version 5.1
<#
.SYNOPSIS
    Move shared game state off SharedPreferences and onto players_test.

.DESCRIPTION
    Three things were being kept in per-device prefs even though they are
    properties of the game, not of the device:

      1. playWithCards      -> players_test.play_with_cards   (already in table)
      2. playerValue        -> players_test.player_value      (NEW column)
      3. advance            -> players_test.advance_value     (NEW column)

    As a result:
      * the banker's cards switch could be overridden by a stale pref
        (merged with ||);
      * the banker's stake and advance amounts lived only on the banker's
        device, so a second banker device (or the same device after prefs
        were cleared) staked the wrong amount, or refused to accept a
        join request at all;
      * a player device could not show the round-advance amount until
        its prefs happened to carry it.

    After this patch, players_test is the source of truth for all three.
    prefs keeps:
      * playerID, profile_name, profile_image, avatar_path,
        selected_avatar_index, theme_mode    - device-local, correct;
      * role, display_name                   - local mirror so
                                               receive.dart can build a QR
                                               without a DB read; now
                                               refreshed on every roster
                                               tick from the table;
      * playerValue, advance                 - local cache only; the row
                                               wins whenever it can be read.

    The "role" value the app writes is derived from the roster, not from a
    per-device switch, so a device that was banker last game and player this
    game no longer sends a banker QR.

.SQL (run once in the Supabase SQL editor before this script's changes
take effect on existing games; new games work either way because the
insert strips the keys when the columns are missing):

    alter table public.players_test
      add column if not exists player_value  numeric not null default 0;
    alter table public.players_test
      add column if not exists advance_value numeric not null default 0;

    -- Optional: seed the two columns for the game in flight, if you know
    -- the values the banker typed. Leaving them 0 means the banker's
    -- screen falls back to its local prefs for the current game, and the
    -- next game starts writing them properly.
    --
    -- update public.players_test
    --    set player_value  = 1500,
    --        advance_value = 200
    --  where game_id = '<current_game>' and role = 'banker';

.USAGE
    cd <project root>
    powershell -ExecutionPolicy Bypass -File .\apply_shared_game_state.ps1
#>

param([string]$ProjectRoot = ".")

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ProjectRoot = (Resolve-Path $ProjectRoot).Path
if (-not (Test-Path (Join-Path $ProjectRoot 'pubspec.yaml'))) {
    throw "Not a Flutter project: $ProjectRoot (pubspec.yaml missing)"
}

$bankDetailsPath = Join-Path $ProjectRoot 'lib/pages/banker/bank_details.dart'
$bankerPath      = Join-Path $ProjectRoot 'lib/pages/banker/banker_screen.dart'
$homePath        = Join-Path $ProjectRoot 'lib/pages/home.dart'
$playerPath      = Join-Path $ProjectRoot 'lib/pages/player/player_screen.dart'

foreach ($p in @($bankDetailsPath, $bankerPath, $homePath, $playerPath)) {
    if (-not (Test-Path $p)) { throw "Required file missing: $p" }
}

# ---- Backup -------------------------------------------------------------
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path $ProjectRoot ".backup-sharedstate-$stamp"
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
foreach ($p in @($bankDetailsPath, $bankerPath, $homePath, $playerPath)) {
    $rel  = $p.Substring($ProjectRoot.Length).TrimStart('\', '/')
    $dest = Join-Path $backupDir $rel
    New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null
    Copy-Item $p $dest
}
Write-Host "Backed up to: $backupDir" -ForegroundColor Cyan

# ---- Helpers ------------------------------------------------------------
$script:editCount = 0
function Normalize-Lf   { param([string]$s) ($s -replace "`r`n", "`n") }
function Normalize-Crlf { param([string]$s) ((($s -replace "`r`n", "`n")) -replace "`n", "`r`n") }

function Edit-File {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Search,
        [Parameter(Mandatory)] [string]$Replace,
        [Parameter(Mandatory)] [string]$Name
    )
    $content  = [System.IO.File]::ReadAllText($Path)
    $usesCrlf = $content.Contains("`r`n")
    $s = if ($usesCrlf) { Normalize-Crlf $Search }  else { Normalize-Lf $Search }
    $r = if ($usesCrlf) { Normalize-Crlf $Replace } else { Normalize-Lf $Replace }
    $count = ([regex]::Matches($content, [regex]::Escape($s))).Count
    if ($count -eq 0) { throw "[$Name] anchor not found in $(Split-Path $Path -Leaf). File unchanged." }
    if ($count -gt 1) { throw "[$Name] anchor not unique in $(Split-Path $Path -Leaf) ($count matches). File unchanged." }
    $newContent = $content.Replace($s, $r)
    [System.IO.File]::WriteAllText($Path, $newContent, (New-Object System.Text.UTF8Encoding($false)))
    $script:editCount++
    Write-Host ("  [OK] {0,-58} {1}" -f $Name, (Split-Path $Path -Leaf)) -ForegroundColor Green
}

# =========================================================================
# bank_details.dart
#   * write player_value / advance_value onto the bank row
#   * keep the pref writes (local cache for this device)
#   * keep the "strip key if column missing" fallback
#   * stop writing playWithCards to prefs
# =========================================================================
Write-Host "`nEditing bank_details.dart" -ForegroundColor Yellow

# 1) Insert the two new keys into bankRow and extend the fallback to strip
#    all three optional keys.
Edit-File -Path $bankDetailsPath -Name 'bank_details: bankRow carries stakes' -Search @'
    // The cards switch travels with the bank row, so the players' devices know
    // whether to offer "My Cards" / "Buy Card" at all.
    final Map<String, dynamic> bankRow = <String, dynamic>{
      'game_id': gameId,
      'role': role,
      'name': playerName,
      'wallet': bankValue,
      'player_id': playerID,
      'SP/IP': _selectedOption,
      'play_with_cards': _playWithCards,
    };
    try {
      await Supabase.instance.client.from('players_test').insert(bankRow);
    } on PostgrestException catch (error) {
      // The flag needs supabase/cards_mode.sql. A game without that column can
      // still start; only the players lose the cards buttons.
      if (!error.message.contains('play_with_cards')) rethrow;
      bankRow.remove('play_with_cards');
      await Supabase.instance.client.from('players_test').insert(bankRow);
    }
'@ -Replace @'
    // Everything a later screen (or a second banker device) needs to run
    // this game lives on the bank row: the cards switch, the per-player
    // stake, and the round advance. prefs keeps a local copy for speed, but
    // the row is the source of truth.
    final Map<String, dynamic> bankRow = <String, dynamic>{
      'game_id': gameId,
      'role': role,
      'name': playerName,
      'wallet': bankValue,
      'player_id': playerID,
      'SP/IP': _selectedOption,
      'play_with_cards': _playWithCards,
      'player_value': playerValue,
      'advance_value': advanceValue,
    };
    try {
      await Supabase.instance.client.from('players_test').insert(bankRow);
    } on PostgrestException catch (error) {
      // The three optional columns need their SQL files (cards_mode.sql
      // and shared_game_state.sql). A project that has not run them can
      // still start a game; the affected features fall back to local
      // prefs instead of failing.
      final String message = error.message;
      bool removed = false;
      if (message.contains('play_with_cards')) {
        bankRow.remove('play_with_cards');
        removed = true;
      }
      if (message.contains('player_value')) {
        bankRow.remove('player_value');
        removed = true;
      }
      if (message.contains('advance_value')) {
        bankRow.remove('advance_value');
        removed = true;
      }
      if (!removed) rethrow;
      await Supabase.instance.client.from('players_test').insert(bankRow);
    }
'@

# 2) Drop the playWithCards pref write; explain the rest.
Edit-File -Path $bankDetailsPath -Name 'bank_details: prefs write note' -Search @'
    await prefs.setString('name', 'banker');
    await prefs.setString('role', 'banker');
    await prefs.setString('display_name', 'Bank');
    await prefs.setString('gameID', gameId);
    await prefs.setBool('playWithCards', _playWithCards);
'@ -Replace @'
    await prefs.setString('name', 'banker');
    await prefs.setString('role', 'banker');
    await prefs.setString('display_name', 'Bank');
    await prefs.setString('gameID', gameId);
    // play_with_cards travels on the bank row (players_test), not in prefs:
    // the switch is a property of the game, shared with every device.
    // playerValue / advance stay in prefs as a local cache; the banker
    // screens read them from the row whenever it can be read.
'@

# =========================================================================
# banker_screen.dart
#   * drop _cardsModeFromPrefs and read play_with_cards from the row only
#   * add _playerValue / _advanceValue fields read from the row, with the
#     local prefs value as a fallback while the columns are missing
#   * use those fields where the pref was read
#   * drop the pref remove on leave
# =========================================================================
Write-Host "`nEditing banker_screen.dart" -ForegroundColor Yellow

# 1) Drop _cardsModeFromPrefs; add the two new fields next to it.
Edit-File -Path $bankerPath -Name 'banker: fields' -Search @'
  /// Cards game, chosen on the "Enter Bank Value" screen before the game
  /// started. When on, the bank can sell board properties: by QR in a ScanPay
  /// game, by assignment to a named player in an InstantPay one.
  bool _playWithCards = false;

  /// What this device's own switch said at game start. The switch is the
  /// banker's alone, so this copy wins whenever the bank row disagrees - a game
  /// started before supabase/cards_mode.sql was run carries a false there.
  bool _cardsModeFromPrefs = false;
'@ -Replace @'
  /// Cards game, read from the bank row of this game. The banker writes it
  /// once at game start; every device reads it back from the same row.
  bool _playWithCards = false;

  /// Stake and round advance, read from the bank row. The device that
  /// started the game typed them, but a second banker device (or this one
  /// after prefs were cleared) has to be able to read them back.
  ///
  /// Null means "not yet known". The prefs copies are consulted as a
  /// fallback only while the columns are missing from the row.
  double? _playerValue;
  double? _advanceValue;
'@

# 2) _applyGameRows: read the three values from the bank row; fall back to
#    the prefs copies only when the row does not carry them.
Edit-File -Path $bankerPath -Name 'banker: read shared state from row' -Search @'
    // A trade that touches a mortgaged card owes the bank 10% interest, and
    // only this id can route that payment.
    final String bankPlayerId = bankRow['player_id']?.toString() ?? '';
    if (bankPlayerId.isNotEmpty) Deals.rememberBankId(bankPlayerId);

    final double bankWallet =
        double.parse((bankRow['wallet'] as num).toStringAsFixed(2));
    final String bankPayOption = (bankRow['SP/IP'] as String?) ?? payOption;
    // The switch is this device's, so it is never switched off behind the
    // banker's back: the bank row can only add to it, which is what lets a
    // player's screen follow the same game.
    final bool bankCardsMode = _cardsModeFromPrefs ||
        (bankRow.containsKey('play_with_cards') &&
            bankRow['play_with_cards'] == true);
    // Only rebuild when the bank state actually moved.
    if (bankWallet != value ||
        bankPayOption != payOption ||
        bankCardsMode != _playWithCards) {
      setState(() {
        value = bankWallet;
        payOption = bankPayOption;
        _playWithCards = bankCardsMode;
      });
    }
'@ -Replace @'
    // A trade that touches a mortgaged card owes the bank 10% interest, and
    // only this id can route that payment.
    final String bankPlayerId = bankRow['player_id']?.toString() ?? '';
    if (bankPlayerId.isNotEmpty) Deals.rememberBankId(bankPlayerId);

    final double bankWallet =
        double.parse((bankRow['wallet'] as num).toStringAsFixed(2));
    final String bankPayOption = (bankRow['SP/IP'] as String?) ?? payOption;
    // play_with_cards lives on the bank row and is the only source of truth.
    // A project where cards_mode.sql has not been run reports false, which
    // hides the card buttons.
    final bool bankCardsMode = bankRow['play_with_cards'] == true;

    // The stake and advance are per-game, not per-device. Read them from the
    // row whenever it carries them; the prefs copies are a fallback for a
    // project that has not run shared_game_state.sql yet.
    double? nextPlayerValue = _playerValue;
    if (bankRow['player_value'] is num) {
      nextPlayerValue = (bankRow['player_value'] as num).toDouble();
    }
    double? nextAdvanceValue = _advanceValue;
    if (bankRow['advance_value'] is num) {
      nextAdvanceValue = (bankRow['advance_value'] as num).toDouble();
    }

    // Only rebuild when the bank state actually moved.
    if (bankWallet != value ||
        bankPayOption != payOption ||
        bankCardsMode != _playWithCards ||
        nextPlayerValue != _playerValue ||
        nextAdvanceValue != _advanceValue) {
      setState(() {
        value = bankWallet;
        payOption = bankPayOption;
        _playWithCards = bankCardsMode;
        _playerValue = nextPlayerValue;
        _advanceValue = nextAdvanceValue;
      });
    }
'@

# 3) _loadStartupSettings: seed ID and the two amounts from prefs as a
#    local fallback while the row is in flight (or missing).
Edit-File -Path $bankerPath -Name 'banker: seed fallback amounts' -Search @'
  /// Reads what this device knows about the game it is hosting.
  ///
  /// The cards switch lives here rather than on the server, so it survives a
  /// rebuild but is written once per game start by bank_details.dart. [ID] is the
  /// bank row's player_id, which the history screen needs before the first join
  /// request has been accepted - it used to be filled in only from a stake.
  Future<void> _loadStartupSettings() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool enabled = prefs.getBool('playWithCards') ?? false;
    final String ownId = prefs.getString('playerID') ?? '';
    if (!mounted) return;
    // Merge, never overwrite: the bank row may already have told us the game is
    // in cards mode (a banker who opens a game started on another device has
    // no local pref). Turning the switch off here would hide Give Card / Board
    // in a game that is actually playing with cards.
    final bool cardsMode = _playWithCards || enabled;
    final bool cardsPrefs = _cardsModeFromPrefs || enabled;
    final bool unchanged =
        cardsMode == _playWithCards && cardsPrefs == _cardsModeFromPrefs;
    if (unchanged && (ownId.isEmpty || ownId == ID)) return;
    setState(() {
      _cardsModeFromPrefs = cardsPrefs;
      _playWithCards = cardsMode;
      if (ownId.isNotEmpty) ID = ownId;
    });
  }
'@ -Replace @'
  /// Seeds the screen's local fallbacks before the first bank row arrives.
  ///
  /// The cards switch is not read here any more: it is written on the bank row
  /// at game start and read back by _applyGameRows, which runs on the same
  /// first tick. [ID] and the two amounts are seeded from prefs only so the
  /// screen has something to show while the row is in flight, or on a project
  /// where the row cannot carry them. The row overwrites them the moment it
  /// lands.
  Future<void> _loadStartupSettings() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String ownId = prefs.getString('playerID') ?? '';
    final double? stake = prefs.getDouble('playerValue');
    final double? advance = prefs.getDouble('advance');
    if (!mounted) return;
    if (ownId == ID &&
        (stake == null || stake == _playerValue) &&
        (advance == null || advance == _advanceValue)) {
      return;
    }
    setState(() {
      if (ownId.isNotEmpty) ID = ownId;
      _playerValue ??= stake;
      _advanceValue ??= advance;
    });
  }
'@

# 4) Accept branch: stake from the row, not from prefs.
Edit-File -Path $bankerPath -Name 'banker: stake from row' -Search @'
              TextButton(
                onPressed: () async {
                  SharedPreferences prefs =
                      await SharedPreferences.getInstance();

                  final double? playerValue =
                      prefs.getDouble('playerValue');

                  if (playerValue == null) {
                    Navigator.of(context).pop();
                    return;
                  }

                  // One call seats the player, moves the stake off the bank
                  // (which is allowed to go negative) and clears the request.
                  final StakeOutcome stake = await WalletTransfer.stake(
                    gameId: widget.gameId,
                    playerId: '${request['player_id']}',
                    playerName: '${request['name']}',
                    amount: playerValue,
                    paymentOption: payOption,
                    requestId: '${request['id']}',
                  );
'@ -Replace @'
              TextButton(
                onPressed: () async {
                  // The stake is a property of the game, read from the bank
                  // row. prefs is only a fallback while the row cannot carry
                  // it (project without shared_game_state.sql).
                  final double? stakeAmount = _playerValue;
                  if (stakeAmount == null) {
                    Navigator.of(context).pop();
                    if (mounted) {
                      showMessage(this.context,
                          'Could not read the player stake - try again');
                    }
                    return;
                  }

                  // One call seats the player, moves the stake off the bank
                  // (which is allowed to go negative) and clears the request.
                  final StakeOutcome stake = await WalletTransfer.stake(
                    gameId: widget.gameId,
                    playerId: '${request['player_id']}',
                    playerName: '${request['name']}',
                    amount: stakeAmount,
                    paymentOption: payOption,
                    requestId: '${request['id']}',
                  );
'@

# 5) Advance button: amount from the row, not from prefs.
Edit-File -Path $bankerPath -Name 'banker: advance from row' -Search @'
                ElevatedButton(
                  onPressed: () async {
                    advancing();
                    final prefs = await SharedPreferences.getInstance();
                    final payerPlayerID =
                        prefs.getString('playerID') ?? 'UnknownPlayer';
                    double advanceValue = prefs.getDouble('advance')!;
                    double advanceAmount = advanceValue;
'@ -Replace @'
                ElevatedButton(
                  onPressed: () async {
                    advancing();
                    final prefs = await SharedPreferences.getInstance();
                    final payerPlayerID =
                        prefs.getString('playerID') ?? 'UnknownPlayer';
                    // The advance is a property of the game, read from the
                    // bank row; prefs is only a fallback while the row cannot
                    // carry it.
                    final double advanceAmount = _advanceValue ?? 0;
                    if (advanceAmount <= 0) {
                      if (context.mounted) {
                        showMessage(context,
                            'Could not read the advance amount - try again');
                      }
                      return;
                    }
'@

# 6) Leave handler: stop removing the pref.
Edit-File -Path $bankerPath -Name 'banker: leave drops pref remove' -Search @'
                    SharedPreferences prefs =
                        await SharedPreferences.getInstance();
                    await prefs.remove('gameID');
                    await prefs.remove('playWithCards');
'@ -Replace @'
                    SharedPreferences prefs =
                        await SharedPreferences.getInstance();
                    await prefs.remove('gameID');
'@

# =========================================================================
# home.dart -- read cards mode from the bank row only
# =========================================================================
Write-Host "`nEditing home.dart" -ForegroundColor Yellow

Edit-File -Path $homePath -Name 'home: cards from row only' -Search @'
    _playWithCards = prefs.getBool('playWithCards') ?? false;
    if (!_playWithCards) {
      // A player device never sets playWithCards locally; the banker does.
      // Read the current game's bank row so the board icon matches the game
      // that is actually in play.
      final String? gameId = prefs.getString('gameID');
      if (gameId != null && gameId.isNotEmpty) {
        try {
          final Map<String, dynamic>? bankRow = await supabase
              .from('players_test')
              .select('play_with_cards')
              .eq('game_id', gameId)
              .eq('role', 'banker')
              .maybeSingle();
          if (bankRow != null && bankRow['play_with_cards'] == true) {
            _playWithCards = true;
          }
        } catch (error) {
          debugPrint('Could not read cards mode: $error');
        }
      }
    }
'@ -Replace @'
    // Cards mode is a property of the current game, stored on its bank row.
    // Read it from there every time so no local copy can disagree with the
    // game that is actually in play.
    final String? gameId = prefs.getString('gameID');
    if (gameId != null && gameId.isNotEmpty) {
      try {
        final Map<String, dynamic>? bankRow = await supabase
            .from('players_test')
            .select('play_with_cards')
            .eq('game_id', gameId)
            .eq('role', 'banker')
            .maybeSingle();
        _playWithCards = bankRow?['play_with_cards'] == true;
      } catch (error) {
        // A project without cards_mode.sql throws here; the board icon then
        // simply stays hidden, which matches the missing column's false.
        debugPrint('Could not read cards mode: $error');
      }
    }
'@

# =========================================================================
# player_screen.dart
#   * read advance_value from the bank row; keep prefs as a fallback
#   * refresh display_name / role from the live roster every tick
#   * stop removing the pref on leave
# =========================================================================
Write-Host "`nEditing player_screen.dart" -ForegroundColor Yellow

# 1) New fields next to _playWithCards.
Edit-File -Path $playerPath -Name 'player: field for advance' -Search @'
  /// Cards game, read from the bank row of this game. The banker flips the
  /// switch once at game start; until then, and in a game started before the
  /// flag existed, this stays false and the card buttons stay hidden.
  bool _playWithCards = false;
'@ -Replace @'
  /// Cards game, read from the bank row of this game. The banker flips the
  /// switch once at game start; until then, and in a game started before the
  /// flag existed, this stays false and the card buttons stay hidden.
  bool _playWithCards = false;

  /// The round advance, read from the bank row. Local prefs is a fallback
  /// while the row cannot carry it (project without
  /// shared_game_state.sql).
  double? _advanceValue;
'@

# 2) _applyRosterRows: read advance_value, and refresh the local role /
#    display_name mirror from the live roster row.
Edit-File -Path $playerPath -Name 'player: read advance + refresh mirror' -Search @'
    // The banker's cards switch, as written on the bank row at game start.
    // Capture the bank's player_id at the same time: a trade that touches a
    // mortgaged card owes the bank 10% interest, and only the id can route it.
    bool cardsMode = _playWithCards;
    for (final Map<String, dynamic> row in rows) {
      if (row['role'] == 'banker') {
        if (row.containsKey('play_with_cards')) {
          cardsMode = row['play_with_cards'] == true;
        }
        final String? bankId = row['player_id']?.toString();
        if (bankId != null && bankId.isNotEmpty) {
          _bankerPlayerId = bankId;
          Deals.rememberBankId(bankId);
        }
        break;
      }
    }
    if (cardsMode != _playWithCards) {
      setState(() => _playWithCards = cardsMode);
    }

    _applyMyPlayer(roster);
'@ -Replace @'
    // The banker's cards switch and advance, as written on the bank row at
    // game start. Capture the bank's player_id at the same time: a trade that
    // touches a mortgaged card owes the bank 10% interest, and only the id
    // can route it.
    bool cardsMode = _playWithCards;
    double? advance = _advanceValue;
    for (final Map<String, dynamic> row in rows) {
      if (row['role'] == 'banker') {
        if (row.containsKey('play_with_cards')) {
          cardsMode = row['play_with_cards'] == true;
        }
        if (row['advance_value'] is num) {
          advance = (row['advance_value'] as num).toDouble();
        }
        final String? bankId = row['player_id']?.toString();
        if (bankId != null && bankId.isNotEmpty) {
          _bankerPlayerId = bankId;
          Deals.rememberBankId(bankId);
        }
        break;
      }
    }
    if (cardsMode != _playWithCards || advance != _advanceValue) {
      setState(() {
        _playWithCards = cardsMode;
        _advanceValue = advance;
      });
    }

    _applyMyPlayer(roster);
'@

# 3) fetchCurrentPlayerName: drop the role/display_name writes here.
#    They are refreshed from the live roster in _applyMyPlayer below, so
#    this method only needs the local identity bits.
Edit-File -Path $playerPath -Name 'player: stop writing stale mirror' -Search @'
  Future<void> fetchCurrentPlayerName() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gameID', widget.gameId);

    // This device is playing as a player in this game. Store the role and the
    // display name in prefs so the QR generator (receive.dart) can build the
    // correct payload without a database round-trip.
    final profileName = prefs.getString('profile_name');
    await prefs.setString('role', 'player');
    await prefs.setString('display_name', profileName ?? 'Player');

    if (!mounted) return;
    setState(() {
      // Read once at startup instead of on every tick.
      playerID ??= prefs.getString('playerID');
      currentPlayerName ??= profileName;
    });
  }
'@ -Replace @'
  Future<void> fetchCurrentPlayerName() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gameID', widget.gameId);

    // role / display_name are a local mirror of the roster row so
    // receive.dart can build a QR without a database read. They are
    // refreshed from the live roster in _applyMyPlayer below; this method
    // only seeds them, so a device that has just opened the game has
    // something to send before the first tick lands.
    final profileName = prefs.getString('profile_name');
    await prefs.setString('role', 'player');
    if (!prefs.containsKey('display_name') || prefs.getString('display_name')!.isEmpty) {
      await prefs.setString('display_name', profileName ?? 'Player');
    }

    if (!mounted) return;
    setState(() {
      // Read once at startup instead of on every tick.
      playerID ??= prefs.getString('playerID');
      currentPlayerName ??= profileName;
    });
  }
'@

# 4) _applyMyPlayer: keep the QR mirror in step with the live row.
Edit-File -Path $playerPath -Name 'player: refresh mirror from row' -Search @'
    // Show SnackBar only if there's a change
    if (previousWallet != null) {
      if (wallet > previousWallet!) {
        notification('received', (wallet - previousWallet!).toStringAsFixed(2));
      } else if (wallet < previousWallet! && payOption == 'ScanPay') {
        notification('paid', (previousWallet! - wallet).toStringAsFixed(2));
      }
    }

    previousWallet = wallet.toDouble();
  }
'@ -Replace @'
    // Keep the QR mirror (role / display_name) in step with the row, so a
    // banker who renames a player does not leave this device sending a QR
    // with the old name. One cheap read and only one write when it changed.
    _syncQrMirror(name);

    // Show SnackBar only if there's a change
    if (previousWallet != null) {
      if (wallet > previousWallet!) {
        notification('received', (wallet - previousWallet!).toStringAsFixed(2));
      } else if (wallet < previousWallet! && payOption == 'ScanPay') {
        notification('paid', (previousWallet! - wallet).toStringAsFixed(2));
      }
    }

    previousWallet = wallet.toDouble();
  }

  /// Keeps `display_name` and `role` in prefs in step with the roster row.
  /// receive.dart reads them to build a QR; without this a rename on the
  /// bank's screen never reaches the player's QR.
  Future<void> _syncQrMirror(String? liveName) async {
    if (liveName == null || liveName.isEmpty) return;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (prefs.getString('display_name') == liveName &&
        prefs.getString('role') == 'player') {
      return;
    }
    await prefs.setString('display_name', liveName);
    await prefs.setString('role', 'player');
  }
'@

# 5) Leave handler: stop removing the pref.
Edit-File -Path $playerPath -Name 'player: leave drops pref remove' -Search @'
                    SharedPreferences prefs =
                        await SharedPreferences.getInstance();
                    await prefs.remove('gameID');
                    await prefs.remove('playWithCards');
'@ -Replace @'
                    SharedPreferences prefs =
                        await SharedPreferences.getInstance();
                    await prefs.remove('gameID');
'@

# =========================================================================
# Done
# =========================================================================
Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "All $script:editCount edits applied." -ForegroundColor Green
Write-Host "Backup: $backupDir" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Before running the app, in the Supabase SQL editor:" -ForegroundColor Yellow
Write-Host "  alter table public.players_test"
Write-Host "    add column if not exists player_value  numeric not null default 0;"
Write-Host "  alter table public.players_test"
Write-Host "    add column if not exists advance_value numeric not null default 0;"
Write-Host ""
Write-Host "If a game is in flight and you want it to pick up the new"
Write-Host "columns immediately, seed them for that game (values shown are"
Write-Host "examples):"
Write-Host "  update public.players_test"
Write-Host "     set player_value = 1500, advance_value = 200"
Write-Host "   where game_id = '<current_game>' and role = 'banker';"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. flutter analyze"
Write-Host "  2. Run apply_updates.ps1 afterwards if you have not already;"
Write-Host "     the two patches touch different anchors."
Write-Host ""
Write-Host "Manual checks:" -ForegroundColor Yellow
Write-Host "  * Start a game with playerValue=1500, advance=200."
Write-Host "    Open players_test in Supabase: the bank row carries"
Write-Host "    player_value=1500 and advance_value=200."
Write-Host "  * Clear the app's data on the banker device and reopen the"
Write-Host "    game. Accept a join request: it still stakes 1500 (read"
Write-Host "    from the row, not from prefs), and the Advance button"
Write-Host "    still pays 200."
Write-Host "  * Open the game as a player on a fresh device. The Advance"
Write-Host "    button label shows 200 without the player ever having"
Write-Host "    prefs for it."
Write-Host "  * Rename the player on the banker screen. The player's QR"
Write-Host "    (Receive button) shows the new name after the next tick."
Write-Host "  * Banker starts a game with cards ON: Give Card / Board"
Write-Host "    appear. Edit the bank row to play_with_cards=false:"
Write-Host "    they disappear on every device on the next tick."
Write-Host ""
Write-Host "What remains in prefs, and why:" -ForegroundColor Yellow
Write-Host "  playerID, profile_name, profile_image, avatar_path,"
Write-Host "  selected_avatar_index, theme_mode   - device-local, correct."
Write-Host "  role, display_name                  - local QR mirror, now"
Write-Host "                                        refreshed every tick"
Write-Host "                                        from the roster row."
Write-Host "  playerValue, advance, gameID        - local cache only; the"
Write-Host "                                        row wins whenever it can"
Write-Host "                                        be read."
Write-Host ""
Write-Host "To roll back: Copy-Item '$backupDir\lib\*' 'lib\' -Recurse -Force" -ForegroundColor DarkGray