#Requires -Version 5.1
<#
.SYNOPSIS
    Confirm dialogs, cancel auto-close, extra history tabs, and a more
    reliable My Cards refresh on sell/mortgage.

.DESCRIPTION
    1.  player_screen: confirmation dialog before mortgage / unmortgage /
        sell-house / sell-hotel / trade.
    2.  player_screen: onBuilt() now runs BEFORE the deed pops, and the
        pop is deferred one frame so the sheet visibly rebuilds with the
        new state (this is the fix for "My Cards only updates on buy").
    3.  player_screen: _showTradeOffer auto-closes if the sender settles
        or cancels the trade while it's on screen.
    4.  banker_screen: _showDealApproval auto-closes if the player
        cancels the request while the dialog is up.
    5.  deals.dart + card_requests.dart: carry date/time so the history
        tabs can sort chronologically.
    6.  transactions.dart: Cards tab also shows mortgage / unmortgage,
        Houses tab also shows house / hotel sales, and there is a new
        Trades tab listing every accepted, rejected and cancelled trade.

.USAGE
    cd <project root>
    powershell -ExecutionPolicy Bypass -File .\apply_v3.ps1
#>

param([string]$ProjectRoot = ".")

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ProjectRoot = (Resolve-Path $ProjectRoot).Path
if (-not (Test-Path (Join-Path $ProjectRoot 'pubspec.yaml'))) {
    throw "Not a Flutter project: $ProjectRoot (pubspec.yaml missing)"
}

$dealsPath     = Join-Path $ProjectRoot 'lib/services/deals.dart'
$cardsReqPath  = Join-Path $ProjectRoot 'lib/services/card_requests.dart'
$playerPath    = Join-Path $ProjectRoot 'lib/pages/player/player_screen.dart'
$bankerPath    = Join-Path $ProjectRoot 'lib/pages/banker/banker_screen.dart'
$tradePath     = Join-Path $ProjectRoot 'lib/widgets/trade_builder_dialog.dart'
$txPath        = Join-Path $ProjectRoot 'lib/pages/transactions/transactions.dart'

foreach ($p in @($dealsPath,$cardsReqPath,$playerPath,$bankerPath,$tradePath,$txPath)) {
    if (-not (Test-Path $p)) { throw "Required file missing: $p" }
}

# ---- Backup -------------------------------------------------------------
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path $ProjectRoot ".backup-v3-$stamp"
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
foreach ($p in @($dealsPath,$cardsReqPath,$playerPath,$bankerPath,$tradePath,$txPath)) {
    $rel = $p.Substring($ProjectRoot.Length).TrimStart('\', '/')
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
    Write-Host ("  [OK] {0,-52} {1}" -f $Name, (Split-Path $Path -Leaf)) -ForegroundColor Green
}

# =========================================================================
# deals.dart -- DealRequest.date / .time so history can sort chronologically
# =========================================================================
Write-Host "`nEditing deals.dart" -ForegroundColor Yellow

Edit-File -Path $dealsPath -Name 'deals: fields' -Search @'
  final double offerCash;
  final double wantsCash;
  final String status;

  bool get isTrade => kind == DealKind.trade;
'@ -Replace @'
  final double offerCash;
  final double wantsCash;
  final String status;

  /// When the deal was written (`yyyy-MM-dd`), so the history tabs can sort.
  final String date;

  /// When the deal was written (`HH:mm:ss`).
  final String time;

  bool get isTrade => kind == DealKind.trade;
'@

Edit-File -Path $dealsPath -Name 'deals: constructor' -Search @'
    required this.status,
  });
'@ -Replace @'
    required this.status,
    this.date = '',
    this.time = '',
  });
'@

Edit-File -Path $dealsPath -Name 'deals: fromMap' -Search @'
      status: map['status']?.toString() ?? 'pending',
    );
'@ -Replace @'
      status: map['status']?.toString() ?? 'pending',
      date: map['date']?.toString() ?? '',
      time: map['time']?.toString() ?? '',
    );
'@

# =========================================================================
# card_requests.dart -- CardRequest.date / .time (same reason)
# =========================================================================
Write-Host "`nEditing card_requests.dart" -ForegroundColor Yellow

Edit-File -Path $cardsReqPath -Name 'cardreq: fields' -Search @'
  /// `house` or `hotel`.
  final String kind;
  final double amount;

  bool get isHotel => kind == 'hotel';
'@ -Replace @'
  /// `house` or `hotel`.
  final String kind;
  final double amount;

  /// When the request was written (`yyyy-MM-dd`).
  final String date;

  /// When the request was written (`HH:mm:ss`).
  final String time;

  bool get isHotel => kind == 'hotel';
'@

Edit-File -Path $cardsReqPath -Name 'cardreq: constructor' -Search @'
    required this.kind,
    required this.amount,
  });
'@ -Replace @'
    required this.kind,
    required this.amount,
    this.date = '',
    this.time = '',
  });
'@

Edit-File -Path $cardsReqPath -Name 'cardreq: fromMap' -Search @'
      kind: map['kind']?.toString() ?? 'house',
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
    );
'@ -Replace @'
      kind: map['kind']?.toString() ?? 'house',
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      date: map['date']?.toString() ?? '',
      time: map['time']?.toString() ?? '',
    );
