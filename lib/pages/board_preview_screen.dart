import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/routes.dart';
import 'package:mon/services/board_catalog.dart';
import 'package:mon/services/board_image.dart';
import 'package:mon/services/board_share.dart';
import 'package:mon/widgets/bankpop_board_view.dart';
import 'package:mon/widgets/board_transfer.dart';
import 'package:mon/widgets/bankpop_deck_sheet.dart';
import 'package:mon/widgets/country_chip.dart';
import 'package:responsive_sizer/responsive_sizer.dart';

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

  /// Opens the editor and, when it saves, shows the board it made.
  Future<void> _createBoard() async {
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
      await BoardImage.share(bytes, listing.name);
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
        // Kept out of the chip row, which scrolls sideways: importing is how a
        // player gets a board a friend sent, so it stays where it is always
        // reachable.
        actions: <Widget>[
          IconButton(
            tooltip: 'Download this board to print',
            onPressed: _downloading
                ? null
                : () {
                    // The rows are built from the same list the picker shows,
                    // so the chip the player is looking at is the one saved.
                    final List<BoardListing> known = _knownBoards;
                    if (known.isEmpty) return;
                    final BoardListing selected = known.firstWhere(
                      (BoardListing board) => board.boardId == _boardId,
                      orElse: () => known.first,
                    );
                    _downloadBoard(selected);
                  },
            icon: _downloading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined,
                    color: Color(0xFF689F38)),
          ),
          IconButton(
            tooltip: 'Import a board',
            onPressed: _importBoard,
            icon: const Icon(Icons.file_upload_outlined,
                color: Color(0xFF689F38)),
          ),
        ],
      ),
      body: SafeArea(
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
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: boards.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (BuildContext context, int index) {
                      if (index == boards.length) {
                        return Center(
                          child: CountryChip(
                            label: 'Create your own',
                            icon: Icons.add_circle_outline,
                            selected: false,
                            onTap: _createBoard,
                          ),
                        );
                      }
                      final BoardListing board = boards[index];
                      return Center(
                        child: CountryChip(
                          label: board.name,
                          flag: board.flag,
                          icon: board.isMine ? Icons.person_outline : null,
                          selected: board.boardId == selected.boardId,
                          onTap: () => _select(board.boardId),
                        ),
                      );
                    },
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
                      // Only a board this player made can be sent on: the
                      // countries are already in everybody's picker.
                      if (selected.isCustom) ...<Widget>[
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: 'Share this board',
                          onPressed: () => _shareBoard(selected),
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.ios_share,
                              size: 20, color: Color(0xFF2E7D32)),
                        ),
                      ],
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
    );
  }
}

/// The board and its two decks. Kept in its own widget so switching boards only
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
        return Column(
          children: <Widget>[
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Whatever the column leaves, never more than it: the board
                  // is square, so it has to fit the smaller side.
                  final double size = math.max(
                    0,
                    math.min(
                      constraints.maxWidth - 12,
                      constraints.maxHeight - 12,
                    ),
                  );
                  return Center(
                    child: BankpopBoardView(board: board, size: size),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: _DeckButton(
                      label: 'Chance cards',
                      icon: Icons.casino_outlined,
                      onTap: () => showBankpopDeckSheet(
                        context,
                        'Chance',
                        board.chanceOptions,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DeckButton(
                      label: 'Community chest',
                      icon: Icons.inventory_2_outlined,
                      onTap: () => showBankpopDeckSheet(
                        context,
                        'Community Chest',
                        board.communityChest,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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

/// The two deck buttons under the board. The decks are the board's own, so they
/// read the same as the sheet a tile opens during a game.
class _DeckButton extends StatelessWidget {
  const _DeckButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18.sp, color: const Color(0xFF2E7D32)),
      label: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12.sp,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF2E7D32),
        ),
      ),
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFFAED581)),
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}
