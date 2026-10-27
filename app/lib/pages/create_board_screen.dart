import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/routes.dart';
import 'package:mon/services/account.dart';
import 'package:mon/services/board_catalog.dart';
import 'package:mon/services/board_share.dart';
import 'package:mon/widgets/app_message.dart';
import 'package:mon/widgets/board_transfer.dart';
import 'package:mon/widgets/app_metrics.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Making a board of your own: give it a name, then rename the spaces.
///
/// Only names can change. Prices, rents, colour groups and building costs come
/// from the built-in board the copy is made from, so a player's board can never
/// hand somebody cheaper rent or a cheaper hotel - the banker cannot edit the
/// rules of the game from here. The two utilities keep "Electric" and "City
/// Water" because their tiles draw their own artwork, and a station's name
/// always ends in "Station" so the game keeps recognising it.
///
/// The board is saved to `game_boards` against the player's account
/// (supabase/boards.sql) and is only ever offered back to them: nobody else
/// sees it in their picker. A board a friend sent ([draft]) opens here too,
/// with its names already filled in, so importing is the same screen as making
/// one from scratch - and the same checks.
class CreateBoardScreen extends StatefulWidget {
  const CreateBoardScreen({super.key, this.draft});

  /// A board imported by paste or by file, or null when this player is
  /// starting one from the built-in names.
  final BoardDraft? draft;

  @override
  State<CreateBoardScreen> createState() => _CreateBoardScreenState();
}

/// One editable space: the space it was copied from, and the field holding the
/// name this player wants.
class _Slot {
  _Slot(this.space, this.controller);

  final BankpopSpace space;
  final TextEditingController controller;

  bool get isStation => space.color == 'Station';

  /// A colour property: its name is printed in the tile's colour block.
  bool get isColour =>
      space.isProperty &&
      space.color != null &&
      space.color != 'Station' &&
      space.color != 'Utility';

  /// The longest name this slot accepts.
  int get maxLength =>
      isColour ? BoardNames.colourNameMaxLength : BoardNames.maxLength;

  String get name => controller.text.trim();
}

class _CreateBoardScreenState extends State<CreateBoardScreen> {
  final TextEditingController _nameController = TextEditingController();

  /// The emoji a board can be listed under: the empty one draws the person
  /// icon a board without a flag has always had.
  static const List<String> _emojis = <String>[
    '',
    '🌍',
    '🏝️',
    '🏰',
    '🌆',
    '🚀',
    '🐉',
    '⚽',
    '🎸',
    '🍕',
    '🌵',
    '🎲',
    '👑',
    '🦁',
    '🎨',
    '🌊',
  ];

  /// The spaces a player may rename, in board order.
  final List<_Slot> _slots = <_Slot>[];

  /// Electric and City Water: shown so the board reads complete, but fixed.
  final List<BankpopSpace> _fixed = <BankpopSpace>[];

  bool _loading = true;
  bool _signedIn = false;
  bool _saving = false;
  String? _error;
  int _step = 0;

  /// The board being imported, if any. It can also be set from inside the
  /// editor: "Import" sits on the first step, so a player who has already
  /// typed a name can decide to use a friend's board instead.
  BoardDraft? _draft;

  /// The emoji this board is listed under in the pickers. Empty draws a
  /// person icon instead, the same way a board with no flag always has.
  String _flag = '';

  /// The money symbol this board's prices are written in. Empty until the
  /// first load, which fills it with the currency of the country being copied.
  String _currency = '';

  /// The built-in board the names are relative to: the one the imported board
  /// was copied from, or the default country when starting from scratch.
  late String _baseId = widget.draft?.baseId ?? BoardCatalog.fallbackId;