'@

# =========================================================================
# player_screen.dart
# =========================================================================
Write-Host "`nEditing player_screen.dart" -ForegroundColor Yellow

# ---- 1) Add _confirm helper right after _showBoard ---------------------
Edit-File -Path $playerPath -Name 'player: add _confirm helper' -Search @'
  /// Live trades addressed to this player. Polled on every reconciliation tick;
'@ -Replace @'
  /// A yes/no confirmation with the Bankpop style. Used before a deal is
  /// committed so a single tap cannot mortgage a card by accident.
  Future<bool> _confirm(String title, String message, String action) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFFFFF8E1),
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result == true;
  }

  /// Live trades addressed to this player. Polled on every reconciliation tick;
'@

# ---- 2) _mortgageCard: add confirm, reorder onBuilt before pop --------
Edit-File -Path $playerPath -Name 'player: mortgage confirm + refresh' -Search @'
    if (builtInGroup) {
      await showMessage(
        context,
        'Sell the buildings in the ${space.color} group first',
        title: 'Cannot mortgage yet',
      );
      return;
    }

    final int? dealId = await Deals.ask(
      gameId: widget.gameId,
      kind: DealKind.mortgage,
      fromId: id,
      fromName: currentPlayerName ?? 'Player',
      toId: bankId,
      toName: 'Bank',
      cards: <int>[card.cardIndex],
    );
    if (!mounted) return;
    if (dealId == null) {
      await showMessage(context, 'Could not ask to mortgage ${space.name}');
      return;
    }
    final bool approved =
        await _waitForDeal(dealId: dealId, what: 'mortgage');
    if (approved && mounted) {
      // The sheet still holds the pre-mortgage PlayerCard; write the new
      // state into that same list so the mini card re-renders with the M
      // badge instead of the old rent and dots.
      final int idx =
          myCards.indexWhere((PlayerCard c) => c.cardIndex == card.cardIndex);
      if (idx != -1) {
        myCards[idx] = myCards[idx].copyWith(mortgaged: true);
      }
      Navigator.of(context).maybePop();
      onBuilt();
      _refreshRoster();
    }
  }
'@ -Replace @'
    if (builtInGroup) {
      await showMessage(
        context,
        'Sell the buildings in the ${space.color} group first',
        title: 'Cannot mortgage yet',
      );
      return;
    }

    final int halfValue = (space.price ?? 0) ~/ 2;
    final bool confirmed = await _confirm(
      'Mortgage ${space.name}?',
      'The bank will pay you \u00a3$halfValue and the card stops '
          'collecting rent until you unmortgage it.',
      'Mortgage',
    );
    if (!confirmed || !mounted) return;

    final int? dealId = await Deals.ask(
      gameId: widget.gameId,
      kind: DealKind.mortgage,
      fromId: id,
      fromName: currentPlayerName ?? 'Player',
      toId: bankId,
      toName: 'Bank',
      cards: <int>[card.cardIndex],
    );
    if (!mounted) return;
    if (dealId == null) {
      await showMessage(context, 'Could not ask to mortgage ${space.name}');
      return;
    }
    final bool approved =
        await _waitForDeal(dealId: dealId, what: 'mortgage');
    if (approved && mounted) {
      // Write to myCards, refresh the sheet, then close the deed one frame
      // later. Without the deferred pop the sheet's rebuild could race the
      // deed's dismissal and the mini card would stay stale.
      final int idx =
          myCards.indexWhere((PlayerCard c) => c.cardIndex == card.cardIndex);
      if (idx != -1) {
        myCards[idx] = myCards[idx].copyWith(mortgaged: true);
      }
      onBuilt();
      _refreshRoster();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
  }
'@

# ---- 3) _unmortgageCard: add confirm, reorder ------------------------
Edit-File -Path $playerPath -Name 'player: unmortgage confirm + refresh' -Search @'
    final String? bankId = _bankerPlayerId;
    if (bankId == null || bankId.isEmpty) return;
    final String id = playerID ?? '';
    if (id.isEmpty) return;

    final int? dealId = await Deals.ask(
      gameId: widget.gameId,
      kind: DealKind.unmortgage,
      fromId: id,
      fromName: currentPlayerName ?? 'Player',
      toId: bankId,
      toName: 'Bank',
      cards: <int>[card.cardIndex],
    );
    if (!mounted || dealId == null) return;
    final bool approved =
        await _waitForDeal(dealId: dealId, what: 'unmortgage');
    if (approved && mounted) {
      final int idx =
          myCards.indexWhere((PlayerCard c) => c.cardIndex == card.cardIndex);
      if (idx != -1) {
        myCards[idx] = myCards[idx].copyWith(mortgaged: false);
      }
      Navigator.of(context).maybePop();
      onBuilt();
      _refreshRoster();
    }
  }
