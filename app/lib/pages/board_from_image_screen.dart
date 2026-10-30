import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mon/models/bankpop_board.dart';
import 'package:mon/routes.dart';
import 'package:mon/services/board_catalog.dart';
import 'package:mon/services/board_ocr.dart';
import 'package:mon/services/board_scan.dart';
import 'package:mon/widgets/app_dialog.dart';
import 'package:mon/widgets/app_message.dart';
import 'package:mon/widgets/board_photo_guide.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Making a board out of a photograph of one.
///
/// A player who already owns a board - a printed one, or a photo of another
/// game - should not have to type twenty-eight names. They take a picture (or
/// pick one they already have), the device reads the squares' names off it, and
/// this screen shows what was read, in board order, each name beside the colour
/// group it belongs to. Nothing is saved blind: every name can be corrected,
/// and the board is only created when the player presses Create.
///
/// Only the names come from the picture. Prices, rents, colour groups, building
/// costs and the order of the squares are the game's, exactly as they are in
/// the editor - a photographed board cannot change a rule.
class BoardFromImageScreen extends StatefulWidget {
  const BoardFromImageScreen({super.key});

  @override
  State<BoardFromImageScreen> createState() => _BoardFromImageScreenState();
}

/// One square on the new board: where it came from, and the name it will have.
class _Square {
  _Square(this.space, this.name, {required this.fromPhoto});

  final BankpopSpace space;

  /// The name the square will carry; edited in place in the review list.
  String name;

  /// True when the picture supplied this name, false when it is the one the
  /// built-in board has (the picture did not reach this square).
  final bool fromPhoto;
}

class _BoardFromImageScreenState extends State<BoardFromImageScreen> {
  final TextEditingController _boardName = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  List<_Square> _squares = <_Square>[];

  /// The photograph being read, kept only to show beside the names.
  Uint8List? _photo;

  /// The built-in board the names are applied to.
  BankpopBoard? _base;

  bool _reading = false;
  bool _saving = false;
  String? _error;

  /// 0 is the picture, 1 is the names read from it.
  int _step = 0;

  bool get _supported => BoardOcr.isSupported;

