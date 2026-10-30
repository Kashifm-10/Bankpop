import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/routes.dart';
import 'package:mon/services/account.dart';
import 'package:mon/services/board_catalog.dart';
import 'package:mon/services/board_image.dart';
import 'package:mon/services/board_share.dart';
import 'package:mon/widgets/app_content.dart';
import 'package:mon/widgets/app_dialog.dart';
import 'package:mon/widgets/bankpop_board_view.dart';
import 'package:mon/widgets/board_transfer.dart';
import 'package:mon/widgets/country_chip.dart';
import 'package:mon/widgets/app_metrics.dart';

/// The boards, before a game exists: pick one and look at the board it plays on
/// and the two decks that come with it.
///
/// This is the same board the banker chooses at the table, drawn by the same
/// widget, so what a player sees here is what they will get in a game. A
/// signed-in player can also start their own board from here.
class BoardPreviewScreen extends StatefulWidget {
  const BoardPreviewScreen({super.key, this.initialBoard});

  /// Usually null, which opens on the board this device played last.
  final String? initialBoard;

  @override
  State<BoardPreviewScreen> createState() => _BoardPreviewScreenState();
}

class _BoardPreviewScreenState extends State<BoardPreviewScreen> {
  late Future<List<BoardListing>> _boards;
  late String _boardId;

  /// True while the printable picture of the board is being drawn, so the
  /// download button cannot be pressed twice.
  bool _downloading = false;

  /// The boards the picker last drew, so the app bar's download button knows
  /// which one is on screen.
  List<BoardListing> _knownBoards = const <BoardListing>[];

  @override
  void initState() {
    super.initState();
    _boardId = widget.initialBoard ?? BoardCatalog.activeId;
    _boards = BoardCatalog.available(refresh: true);
  }

  void _select(String boardId) {
    if (boardId == _boardId) return;
    setState(() => _boardId = boardId);
  }

  /// The board on screen: the row the picker drew that matches the choice, so
  /// download/share act on what the player is looking at.
  BoardListing _selected() {
    final List<BoardListing> known = _knownBoards;
    if (known.isEmpty) {
      return BoardListing(boardId: _boardId, name: 'Board');
    }
    return known.firstWhere(
      (BoardListing board) => board.boardId == _boardId,
      orElse: () => known.first,
    );
  }

  /// Opens the editor and, when it saves, shows the board it made.
  ///
  /// Making a board is the one thing here that needs an account - it is saved
  /// against the player, so it can be found again on another device. A guest
  /// is told so before the editor opens, not after they have typed 28 names.
  Future<void> _createBoard() async {
    if (!await Account.isSignedIn()) {
      if (!mounted) return;
      final bool signIn = await showAppConfirm(
        context,
        title: 'Log in to create a board',
        icon: Icons.lock_outline,
        confirmLabel: 'Sign in',
        cancelLabel: 'Not now',
        message: 'Your own boards are saved to your account, so they are '
            'there on any device you sign in on and nobody else sees them.\n\n'
            'Until then you can play on any of the built-in countries.',
      );
      if (!signIn || !mounted) return;
      final bool? signedIn = await context.push<bool>(AppRoutes.authReturning);
      if (signedIn != true || !mounted) return;
      setState(() => _boards = BoardCatalog.available(refresh: true));
    }
    if (!mounted) return;
    await _openEditor();
  }

  /// Paste or pick a board a friend sent. It opens in the same editor with its
  /// names filled in - nothing is saved until this player presses Save.
  Future<void> _importBoard() async {
    final BoardDraft? draft = await showBoardImportSheet(context);
    if (draft == null || !mounted) return;
    await _openEditor(draft);
  }

  Future<void> _openEditor([BoardDraft? draft]) async {
    final String? created =
        await context.push<String>(AppRoutes.newBoard, extra: draft);
    if (!mounted) return;
    setState(() => _boards = BoardCatalog.available(refresh: true));
    if (created != null && created.isNotEmpty) {
      setState(() => _boardId = created);
    }
  }