'@ -Replace @'
    final String? bankId = _bankerPlayerId;
    if (bankId == null || bankId.isEmpty) return;
    final String id = playerID ?? '';
    if (id.isEmpty) return;

    final Map<int, BankpopSpace> spaces = await PlayerCards.spaces();
    final int unmortgageValue = card.unmortgageCost(spaces[card.cardIndex]);
    final bool confirmed = await _confirm(
      'Unmortgage ${spaces[card.cardIndex]?.name ?? "this card"}?',
      'You will pay the bank \u00a3$unmortgageValue to clear the mortgage '
          'and start collecting rent again.',
      'Unmortgage',
    );
    if (!confirmed || !mounted) return;

    final int? dealId = await Deals.ask(
      gameId: widget.gameId,
      kind: DealKind.unmortgage,
      fromId: id,
      fromName: currentPlayerName ?? 'Player',
      toId: bankId,
      toName: 'Bank',
      cards: <int>[card.cardIndex],
    );
    if (!mounted || dealId == null) return;
    final bool approved =
        await _waitForDeal(dealId: dealId, what: 'unmortgage');
    if (approved && mounted) {
      final int idx =
          myCards.indexWhere((PlayerCard c) => c.cardIndex == card.cardIndex);
      if (idx != -1) {
        myCards[idx] = myCards[idx].copyWith(mortgaged: false);
      }
      onBuilt();
      _refreshRoster();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
  }
'@

# ---- 4) _sellHouse: confirm + refresh --------------------------------
Edit-File -Path $playerPath -Name 'player: sellHouse confirm + refresh' -Search @'
    final String? bankId = _bankerPlayerId;
    if (bankId == null || bankId.isEmpty) return;
    final String id = playerID ?? '';
    if (id.isEmpty) return;

    final int? dealId = await Deals.ask(
      gameId: widget.gameId,
      kind: DealKind.sellHouse,
      fromId: id,
      fromName: currentPlayerName ?? 'Player',
      toId: bankId,
      toName: 'Bank',
      cards: <int>[card.cardIndex],
    );
    if (!mounted || dealId == null) return;
    final bool approved =
        await _waitForDeal(dealId: dealId, what: 'house sale');
    if (approved && mounted) {
      final int idx =
          myCards.indexWhere((PlayerCard c) => c.cardIndex == card.cardIndex);
      if (idx != -1) {
        myCards[idx] = myCards[idx].copyWith(
          houses: (myCards[idx].houses - 1).clamp(0, 4),
        );
      }
      Navigator.of(context).maybePop();
      onBuilt();
      _refreshRoster();
    }
  }
'@ -Replace @'
    final String? bankId = _bankerPlayerId;
    if (bankId == null || bankId.isEmpty) return;
    final String id = playerID ?? '';
    if (id.isEmpty) return;

    final Map<int, BankpopSpace> spaces = await PlayerCards.spaces();
    final BankpopSpace? space = spaces[card.cardIndex];
    final int refund = (space?.houseCost ?? 0) ~/ 2;
    final bool confirmed = await _confirm(
      'Sell a house on ${space?.name ?? "this card"}?',
      'The bank will pay you \u00a3$refund and one house will be removed '
          'from the card.',
      'Sell house',
    );
    if (!confirmed || !mounted) return;

    final int? dealId = await Deals.ask(
      gameId: widget.gameId,
      kind: DealKind.sellHouse,
      fromId: id,
      fromName: currentPlayerName ?? 'Player',
      toId: bankId,
      toName: 'Bank',
      cards: <int>[card.cardIndex],
    );
    if (!mounted || dealId == null) return;
    final bool approved =
        await _waitForDeal(dealId: dealId, what: 'house sale');
    if (approved && mounted) {
      final int idx =
          myCards.indexWhere((PlayerCard c) => c.cardIndex == card.cardIndex);
      if (idx != -1) {
        myCards[idx] = myCards[idx].copyWith(
          houses: (myCards[idx].houses - 1).clamp(0, 4),
        );
      }
      onBuilt();
      _refreshRoster();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
  }
'@

# ---- 5) _sellHotel: confirm + refresh --------------------------------
Edit-File -Path $playerPath -Name 'player: sellHotel confirm + refresh' -Search @'
    final String? bankId = _bankerPlayerId;
    if (bankId == null || bankId.isEmpty) return;
    final String id = playerID ?? '';
    if (id.isEmpty) return;

    final int? dealId = await Deals.ask(
      gameId: widget.gameId,
      kind: DealKind.sellHotel,
      fromId: id,
      fromName: currentPlayerName ?? 'Player',
      toId: bankId,
      toName: 'Bank',
      cards: <int>[card.cardIndex],
    );
    if (!mounted || dealId == null) return;
    final bool approved =
        await _waitForDeal(dealId: dealId, what: 'hotel sale');
    if (approved && mounted) {
      final int idx =
          myCards.indexWhere((PlayerCard c) => c.cardIndex == card.cardIndex);
      if (idx != -1) {
        myCards[idx] = myCards[idx].copyWith(hotels: 0);
      }
      Navigator.of(context).maybePop();
      onBuilt();
      _refreshRoster();
    }
  }