  @override
  void initState() {
    super.initState();
    // The picture has to be taken the way the board is printed - GO in the
    // bottom-right corner and Free Parking in the top-left - or every name is
    // read backwards. So the guide comes before the camera, not after a bad
    // read. A build with no reader shows its own notice instead.
    if (!_supported) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showBoardPhotoGuide(context);
    });
  }

  /// A desktop has a file picker but no camera, so the shutter is only offered
  /// where one exists; the gallery button covers the rest.
  bool get _cameraAvailable =>
      _picker.supportsImageSource(ImageSource.camera);

  @override
  void dispose() {
    _boardName.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    if (_reading) return;
    setState(() => _error = null);
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        // Big enough to read a printed square, small enough to recognise in a
        // second or two on a phone.
        maxWidth: 2600,
        imageQuality: 90,
      );
      if (file == null) return;
      final Uint8List bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _photo = bytes;
        _reading = true;
      });
      // Both are handed over: the phone reads the file, the browser has no file
      // to open and reads the bytes instead.
      await _read(path: file.path, bytes: bytes);
    } catch (error) {
      debugPrint('Could not take the board photograph: $error');
      if (!mounted) return;
      setState(() {
        _reading = false;
        _error = 'That picture could not be opened. Try another one.';
      });
    }
  }

  /// Reads the names off the picture and fills the review list.
  Future<void> _read({required String path, required Uint8List bytes}) async {
    try {
      final List<List<String>> blocks =
          await BoardOcr.readBlocks(path, bytes: bytes);
      final BankpopBoard base = _base ??= await BoardCatalog.board();
      final List<BankpopSpace> slots = BoardScan.renamable(base);
      // A board's own name is printed in the middle of the picture; read as a
      // square it would shift every card after it onto the wrong one.
      final BoardRead read = BoardScan.apply(
        blocks,
        slots,
        noise: <String>{base.boardName},
      );
      if (!mounted) return;
      setState(() {
        _reading = false;
        _squares = <_Square>[
          for (int i = 0; i < slots.length; i++)
            _Square(
              slots[i],
              read.names[i],
              fromPhoto: read.fromPhoto[i],
            ),
        ];
        _step = 1;
      });
      if (read.isEmpty) {
        await showMessage(
          context,
          'No square names came out of that picture. Try a straight-on photo '
          'with the whole board in frame, or type the names in yourself.',
          title: 'Nothing was read',
          kind: MessageKind.warning,
        );
        if (!mounted) return;
        setState(() => _step = 0);
        return;
      }
      await showMessage(
        context,
        'Read ${read.captured} of ${slots.length} names. Check them below '
        'before you save - a long name can be split, and a blurry one can '
        'come out wrong.',
        title: 'Read from your picture',
        kind: MessageKind.success,
      );
    } catch (error) {
      debugPrint('Could not read the board photograph: $error');
      if (!mounted) return;
      setState(() {
        _reading = false;
        _error = error is UnsupportedError
            ? 'This build cannot read a picture. Try the phone app or a '
                'browser, or type the names in with "Create your board".'
            : 'That picture could not be read. Try again in better light.';
        _step = 0;
      });
    }
  }

  /// The names to save, with the same rules the editor enforces: a station
  /// ends in "Station", and a colour card's name has to fit its block.
  String? _validate() {
    final String name = _boardName.text.trim();
    if (name.isEmpty) return 'Give your board a name first';
    if (name.length > BoardNames.maxLength) return 'That board name is too long';

    final Set<String> seen = <String>{
      for (final String fixed in BoardNames.fixed) fixed.toLowerCase(),
    };
    for (final _Square square in _squares) {
      final String value = _finish(square).trim();
      if (value.isEmpty) return 'Every square needs a name';
      if (value.length > _maxLength(square.space)) {
        return '"$value" is too long for that square';
      }
      if (!seen.add(value.toLowerCase())) {
        return '"$value" is used twice on this board';
      }
    }
    return null;
  }

  static bool _isColour(BankpopSpace space) =>
      space.isProperty &&
      space.color != null &&
      space.color != 'Station' &&
      space.color != 'Utility';

  static int _maxLength(BankpopSpace space) =>
      _isColour(space) ? BoardNames.colourNameMaxLength : BoardNames.maxLength;

  static String _finish(_Square square) => square.space.color == 'Station'
      ? BoardNames.finishStation(square.name)
      : square.name.trim();

  Future<void> _create() async {
    if (_saving) return;
    final String? problem = _validate();
    if (problem != null) {
      await showMessage(context, problem, kind: MessageKind.warning);
      return;
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? ownerId = prefs.getString('account_id');
    if (!mounted) return;
    if (ownerId == null || ownerId.isEmpty) {
      final bool signIn = await showAppConfirm(
        context,
        title: 'Log in to save this board',
        icon: Icons.lock_outline,
        confirmLabel: 'Sign in',
        cancelLabel: 'Not now',
        message: 'Your boards are kept on your account, so this one is there '
            'on any device you sign in on and nobody else sees it.\n\n'
            'Signing in now keeps the names you have just checked.',
      );
      if (!signIn || !mounted) return;
      await context.push<bool>(AppRoutes.authReturning);
      if (!mounted) return;
      // The names are still on this screen: signing in resumes the save.
      return _create();
    }

    setState(() => _saving = true);
    final Map<String, String> renames = <String, String>{
      for (final _Square square in _squares) square.space.name: _finish(square),
    };
    final BoardCreateResult result = await BoardCatalog.createCustom(
      name: _boardName.text.trim(),
      ownerId: ownerId,
      renames: renames,
      baseId: _base?.boardId ?? BoardCatalog.fallbackId,
    );
    if (!mounted) return;
    setState(() => _saving = false);

    if (result.ok) {
      await showMessage(
        context,
        '"${_boardName.text.trim()}" is ready. It sits in your boards, and '
        'the banker can start a game on it.',
        title: 'Board created',
        kind: MessageKind.success,
      );
      if (!mounted) return;
      context.pop<String>(result.boardId);
      return;
    }
    await showMessage(
      context,
      result.duplicateName
          ? 'You already have a board with that name. Pick another one.'
          : 'The board could not be saved. Check the connection and try again.',
      title: 'Could not save',
      kind: MessageKind.failure,
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
          'Board from a photo',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18.sp,
            color: const Color(0xFF689F38),
          ),
        ),
      ),
      body: SafeArea(child: _step == 0 ? _captureStep() : _reviewStep()),
    );
  }

  Widget _captureStep() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: <Widget>[
        Text(
          'Point at the board',
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF33691E),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Take a photo of a printed board - or pick one you already have - '
          'and BankPop reads the names on its squares. You check every name '
          'before anything is saved.',
          style: TextStyle(fontSize: 13.sp, color: Colors.black54, height: 1.4),
        ),
        const SizedBox(height: 14),
        _tip('GO bottom-right, FREE PARKING top-left - the way the board is '
            'printed, so the squares read in play order.'),
        _tip('The whole board in frame, flat and evenly lit; a steep angle cuts '
            'names short.'),
        _tip('Prices are ignored, and so are the squares that are the game\'s '
            'own: corners, Chance, Community Chest, taxes, Electric and Water.'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.lock_outline, size: 18, color: Color(0xFF33691E)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'The picture is read on this device and never uploaded. '
                  'Prices, rents and colour groups come from the game, so a '
                  'board made this way plays by the same rules as any other.',
                  style: TextStyle(fontSize: 12.sp, color: const Color(0xFF33691E)),
                ),
              ),
            ],
          ),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(fontSize: 12.5.sp, color: const Color(0xFFB71C1C)),
          ),
        ],
        const SizedBox(height: 18),
        if (!_supported)
          _unsupported()
        else if (_reading)
          _readingCard()
        else ...<Widget>[
          if (_cameraAvailable) ...<Widget>[
            ElevatedButton.icon(
              onPressed: () => _pick(ImageSource.camera),
              icon: Image.asset(
                'assets/Icons/camera.png',
                width: 22,
                height: 22,
                fit: BoxFit.contain,
              ),
              label: const Text('Take a photo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF689F38),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          OutlinedButton.icon(
            onPressed: () => _pick(ImageSource.gallery),
            icon: Image.asset(
              'assets/Icons/open_file.png',
              width: 20,
              height: 20,
              fit: BoxFit.contain,
            ),
            label: const Text('Use a picture I already have'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF33691E),
              side: const BorderSide(color: Color(0xFFAED581)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
        if (_photo != null && _reading) ...<Widget>[
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              _photo!,
              height: 160,
              fit: BoxFit.cover,
              semanticLabel: 'The board photograph being read',
            ),
          ),
        ],
      ],
    );
  }

  Widget _tip(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Icon(Icons.check_circle_outline,
                size: 15, color: Color(0xFF689F38)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12.5.sp, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _readingCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFAED581)),
      ),
      child: Column(
        children: <Widget>[
          const SizedBox(
            height: 26,
            width: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: Color(0xFF689F38),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Reading the board…',
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF33691E),
            ),
          ),
        ],
      ),
    );
  }

  Widget _unsupported() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3CD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0C068)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Not on this build',
            style: TextStyle(
              fontSize: 13.5.sp,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF8D6E00),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'This build has no picture reader. Open BankPop on your phone, in '
            'a browser or on Windows to make a board from a photo - or type '
            'the names in with "Create your board", or import one a friend '
            'sent.',
            style: TextStyle(
              fontSize: 12.5.sp,
              height: 1.4,
              color: const Color(0xFF8D6E00),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewStep() {
    final int captured =
        _squares.where((_Square square) => square.fromPhoto).length;
    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: <Widget>[
              if (_photo != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    _photo!,
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    semanticLabel: 'The board photograph that was read',
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                '$captured of ${_squares.length} names read',
                style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF558B2F),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Each name sits beside the colour group it belongs to, in board '
                'order. Correct anything the camera got wrong - a name it did '
                'not find kept the built-in one.',
                style: TextStyle(
                  fontSize: 12.sp,
                  height: 1.35,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _boardName,
                maxLength: BoardNames.maxLength,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Board name',
                  hintText: 'e.g. Our seaside board',
                  border: OutlineInputBorder(),
                  isDense: true,
                  counterText: '',
                ),
              ),
              const SizedBox(height: 14),
              for (final _Square square in _squares) _squareRow(square),
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
                  onPressed: _saving ? null : _create,
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
                      : Text('Create board', style: TextStyle(fontSize: 15.sp)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// One square: its colour group, its name, and whether the picture gave it.
  Widget _squareRow(_Square square) {
    final Color group = Color(BankpopBoard.colorForGroup(square.space.color));
    final bool known = square.space.color == 'Station' ||
        square.space.color == 'Utility';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: <Widget>[
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: group,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: Colors.black26),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              key: ValueKey<int>(square.space.index),
              initialValue: square.name,
              maxLength: _maxLength(square.space),
              textCapitalization: TextCapitalization.words,
              onChanged: (String value) => square.name = value,
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                labelText: known ? square.space.color : null,
                border: const OutlineInputBorder(),
                suffixIcon: Icon(
                  square.fromPhoto ? Icons.photo_camera_outlined : Icons.style,
                  size: 18,
                  color: square.fromPhoto
                      ? const Color(0xFF689F38)
                      : Colors.black26,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