  @override
  void initState() {
    super.initState();
    _draft = widget.draft;
    _flag = widget.draft?.flag ?? '';
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final _Slot slot in _slots) {
      slot.controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final bool signedIn = await Account.isSignedIn();
    if (!mounted) return;
    setState(() {
      _signedIn = signedIn;
      _loading = signedIn;
    });
    if (!signedIn) return;

    // A second load is an import: the names start again from the new base.
    for (final _Slot slot in _slots) {
      slot.controller.dispose();
    }
    _slots.clear();
    _fixed.clear();
    _baseId = _draft?.baseId ?? BoardCatalog.fallbackId;

    try {
      BankpopBoard base;
      try {
        base = await BoardCatalog.board(_baseId);
      } catch (error) {
        // The country this board was copied from is not on this device's
        // server; the names still apply to the built-in board, so the editor
        // opens on that rather than refusing the import outright.
        debugPrint('Board $_baseId could not be read: $error');
        _baseId = BoardCatalog.fallbackId;
        base = await BoardCatalog.board(_baseId);
      }
      // A new board starts on the country's own currency; a board the player
      // already picked a symbol for keeps it.
      if (_currency.isEmpty) _currency = base.currency;
      final BoardDraft? draft = _draft;
      if (draft != null && _nameController.text.trim().isEmpty) {
        _nameController.text = draft.name;
      }
      final List<BankpopSpace> properties = base.spaces
          .where((BankpopSpace space) => space.isProperty)
          .toList()
        ..sort((BankpopSpace a, BankpopSpace b) => a.index.compareTo(b.index));
      for (final BankpopSpace space in properties) {
        if (BoardNames.fixed.contains(space.name)) {
          _fixed.add(space);
        } else {
          // An imported board names its spaces by card index; a file from
          // before that format named them by their built-in name. Anything it
          // did not rename keeps the country's own name.
          final String name = draft?.renamesByIndex[space.index] ??
              draft?.renames[space.name] ??
              space.name;
          _slots.add(_Slot(space, TextEditingController(text: name)));
        }
      }
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (error) {
      debugPrint('Could not load the board to copy: $error');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'The built-in boards could not be read. Run '
            'supabase/boards.sql once to add them, then open this screen '
            'again.';
      });
    }
  }

  /// Brings in a board a friend sent, without leaving the editor: paste the
  /// JSON or choose the file, and its names (and emoji) fill this board in.
  Future<void> _importFromFriend() async {
    final BoardDraft? draft = await showBoardImportSheet(context);
    if (draft == null || !mounted) return;
    setState(() {
      _draft = draft;
      _flag = draft.flag;
      // The shared file carries names only, so the symbol comes back to the
      // country the board was copied from.
      _currency = '';
      if (_nameController.text.trim().isEmpty) {
        _nameController.text = draft.name;
      }
      _loading = true;
    });
    await _load();
    if (!mounted) return;
    setState(() => _step = 1);
  }

  /// Everything the editor can reject, in the order a player would hit it.
  String? _validate() {
    final String name = _nameController.text.trim();
    if (name.isEmpty) return 'Give your board a name first';
    if (name.length > BoardNames.maxLength) return 'That board name is too long';

    final Set<String> seen = <String>{
      for (final String name in BoardNames.fixed) name.toLowerCase(),
    };
    for (final _Slot slot in _slots) {
      final String value = _finishName(slot);
      if (value.isEmpty) return 'Every space needs a name';
      if (value.length > slot.maxLength) {
        return slot.isColour
            ? '"$value" is too long: a colour card fits '
                '${BoardNames.colourNameMaxLength} characters'
            : '"$value" is too long for a space';
      }
      final String key = value.toLowerCase();
      if (!seen.add(key)) return '"$value" is used twice on this board';
    }
    return null;
  }

  /// Stations are completed by [BoardNames.finishStation]; everything else is
  /// used as typed.
  String _finishName(_Slot slot) =>
      slot.isStation ? BoardNames.finishStation(slot.name) : slot.name;

  Future<void> _save() async {
    final String? problem = _validate();
    if (problem != null) {
      showMessage(context, problem);
      return;
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? ownerId = prefs.getString('account_id');
    if (ownerId == null || ownerId.isEmpty) {
      if (!mounted) return;
      showMessage(context, 'Sign in again to save a board to your account');
      return;
    }

    final Map<String, String> renames = <String, String>{};
    for (final _Slot slot in _slots) {
      renames[slot.space.name] = _finishName(slot);
    }

    setState(() => _saving = true);
    final BoardCreateResult result = await BoardCatalog.createCustom(
      name: _nameController.text.trim(),
      ownerId: ownerId,
      renames: renames,
      flag: _flag,
      baseId: _baseId,
      currency: _currency,
    );
    if (!mounted) return;
    setState(() => _saving = false);

    if (result.ok) {
      context.pop<String>(result.boardId);
      return;
    }
    if (result.duplicateName) {
      showMessage(context,
          'You already have a board with that name. Pick another name.');
      return;
    }
    showMessage(
      context,
      'The board could not be saved. Check the connection and try again.',
    );
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
          _draft == null ? 'Create your board' : 'Imported board',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18.sp,
            color: const Color(0xFF689F38),
          ),
        ),
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_signedIn) {
      return _SignedOut(onSignIn: _signInThenReload);
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
        ),
      );
    }
    return _step == 0 ? _nameStep() : _namesStep();
  }

  Widget _nameStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Step 1 of 2',
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF689F38),
            ),
          ),
          SizedBox(height: 6),
          Text(
            'What is your country called?',
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF33691E),
            ),
          ),
          SizedBox(height: 8),
          Text(
            'This is the name the board is listed under and the name every '
            'player sees when the banker starts a game with it.',
            style: TextStyle(fontSize: 13.sp, color: Colors.black54),
          ),
          if (_draft != null) ...<Widget>[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFDCEDC8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.download_done,
                      size: 18, color: Color(0xFF33691E)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'The names are already filled in from the board you '
                      'imported. Change any of them you like, then save it to '
                      'your account.',
                      style: TextStyle(
                          fontSize: 12.sp, color: const Color(0xFF33691E)),
                    ),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: 18),
          TextField(
            controller: _nameController,
            maxLength: BoardNames.maxLength,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Board name',
              hintText: 'e.g. My Home Town',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onSubmitted: (_) => _nextStep(),
          ),
          Text(
            'Pick an emoji for it',
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF558B2F),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final String emoji in _emojis)
                GestureDetector(
                  onTap: () => setState(() => _flag = emoji),
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _flag == emoji
                          ? const Color(0xFFC5E1A5)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _flag == emoji
                            ? const Color(0xFF689F38)
                            : Colors.black12,
                        width: _flag == emoji ? 2 : 1,
                      ),
                    ),
                    child: emoji.isEmpty
                        ? const Icon(Icons.person_outline,
                            size: 20, color: Colors.black45)
                        : Text(emoji, style: const TextStyle(fontSize: 20)),
                  ),
                ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            'Pick the money symbol',
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF558B2F),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final String symbol in BoardCurrencies.choices)
                GestureDetector(
                  onTap: () => setState(() => _currency = symbol),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 44),
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _currency == symbol
                          ? const Color(0xFFC5E1A5)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _currency == symbol
                            ? const Color(0xFF689F38)
                            : Colors.black12,
                        width: _currency == symbol ? 2 : 1,
                      ),
                    ),
                    child: Text(
                      symbol,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _saving ? null : _importFromFriend,
            icon: const Icon(Icons.file_download_outlined, size: 18),
            label: const Text('Import a board a friend sent'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF33691E),
              side: const BorderSide(color: Color(0xFFAED581)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          SizedBox(height: 10),
          ElevatedButton(
            onPressed: _nextStep,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF689F38),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text('Continue', style: TextStyle(fontSize: 16.sp)),
          ),
        ],
      ),
    );
  }

  /// Signing in is the one thing this screen asks for, so it comes back to the
  /// editor instead of starting over from the home screen.
  Future<void> _signInThenReload() async {
    await context.push(AppRoutes.authReturning);
    if (!mounted) return;
    setState(() => _loading = true);
    await _load();
  }

  void _nextStep() {
    final String problem = _nameController.text.trim().isEmpty
        ? 'Give your board a name first'
        : (_nameController.text.trim().length > BoardNames.maxLength
            ? 'That board name is too long'
            : '');
    if (problem.isNotEmpty) {
      showMessage(context, problem);
      return;
    }
    setState(() => _step = 1);
  }

  Widget _namesStep() {
    // Grouped by colour so the list reads like the board it becomes.
    final List<_Slot> streets =
        _slots.where((_Slot slot) => !slot.isStation).toList();
    final List<_Slot> stations =
        _slots.where((_Slot slot) => slot.isStation).toList();

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            children: <Widget>[
              Text(
                'Step 2 of 2',
                style: TextStyle(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF689F38),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Rename the spaces',
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF33691E),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Only the names can be changed - the prices, rents and '
                'building costs are the game\'s. A station always ends with '
                '"Station", and Electric and City Water keep their names.',
                style: TextStyle(fontSize: 12.sp, color: Colors.black54),
              ),
              const SizedBox(height: 14),
              _sectionTitle('Stations'),
              for (final _Slot slot in stations) _slotField(slot),
              const SizedBox(height: 16),
              _sectionTitle('Streets'),
              for (final _Slot slot in streets) _slotField(slot),
              const SizedBox(height: 16),
              _sectionTitle('Fixed spaces'),
              for (final BankpopSpace space in _fixed) _fixedRow(space),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => setState(() => _step = 0),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF33691E),
                    side: const BorderSide(color: Color(0xFFAED581)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF689F38),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text('Save board', style: TextStyle(fontSize: 15.sp)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13.sp,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF558B2F),
        ),
      ),
    );
  }

  Widget _slotField(_Slot slot) {
    final Color group = Color(BankpopBoard.colorForGroup(slot.space.color));
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: <Widget>[
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: group,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: Colors.black26),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: slot.controller,
              maxLength: slot.maxLength,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                labelText: slot.isStation ? 'Station name' : null,
                helperText: slot.isStation ? 'Ends with "Station"' : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fixedRow(BankpopSpace space) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          const Icon(Icons.lock_outline, size: 16, color: Colors.black45),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              space.name,
              style: TextStyle(fontSize: 13.sp, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when nobody is signed in: boards are attached to an account, so this
/// is the one screen that cannot work for a guest.
class _SignedOut extends StatelessWidget {
  const _SignedOut({required this.onSignIn});

  final Future<void> Function() onSignIn;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.lock_outline, size: 46, color: Color(0xFF689F38)),
          const SizedBox(height: 14),
          Text(
            'Sign in to create a board',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF33691E),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your board is saved to your account, so it is there on any phone '
            'you sign in on - and only you can see it. Guests can still play '
            'on any of the built-in countries.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.sp, color: Colors.black54),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: onSignIn,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF689F38),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Sign in'),
          ),
        ],
      ),
    );
  }
}