'@ -Replace @'
    final String? bankId = _bankerPlayerId;
    if (bankId == null || bankId.isEmpty) return;
    final String id = playerID ?? '';
    if (id.isEmpty) return;

    final Map<int, BankpopSpace> spaces = await PlayerCards.spaces();
    final BankpopSpace? space = spaces[card.cardIndex];
    final int refund = (space?.hotelCost ?? 0) ~/ 2;
    final bool confirmed = await _confirm(
      'Sell the hotel on ${space?.name ?? "this card"}?',
      'The bank will pay you \u00a3$refund and the hotel will be removed '
          'from the card.',
      'Sell hotel',
    );
    if (!confirmed || !mounted) return;

    final int? dealId = await Deals.ask(
      gameId: widget.gameId,
      kind: DealKind.sellHotel,
      fromId: id,
      fromName: currentPlayerName ?? 'Player',
      toId: bankId,
      toName: 'Bank',
      cards: <int>[card.cardIndex],
    );
    if (!mounted || dealId == null) return;
    final bool approved =
        await _waitForDeal(dealId: dealId, what: 'hotel sale');
    if (approved && mounted) {
      final int idx =
          myCards.indexWhere((PlayerCard c) => c.cardIndex == card.cardIndex);
      if (idx != -1) {
        myCards[idx] = myCards[idx].copyWith(hotels: 0);
      }
      onBuilt();
      _refreshRoster();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
  }
'@