  /// Saves the board as a square PNG, with every card's name in its colour
  /// block, so it can be printed and played on at the table.
  Future<void> _downloadBoard(BoardListing listing) async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final BankpopBoard board = await BoardCatalog.board(listing.boardId);
      if (!mounted) return;
      final Uint8List bytes = await BoardImage.render(context, board);
      final String? path = await BoardImage.save(bytes, listing.name);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            path == null
                ? 'Board saved to your downloads'
                : 'Board saved to $path',
          ),
        ),
      );
    } catch (error) {
      debugPrint('Could not prepare the board for printing: $error');
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('That board could not be prepared.')),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  /// Sends one of this player's boards to a friend, as text or as a file.
  Future<void> _shareBoard(BoardListing listing) async {
    try {
      final BankpopBoard board = await BoardCatalog.board(listing.boardId);
      final String json = await BoardShare.encode(board);
      if (!mounted) return;
      await showBoardShareSheet(
        context,
        boardName: listing.name,
        json: json,
      );
    } catch (error) {
      debugPrint('Could not share the board: $error');
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('That board could not be prepared.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8E1),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: Icon(Icons.chevron_left,
              size: 26.sp, color: const Color(0xFF689F38)),
        ),
        title: Text(
          'Boards & cards',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18.sp,
            color: const Color(0xFF689F38),
          ),
        ),
        // Download, share (only a board of this player's own - the countries
        // are already on everybody's list) and create, in that order.
        actions: <Widget>[
          IconButton(
            tooltip: 'Download this board to print',
            onPressed: _downloading ? null : () => _downloadBoard(_selected()),
            icon: _downloading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined,
                    color: Color(0xFF689F38)),
          ),
          if (_selected().isCustom)
            IconButton(
              tooltip: 'Share this board as JSON',
              onPressed: () => _shareBoard(_selected()),
              icon: const Icon(Icons.ios_share, color: Color(0xFF689F38)),
            ),
          IconButton(
            tooltip: 'Create your own board',
            onPressed: _createBoard,
            icon: const Icon(Icons.add_circle_outline,
                color: Color(0xFF689F38)),
          ),
        ],
      ),
      body: SafeArea(
        // The picker and the board keep a wide but finite measure; the board
        // screen is the one that can use the most room.
        child: AppContent(
          maxWidth: 1280,
          child: FutureBuilder<List<BoardListing>>(
          future: _boards,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final List<BoardListing> boards =
                snap.data ?? const <BoardListing>[];
            _knownBoards = boards;
            if (boards.isEmpty) {
              return _NoBoards(
                isError: snap.hasError,
                onCreate: _createBoard,
                onImport: _importBoard,
              );
            }
            final BoardListing selected = boards.firstWhere(
              (BoardListing board) => board.boardId == _boardId,
              orElse: () => boards.first,
            );
            return Column(
              children: <Widget>[
                SizedBox(
                  height: 44,
                  // A mouse cannot drag a list by default, which left the
                  // picker stuck on the first few flags in a desktop browser.
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      dragDevices: PointerDeviceKind.values.toSet(),
                    ),
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: boards.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (BuildContext context, int index) {
                        final BoardListing board = boards[index];
                        final bool isSelected =
                            board.boardId == selected.boardId;
                        return Center(
                          child: CountryChip(
                            label: board.name,
                            flag: board.flag,
                            icon: board.isMine && board.flag.isEmpty
                                ? Icons.person_outline
                                : null,
                            // Flags only, until one is picked: the row then
                            // reads as the countries rather than as a list.
                            labelVisible: isSelected,
                            selected: isSelected,
                            onTap: () => _select(board.boardId),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      if (selected.flag.isNotEmpty)
                        Text(selected.flag,
                            style: const TextStyle(fontSize: 16)),
                      if (selected.flag.isNotEmpty) const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '${selected.name} board',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15.sp,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF33691E),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _SelectedBoard(boardId: selected.boardId),
                ),
              ],
            );
          },
          ),
        ),
      ),
    );
  }
}

/// The board on its own. Kept in its own widget so switching boards only
/// rebuilds this, not the picker above it.
class _SelectedBoard extends StatefulWidget {
  const _SelectedBoard({required this.boardId});

  final String boardId;

  @override
  State<_SelectedBoard> createState() => _SelectedBoardState();
}

class _SelectedBoardState extends State<_SelectedBoard> {
  late Future<BankpopBoard> _board;

  @override
  void initState() {
    super.initState();
    _board = BoardCatalog.board(widget.boardId);
  }

  @override
  void didUpdateWidget(covariant _SelectedBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.boardId != widget.boardId) {
      _board = BoardCatalog.board(widget.boardId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BankpopBoard>(
      future: _board,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError || !snap.hasData) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Could not load this board: ${snap.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
            ),
          );
        }
        final BankpopBoard board = snap.data!;
        // The same names and prices the download draws: the name sits just
        // under its colour block, so the blocks read as solid bands.
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints area) {
              // Whatever the area leaves, never more than it: the board is
              // square, so it has to fit the smaller side.
              final double size = math.max(
                0,
                math.min(area.maxWidth - 12, area.maxHeight - 12),
              );
              return Center(
                child: BankpopBoardView(
                  board: board,
                  size: size,
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// The database has no boards at all: either the table has not been created
/// (supabase/boards.sql) or the device is offline.
class _NoBoards extends StatelessWidget {
  const _NoBoards({
    required this.isError,
    required this.onCreate,
    required this.onImport,
  });

  final bool isError;
  final Future<void> Function() onCreate;
  final Future<void> Function() onImport;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.grid_on, size: 46, color: Color(0xFF689F38)),
          const SizedBox(height: 12),
          Text(
            isError
                ? 'The boards could not be read'
                : 'There are no boards on the server yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF33691E),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Run supabase/boards.sql once to add the built-in countries, then '
            'reopen this screen. You can still create a board of your own.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.sp, color: Colors.black54),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: onCreate,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF689F38),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Create your own'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onImport,
            child: const Text(
              'Import a board a friend sent',
              style: TextStyle(color: Color(0xFF33691E)),
            ),
          ),
        ],
      ),
    );
  }
}

