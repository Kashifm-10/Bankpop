import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mon/services/board_download.dart';
import 'package:mon/services/board_share.dart';
import 'package:mon/widgets/app_metrics.dart';

/// Bringing a board in: paste the JSON a friend sent, or pick the file they
/// sent it as. Either way the text goes through [BoardShare.decode], and a
/// document that is refused says why without leaving the sheet.
///
/// Returns the draft to open the editor on, or null if the player backed out.
Future<BoardDraft?> showBoardImportSheet(BuildContext context) {
  return showModalBottomSheet<BoardDraft>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFFFFF8E1),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _ImportBoardSheet(),
  );
}

class _ImportBoardSheet extends StatefulWidget {
  const _ImportBoardSheet();

  @override
  State<_ImportBoardSheet> createState() => _ImportBoardSheetState();
}

class _ImportBoardSheetState extends State<_ImportBoardSheet> {
  final TextEditingController _controller = TextEditingController();
  String? _error;
  bool _reading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Takes whatever text is in the field, or [text] when a file was just
  /// picked, and hands the draft back to the screen that opened this sheet.
  void _submit(String text) {
    try {
      final BoardDraft draft = BoardShare.decode(text);
      Navigator.of(context).pop(draft);
    } on BoardImportFailure catch (failure) {
      setState(() => _error = failure.message);
    }
  }

  Future<void> _pickFile() async {
    setState(() {
      _reading = true;
      _error = null;
    });
    try {
      final FilePickerResult? result = await FilePicker.pickFiles(
        dialogTitle: 'Choose a board file',
        type: FileType.custom,
        allowedExtensions: <String>['json'],
        withData: true,
      );
      final PlatformFile? file =
          (result == null || result.files.isEmpty) ? null : result.files.first;
      if (file == null) {
        if (mounted) setState(() => _reading = false);
        return;
      }
      final Uint8List? bytes = file.bytes;
      if (bytes == null) {
        if (!mounted) return;
        setState(() {
          _reading = false;
          _error = 'That file could not be read. Try the paste option.';
        });
        return;
      }
      final String text = utf8.decode(bytes, allowMalformed: true);
      if (!mounted) return;
      setState(() => _reading = false);
      _submit(text);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _reading = false;
        _error = 'That file could not be opened. Try the paste option.';
      });
    }
  }

  Future<void> _paste() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final String text = data?.text ?? '';
    if (text.isEmpty) {
      setState(() => _error = 'There is nothing on the clipboard to paste.');
      return;
    }
    setState(() {
      _controller.text = text;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Import a board',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF33691E),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Paste the board your friend sent, or choose the .json file. '
              'You will see every space before anything is saved, and only '
              'names can be changed.',
              style: TextStyle(fontSize: 12.5.sp, color: Colors.black54),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F8E9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFC5E1A5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'A shared board is a list of { "index", "name" } - the '
                        'card number and its name, nothing else:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF33691E),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    BoardShare.sample,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      height: 1.35,
                      color: Color(0xFF4A5A3A),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _controller,
              minLines: 4,
              maxLines: 8,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: InputDecoration(
                hintText: '{\n  "format": "bankpop-board",\n  ...\n}',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(Icons.error_outline,
                      size: 16, color: Colors.redAccent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                          fontSize: 12.5, color: Colors.redAccent),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _reading ? null : _paste,
                    icon: Image.asset(
                      'assets/Icons/paste.png',
                      width: 20,
                      height: 20,
                      fit: BoxFit.contain,
                    ),
                    label: const Text('Paste'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF33691E),
                      side: const BorderSide(color: Color(0xFFAED581)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _reading ? null : _pickFile,
                    icon: Image.asset(
                      'assets/Icons/open_file.png',
                      width: 20,
                      height: 20,
                      fit: BoxFit.contain,
                    ),
                    label: Text(_reading ? 'Opening…' : 'Choose file'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF33691E),
                      side: const BorderSide(color: Color(0xFFAED581)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () => _submit(_controller.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF689F38),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text('Use this board', style: TextStyle(fontSize: 15.sp)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sending a board out: the JSON on the clipboard, ready to paste into any
/// chat, or the same JSON as a .json file through the share sheet. On the web,
/// where there is no share sheet for files, the browser downloads it instead.
Future<void> showBoardShareSheet(
  BuildContext context, {
  required String boardName,
  required String json,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFFFFF8E1),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (BuildContext sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Share "$boardName"',
              style: TextStyle(
                fontSize: 17.sp,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF33691E),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Your friend opens Boards & cards, taps Import and pastes the '
              'JSON or chooses the file. Only the names travel - they can '
              'rename anything before saving it as their own.',
              style: TextStyle(fontSize: 12.5.sp, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            _ShareAction(
              icon: Icons.content_copy,
              title: 'Copy JSON',
              subtitle: 'Paste it into any chat',
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: json));
                if (!sheetContext.mounted) return;
                Navigator.of(sheetContext).pop();
                _tell(context, 'Board JSON copied');
              },
            ),
            const SizedBox(height: 10),
            _ShareAction(
              icon: Icons.file_download_outlined,
              title: 'Save as file',
              subtitle: 'Puts ${BoardShare.fileName(boardName)} in your '
                  'downloads',
              onTap: () async {
                try {
                  await BoardDownload.json(
                    json,
                    BoardShare.fileName(boardName),
                  );
                  if (!sheetContext.mounted) return;
                  Navigator.of(sheetContext).pop();
                  _tell(context, 'Board file saved');
                } catch (error) {
                  if (!sheetContext.mounted) return;
                  _tell(context, 'Could not save the file');
                }
              },
            ),
          ],
        ),
      ),
    ),
  );
}

void _tell(BuildContext context, String message) {
  final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF33691E),
    ),
  );
}

class _ShareAction extends StatelessWidget {
  const _ShareAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 22, color: const Color(0xFF2E7D32)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14.5.sp,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF33691E),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12.sp, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}