# ---- 6) _showTradeOffer: auto-close when sender settles/cancels -----
Edit-File -Path $playerPath -Name 'player: trade offer auto-close' -Search @'
  Future<void> _showTradeOffer(
    DealRequest deal,
    Map<int, BankpopSpace> spaces,
  ) async {
    final String? result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFFFFF8E1),
        title: Text('Trade from ${deal.fromName}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (deal.cards.isNotEmpty) ...<Widget>[
                const Text('They give:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                for (final int i in deal.cards)
                  Text('  - ${spaces[i]?.name ?? 'Card #$i'}'),
              ],
              if (deal.offerCash > 0)
                Text('  - \u00a3${deal.offerCash.toStringAsFixed(0)} cash'),
              if (deal.wants.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                const Text('They want:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                for (final int i in deal.wants)
                  Text('  - ${spaces[i]?.name ?? 'Card #$i'}'),
              ],
              if (deal.wantsCash > 0)
                Text('  - \u00a3${deal.wantsCash.toStringAsFixed(0)} cash'),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('reject'),
            child: const Text('Reject'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('counter'),
            child: const Text('Counter'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('accept'),
            child: const Text('Accept'),
          ),
        ],
      ),
    );
    if (!mounted) return;

    if (result == 'accept') {
'@ -Replace @'
  Future<void> _showTradeOffer(
    DealRequest deal,
    Map<int, BankpopSpace> spaces,
  ) async {
    String? autoClosed;
    Timer? poll;
    final String? result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        poll = Timer.periodic(const Duration(seconds: 2), (Timer t) async {
          final String? status = await Deals.statusOf(deal.id);
          if (!dialogContext.mounted) { t.cancel(); return; }
          if (status == null || status == 'pending') return;
          t.cancel();
          autoClosed = status;
          Navigator.of(dialogContext).pop(null);
        });
        return AlertDialog(
          backgroundColor: const Color(0xFFFFF8E1),
          title: Text('Trade from ${deal.fromName}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (deal.cards.isNotEmpty) ...<Widget>[
                  const Text('They give:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  for (final int i in deal.cards)
                    Text('  - ${spaces[i]?.name ?? 'Card #$i'}'),
                ],
                if (deal.offerCash > 0)
                  Text('  - \u00a3${deal.offerCash.toStringAsFixed(0)} cash'),
                if (deal.wants.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  const Text('They want:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  for (final int i in deal.wants)
                    Text('  - ${spaces[i]?.name ?? 'Card #$i'}'),
                ],
                if (deal.wantsCash > 0)
                  Text('  - \u00a3${deal.wantsCash.toStringAsFixed(0)} cash'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                poll?.cancel();
                Navigator.of(dialogContext).pop('reject');
              },
              child: const Text('Reject'),
            ),
            TextButton(
              onPressed: () {
                poll?.cancel();
                Navigator.of(dialogContext).pop('counter');
              },
              child: const Text('Counter'),
            ),
            TextButton(
              onPressed: () {
                poll?.cancel();
                Navigator.of(dialogContext).pop('accept');
              },
              child: const Text('Accept'),
            ),
          ],
        );
      },
    );
    poll?.cancel();
    if (!mounted) return;
    if (autoClosed != null) {
      await showMessage(
        context,
        autoClosed == 'cancelled'
            ? '${deal.fromName} cancelled this trade.'
            : 'This trade was already settled.',
        title: autoClosed == 'cancelled' ? 'Cancelled' : 'Already settled',
      );
      return;
    }

    if (result == 'accept') {
'@

# =========================================================================
# banker_screen.dart -- _showDealApproval auto-close
# =========================================================================
Write-Host "`nEditing banker_screen.dart" -ForegroundColor Yellow

Edit-File -Path $bankerPath -Name 'banker: deal dialog auto-close' -Search @'
  Future<bool?> _showDealApproval(
    DealRequest deal,
    Map<int, BankpopSpace> spaces,
  ) {
    final String cards = deal.cards
        .map((int i) => spaces[i]?.name ?? 'Card #$i')
        .join(', ');
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFFFFF8E1),
        title: Text('${deal.fromName} wants to ${deal.label}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (cards.isNotEmpty) Text(cards),
              if (deal.kind == DealKind.mortgage)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'The bank pays half the printed price.',
                    style: TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ),
              if (deal.kind == DealKind.unmortgage)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'The player pays mortgage value plus 10% interest.',
                    style: TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Decline'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
  }
'@ -Replace @'
  Future<bool?> _showDealApproval(
    DealRequest deal,
    Map<int, BankpopSpace> spaces,
  ) async {
    final String cards = deal.cards
        .map((int i) => spaces[i]?.name ?? 'Card #$i')
        .join(', ');
    String? autoClosed;
    Timer? poll;
    final bool? result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        poll = Timer.periodic(const Duration(seconds: 2), (Timer t) async {
          final String? status = await Deals.statusOf(deal.id);
          if (!dialogContext.mounted) { t.cancel(); return; }
          if (status == null || status == 'pending') return;
          t.cancel();
          autoClosed = status;
          Navigator.of(dialogContext).pop(null);
        });
        return AlertDialog(
          backgroundColor: const Color(0xFFFFF8E1),
          title: Text('${deal.fromName} wants to ${deal.label}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (cards.isNotEmpty) Text(cards),
                if (deal.kind == DealKind.mortgage)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'The bank pays half the printed price.',
                      style: TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                  ),
                if (deal.kind == DealKind.unmortgage)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'The player pays mortgage value plus 10% interest.',
                      style: TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                poll?.cancel();
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Decline'),
            ),
            TextButton(
              onPressed: () {
                poll?.cancel();
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Approve'),
            ),
          ],
        );
      },
    );
    poll?.cancel();
    if (autoClosed != null && mounted) {
      await showMessage(
        context,
        autoClosed == 'cancelled'
            ? '${deal.fromName} cancelled the request.'
            : 'The request was already settled.',
        title: autoClosed == 'cancelled' ? 'Cancelled' : 'Already settled',
      );
      return null;
    }
    return result;
  }
'@

# =========================================================================
# trade_builder_dialog.dart -- confirm before send
# =========================================================================
Write-Host "`nEditing trade_builder_dialog.dart" -ForegroundColor Yellow

Edit-File -Path $tradePath -Name 'trade: confirm before send' -Search @'
  Future<void> _submit() async {
    if (_selectedPlayerId == null) return;
    final myCash = double.tryParse(_myCash.text) ?? 0;
    final theirCash = double.tryParse(_theirCash.text) ?? 0;

    final id = await Deals.ask(
'@ -Replace @'
  Future<void> _submit() async {
    if (_selectedPlayerId == null) return;
    final myCash = double.tryParse(_myCash.text) ?? 0;
    final theirCash = double.tryParse(_theirCash.text) ?? 0;

    final String giveDesc = _describe(
      _mySelectedCards.length, myCash,
    );
    final String getDesc = _describe(
      _theirSelectedCards.length, theirCash,
    );
    final bool confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFFF8E1),
        title: const Text('Send this trade?'),
        content: Text(
          'You give: $giveDesc\n'
          'You get: $getDesc\n\n'
          '$_selectedPlayerName will be asked to accept or counter.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final id = await Deals.ask(
'@

Edit-File -Path $tradePath -Name 'trade: _describe helper' -Search @'
  @override
  Widget build(BuildContext context) {
    final otherPlayers = widget.players
        .where((p) => p['player_id'] != widget.myId)
        .toList();
'@ -Replace @'
  /// "2 cards and \u00a3150" - the summary line in the confirm dialog.
  static String _describe(int cardCount, double cash) {
    final List<String> bits = <String>[];
    if (cardCount > 0) {
      bits.add('$cardCount card${cardCount == 1 ? '' : 's'}');
    }
    if (cash > 0) {
      bits.add('\u00a3${cash.toStringAsFixed(0)}');
    }
    if (bits.isEmpty) return 'nothing';
    return bits.join(' and ');
  }

  @override
  Widget build(BuildContext context) {
    final otherPlayers = widget.players
        .where((p) => p['player_id'] != widget.myId)
        .toList();
'@

# =========================================================================
# transactions.dart -- Cards+Houses get new entries, new Trades tab
# =========================================================================
Write-Host "`nEditing transactions.dart" -ForegroundColor Yellow

Edit-File -Path $txPath -Name 'tx: import deals' -Search @'
import 'package:mon/services/card_requests.dart';
'@ -Replace @'
import 'package:mon/services/card_requests.dart';
import 'package:mon/services/deals.dart';
'@

Edit-File -Path $txPath -Name 'tx: extra futures' -Search @'
  /// The houses and hotels half: every building that was approved, newest first.
  late Future<List<CardRequest>> _buildingsFuture;
'@ -Replace @'
  /// The houses and hotels half: every building that was approved, newest first.
  late Future<List<CardRequest>> _buildingsFuture;

  /// Mortgage / unmortgage events, so the Cards tab can show them too.
  late Future<List<DealRequest>> _mortgagesFuture;

  /// House / hotel sales back to the bank, so the Houses tab can show them.
  late Future<List<DealRequest>> _houseSalesFuture;

  /// Every trade this player sent or received, settled or otherwise.
  late Future<List<DealRequest>> _tradesFuture;
'@

Edit-File -Path $txPath -Name 'tx: initState' -Search @'
    _buildingsFuture = _fetchBuildings();
  }
'@ -Replace @'
    _buildingsFuture = _fetchBuildings();
    _mortgagesFuture = _fetchMortgages();
    _houseSalesFuture = _fetchHouseSales();
    _tradesFuture = _fetchTrades();
  }
'@

# ---- New fetch methods, inserted before _fetchRows ------------------
Edit-File -Path $txPath -Name 'tx: fetch helpers' -Search @'
  /// This player's newest rows in this game, capped at 200. The indexed filter
'@ -Replace @'
  /// Approved mortgage / unmortgage deals involving this player, newest first.
  Future<List<DealRequest>> _fetchMortgages() async {
    try {
      final List<dynamic> rows = await Supabase.instance.client
          .from('deal_requests')
          .select()
          .eq('game_id', widget.gameId)
          .inFilter('kind', <String>['mortgage', 'unmortgage'])
          .eq('status', 'approved')
          .or('from_id.eq.${widget.playerId},to_id.eq.${widget.playerId}')
          .order('date', ascending: false)
          .order('time', ascending: false)
          .limit(200);
      return rows
          .cast<Map<String, dynamic>>()
          .map(DealRequest.fromMap)
          .toList();
    } catch (error) {
      debugPrint('Could not read mortgages: $error');
      return const <DealRequest>[];
    }
  }

  /// House / hotel sales back to the bank for this game, or for one player when
  /// showAllPlayers is false.
  Future<List<DealRequest>> _fetchHouseSales() async {
    try {
      final builder = Supabase.instance.client
          .from('deal_requests')
          .select()
          .eq('game_id', widget.gameId)
          .inFilter('kind', <String>['sell_house', 'sell_hotel'])
          .eq('status', 'approved');
      final filtered = widget.showAllPlayers
          ? builder
          : builder.eq('from_id', widget.playerId);
      final List<dynamic> rows = await filtered
          .order('date', ascending: false)
          .order('time', ascending: false)
          .limit(200);
      return rows
          .cast<Map<String, dynamic>>()
          .map(DealRequest.fromMap)
          .toList();
    } catch (error) {
      debugPrint('Could not read house sales: $error');
      return const <DealRequest>[];
    }
  }

  /// Every trade this player sent or received, in any final state.
  Future<List<DealRequest>> _fetchTrades() async {
    try {
      final List<dynamic> rows = await Supabase.instance.client
          .from('deal_requests')
          .select()
          .eq('game_id', widget.gameId)
          .eq('kind', 'trade')
          .inFilter('status', <String>['approved', 'rejected', 'cancelled'])
          .or('from_id.eq.${widget.playerId},to_id.eq.${widget.playerId}')
          .order('date', ascending: false)
          .order('time', ascending: false)
          .limit(200);
      return rows
          .cast<Map<String, dynamic>>()
          .map(DealRequest.fromMap)
          .toList();
    } catch (error) {
      debugPrint('Could not read trades: $error');
      return const <DealRequest>[];
    }
  }

  /// This player's newest rows in this game, capped at 200. The indexed filter
'@

# ---- Tab count / TabBar / TabBarView --------------------------------
Edit-File -Path $txPath -Name 'tx: tab controller' -Search @'
    return DefaultTabController(
      length: 3,
      child: Scaffold(
'@ -Replace @'
    return DefaultTabController(
      length: 4,
      child: Scaffold(
'@

Edit-File -Path $txPath -Name 'tx: tab bar' -Search @'
          tabs: [
            Tab(text: 'Transactions'),
            Tab(text: 'Cards'),
            Tab(text: 'Houses'),
          ],
'@ -Replace @'
          tabs: [
            Tab(text: 'Transactions'),
            Tab(text: 'Cards'),
            Tab(text: 'Houses'),
            Tab(text: 'Trades'),
          ],
'@

Edit-File -Path $txPath -Name 'tx: tab view' -Search @'
      body: TabBarView(
        children: [
          _buildTransactionsTab(),
          _buildCardsTab(),
          _buildHousesTab(),
        ],
      ),
'@ -Replace @'
      body: TabBarView(
        children: [
          _buildTransactionsTab(),
          _buildCardsTab(),
          _buildHousesTab(),
          _buildTradesTab(),
        ],
      ),
'@

# ---- Replace _buildCardsTab -------------------------------------------
Edit-File -Path $txPath -Name 'tx: cards tab merge' -Search @'
  /// The cards this player bought or sold, newest first.
  Widget _buildCardsTab() {
    return FutureBuilder<List<PlayerCard>>(
      future: _cardsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF689F38)),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Could not load cards: ${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final cards = snapshot.data ?? const <PlayerCard>[];
        if (cards.isEmpty) {
          return const Center(child: Text("No cards yet."));
        }

        return FutureBuilder<Map<int, BankpopSpace>>(
          future: _spacesFuture,
          builder: (context, spaceSnapshot) {
            final spaces = spaceSnapshot.data ?? const <int, BankpopSpace>{};
            return ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: cards.length,
              itemBuilder: (context, index) {
                return _buildCardRow(cards[index], spaces);
              },
            );
          },
        );
      },
    );
  }
'@ -Replace @'
  /// Cards this player bought or sold, newest first, interleaved with the
  /// mortgage / unmortgage events on them.
  Widget _buildCardsTab() {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait<dynamic>([_cardsFuture, _mortgagesFuture]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF689F38)),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Could not load cards: ${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final cards = (snapshot.data![0] as List).cast<PlayerCard>();
        final mortgages = (snapshot.data![1] as List).cast<DealRequest>();
        if (cards.isEmpty && mortgages.isEmpty) {
          return const Center(child: Text("No cards yet."));
        }

        return FutureBuilder<Map<int, BankpopSpace>>(
          future: _spacesFuture,
          builder: (context, spaceSnapshot) {
            final spaces = spaceSnapshot.data ?? const <int, BankpopSpace>{};
            final entries = <MapEntry<String, Widget>>[];
            for (final PlayerCard card in cards) {
              entries.add(MapEntry(
                '${card.date} ${card.time}',
                _buildCardRow(card, spaces),
              ));
            }
            for (final DealRequest m in mortgages) {
              entries.add(MapEntry(
                '${m.date} ${m.time}',
                _buildMortgageRow(m, spaces),
              ));
            }
            entries.sort((a, b) => b.key.compareTo(a.key));
            return ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: entries.length,
              itemBuilder: (context, index) => entries[index].value,
            );
          },
        );
      },
    );
  }
'@

# ---- Replace _buildHousesTab -----------------------------------------
Edit-File -Path $txPath -Name 'tx: houses tab merge' -Search @'
  /// Houses and hotels that have been bought in this game, newest first.
  Widget _buildHousesTab() {
    return FutureBuilder<List<CardRequest>>(
      future: _buildingsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF689F38)),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Could not load houses: ${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final requests = snapshot.data ?? const <CardRequest>[];
        if (requests.isEmpty) {
          return const Center(child: Text('No houses or hotels yet.'));
        }

        return FutureBuilder<Map<int, BankpopSpace>>(
          future: _spacesFuture,
          builder: (context, spaceSnapshot) {
            final spaces = spaceSnapshot.data ?? const <int, BankpopSpace>{};
            return ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: requests.length,
              itemBuilder: (context, index) =>
                  _buildBuildingRow(requests[index], spaces),
            );
          },
        );
      },
    );
  }
'@ -Replace @'
  /// Houses and hotels bought and sold in this game, newest first.
  Widget _buildHousesTab() {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait<dynamic>([_buildingsFuture, _houseSalesFuture]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF689F38)),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Could not load houses: ${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final builds = (snapshot.data![0] as List).cast<CardRequest>();
        final sales = (snapshot.data![1] as List).cast<DealRequest>();
        if (builds.isEmpty && sales.isEmpty) {
          return const Center(child: Text('No houses or hotels yet.'));
        }

        return FutureBuilder<Map<int, BankpopSpace>>(
          future: _spacesFuture,
          builder: (context, spaceSnapshot) {
            final spaces = spaceSnapshot.data ?? const <int, BankpopSpace>{};
            final entries = <MapEntry<String, Widget>>[];
            for (final CardRequest b in builds) {
              entries.add(MapEntry(
                '${b.date} ${b.time}',
                _buildBuildingRow(b, spaces),
              ));
            }
            for (final DealRequest s in sales) {
              entries.add(MapEntry(
                '${s.date} ${s.time}',
                _buildHouseSaleRow(s, spaces),
              ));
            }
            entries.sort((a, b) => b.key.compareTo(a.key));
            return ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: entries.length,
              itemBuilder: (context, index) => entries[index].value,
            );
          },
        );
      },
    );
  }
'@

# ---- Append new row widgets + Trades tab at end of class -------------
Edit-File -Path $txPath -Name 'tx: extra builders + trades tab' -Search @'
  Widget _buildCardRow(PlayerCard card, Map<int, BankpopSpace> spaces) {
'@ -Replace @'
  /// A mortgage / unmortgage event in the Cards tab.
  Widget _buildMortgageRow(DealRequest d, Map<int, BankpopSpace> spaces) {
    final int cardIndex = d.cards.isNotEmpty ? d.cards.first : -1;
    final BankpopSpace? space = spaces[cardIndex];
    final String name = space?.name ?? 'Card #$cardIndex';
    final Color groupColor = space == null
        ? Colors.grey
        : Color(BankpopBoard.colorForGroup(space.color));
    final bool isMortgage = d.kind == DealKind.mortgage;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.white, width: 1),
          borderRadius: const BorderRadius.all(Radius.circular(12)),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 8,
              height: 38,
              decoration: BoxDecoration(
                color: groupColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 5,
              child: Text(
                name,
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 4,
              child: Row(
                children: <Widget>[
                  Icon(
                    isMortgage ? Icons.lock : Icons.lock_open,
                    size: 14,
                    color: const Color(0xFF689F38),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      isMortgage ? 'Mortgaged' : 'Unmortgaged',
                      style: TextStyle(
                          fontSize: 12.sp, color: Colors.grey[700]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                _relativeTime('${d.date} ${d.time}'),
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12.sp, color: Colors.grey[600]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A house / hotel sold back to the bank in the Houses tab.
  Widget _buildHouseSaleRow(DealRequest d, Map<int, BankpopSpace> spaces) {
    final int cardIndex = d.cards.isNotEmpty ? d.cards.first : -1;
    final BankpopSpace? space = spaces[cardIndex];
    final String name = space?.name ?? 'Card #$cardIndex';
    final Color groupColor = space == null
        ? Colors.grey
        : Color(BankpopBoard.colorForGroup(space.color));
    final bool isHotel = d.kind == DealKind.sellHotel;
    final double refund =
        ((isHotel ? space?.hotelCost : space?.houseCost) ?? 0) / 2;
    final String who = widget.showAllPlayers ? d.fromName : '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.white, width: 1),
          borderRadius: const BorderRadius.all(Radius.circular(12)),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 8,
              height: 38,
              decoration: BoxDecoration(
                color: groupColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 5,
              child: Text(
                name,
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 4,
              child: Row(
                children: <Widget>[
                  Icon(
                    isHotel ? Icons.business : Icons.home,
                    size: 15,
                    color: Colors.orange.shade700,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      isHotel ? 'Hotel sold' : 'House sold',
                      style: TextStyle(
                          fontSize: 12.sp, color: Colors.grey[700]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    '+\u00a3${refund.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.green.shade700,
                    ),
                  ),
                  if (who.isNotEmpty)
                    Text(
                      who,
                      style: TextStyle(
                          fontSize: 11.sp, color: Colors.grey[600]),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Every trade this player was party to, in any final state.
  Widget _buildTradesTab() {
    return FutureBuilder<List<DealRequest>>(
      future: _tradesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF689F38)),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Could not load trades: ${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final trades = snapshot.data ?? const <DealRequest>[];
        if (trades.isEmpty) {
          return const Center(child: Text('No trades yet.'));
        }

        return FutureBuilder<Map<int, BankpopSpace>>(
          future: _spacesFuture,
          builder: (context, spaceSnapshot) {
            final spaces = spaceSnapshot.data ?? const <int, BankpopSpace>{};
            return ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: trades.length,
              itemBuilder: (context, index) =>
                  _buildTradeRow(trades[index], spaces),
            );
          },
        );
      },
    );
  }

  Widget _buildTradeRow(DealRequest trade, Map<int, BankpopSpace> spaces) {
    final Color statusColor;
    switch (trade.status) {
      case 'approved':
        statusColor = Colors.green.shade700;
        break;
      case 'rejected':
        statusColor = Colors.red.shade700;
        break;
      case 'cancelled':
        statusColor = Colors.grey.shade600;
        break;
      default:
        statusColor = Colors.orange.shade700;
    }
    final List<String> givenBits = <String>[
      if (trade.cards.isNotEmpty)
        trade.cards
            .map((int i) => spaces[i]?.name ?? 'Card #$i')
            .join(', '),
      if (trade.offerCash > 0)
        '\u00a3${trade.offerCash.toStringAsFixed(0)}',
    ];
    final List<String> gotBits = <String>[
      if (trade.wants.isNotEmpty)
        trade.wants
            .map((int i) => spaces[i]?.name ?? 'Card #$i')
            .join(', '),
      if (trade.wantsCash > 0)
        '\u00a3${trade.wantsCash.toStringAsFixed(0)}',
    ];
    final String given = givenBits.isEmpty ? '' : givenBits.join(' + ');
    final String got = gotBits.isEmpty ? '' : gotBits.join(' + ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.white, width: 1),
          borderRadius: const BorderRadius.all(Radius.circular(12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${_displayName(trade.fromName)} \u2192 ${_displayName(trade.toName)}',
                    style: TextStyle(
                        fontSize: 13.sp, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    trade.status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (given.isNotEmpty)
              Text(
                'Gave: $given',
                style: TextStyle(fontSize: 11, color: Colors.grey[700]),
              ),
            if (got.isNotEmpty)
              Text(
                'Got: $got',
                style: TextStyle(fontSize: 11, color: Colors.grey[700]),
              ),
            if (trade.date.isNotEmpty)
              Text(
                _relativeTime('${trade.date} ${trade.time}'),
                style: TextStyle(fontSize: 10, color: Colors.grey[500]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardRow(PlayerCard card, Map<int, BankpopSpace> spaces) {
'@

# =========================================================================
# Done
# =========================================================================
Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "All $script:editCount edits applied." -ForegroundColor Green
Write-Host "Backup: $backupDir" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. flutter analyze"
Write-Host "  2. flutter test test/building_rules_test.dart"
Write-Host "  3. flutter test test/card_mode_test.dart"
Write-Host ""
Write-Host "Manual checks:" -ForegroundColor Yellow
Write-Host "  * Mortgage a card -> confirmation dialog -> approve -> mini card"
Write-Host "    shows M immediately without closing the sheet."
Write-Host "  * Sell a house -> same, the dots update in place."
Write-Host "  * Open a trade offer on the receiving player, cancel it from"
Write-Host "    the sending side -> the dialog closes itself."
Write-Host "  * Open a mortgage request on the banker, cancel it from the"
Write-Host "    player side -> the dialog closes itself."
Write-Host "  * History -> Cards tab now lists mortgages alongside acquisitions."
Write-Host "  * History -> Houses tab now lists sales alongside purchases."
Write-Host "  * History -> Trades tab shows every trade with its status."
Write-Host ""
Write-Host "To roll back: Copy-Item '$backupDir\lib\*' 'lib\' -Recurse -Force" -ForegroundColor DarkGray