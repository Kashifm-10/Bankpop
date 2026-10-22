import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mon/services/account.dart';
import 'package:mon/services/profile_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileDialog extends StatefulWidget {
  final bool first;
  final int prevIndex;
  const ProfileDialog(
      {super.key, required this.first, required this.prevIndex});

  @override
  State<ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<ProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();

  /// The bundled asset this player picked, or null before any pick.
  String? _avatarAsset;
  int _selectedAvatarIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? avatar = prefs.getString('avatar_path');
    final int? avatarIndex = prefs.getInt('selected_avatar_index');
    if (!mounted) return;
    setState(() {
      _nameController.text = prefs.getString('profile_name') ?? '';
      // No saved avatar is not the same as "no avatar chosen". The sheet draws
      // a tick on the first avatar either way, so the first avatar has to be
      // the real selection - otherwise Save stored nothing and the player was
      // left with the app icon after a dialog that said an avatar was picked.
      final bool hasAvatar = avatar != null && avatar.isNotEmpty;
      final int fallback = (widget.prevIndex >= 0 &&
              widget.prevIndex < ProfileAvatar.choices.length)
          ? widget.prevIndex
          : 0;
      _avatarAsset = hasAvatar ? avatar : ProfileAvatar.choices[fallback];
      _selectedAvatarIndex = hasAvatar
          ? (avatarIndex ?? ProfileAvatar.choices.indexOf(avatar))
          : fallback;
    });
  }

  /// Remembers the pick locally; nothing is written until Save, so Cancel
  /// really cancels. The asset itself is drawn straight from the bundle, which
  /// is why this works on the web too.
  void _selectAvatar(String assetPath, int index) {
    setState(() {
      _avatarAsset = assetPath;
      _selectedAvatarIndex = index;
    });
    // A tap is a decent haptic on a phone; on the web it is a no-op.
    HapticFeedback.selectionClick();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    final prefs = await SharedPreferences.getInstance();
    final String name = _nameController.text.trim();
    if (name.isNotEmpty) {
      await prefs.setString('profile_name', name);
    }
    final String? avatar = _avatarAsset;
    if (avatar != null) {
      await ProfileAvatar.save(
        prefs,
        asset: avatar,
        index: _selectedAvatarIndex,
      );
    }
    // The account row is what follows the player to a new device, so the same
    // edit has to reach it, not just this device's prefs.
    await Account.updateProfile(name: name, avatar: avatar);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor:
          const Color(0xFFFFF8E1), // soft light green like body cards
      title: const Text(
        "Edit Profile",
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Color(0xFF33691E), // deep green for title
          letterSpacing: 1.1,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundImage: _avatarAsset == null
                  ? null
                  : ProfileAvatar.provider(_avatarAsset!, cacheWidth: 240),
              backgroundColor: const Color(0xFFC8E6C9), // pale mint green
              child: _avatarAsset == null
                  ? const Icon(Icons.camera_alt,
                      size: 30, color: Color(0xFF689F38))
                  : null,
            ),
            const SizedBox(height: 10),
            Form(
              key: _formKey,
              child: TextFormField(
                controller: _nameController,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Name cannot be empty';
                  }

                  if (value.contains(' ')) {
                    return 'Name cannot contain spaces';
                  }

                  if (value.length < 2) {
                    return 'Name must be at least 2 characters';
                  }

                  if (value.length > 10) {
                    return 'Name must be at most 10 characters';
                  }

                  final nameRegExp = RegExp(r'^[a-zA-Z0-9\-_@]+$');
                  if (!nameRegExp.hasMatch(value)) {
                    return 'Name can only contain letters and \nhyphens';
                  }

                  return null; // ✅ Passed all checks
                },
                decoration: InputDecoration(
                  labelText: "Name",
                  labelStyle: const TextStyle(color: Color(0xFF2E7D32)),
                  filled: true,
                  fillColor: const Color(0xFFE8F5E9),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF689F38)),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: List.generate(
                ProfileAvatar.choices.length,
                (index) {
                  final bool isSelected = _selectedAvatarIndex == index;
                  return GestureDetector(
                    onTap: () => _selectAvatar(
                      ProfileAvatar.choices[index],
                      index,
                    ),
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 25,
                          // The 14 avatars are on screen at once and the
                          // sources are 520-1200 px square, for a 50 px
                          // circle. Decoding at 144px keeps this sheet's
                          // bitmap memory around 1 MB instead of ~40 MB.
                          backgroundImage: ProfileAvatar.provider(
                            ProfileAvatar.choices[index],
                            cacheWidth: 144,
                          ),
                          backgroundColor: Colors.grey[200],
                        ),
                        if (isSelected)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF689F38),
                                  width: 3,
                                ),
                              ),
                            ),
                          ),
                        if (isSelected)
                          const Positioned(
                            top: 0,
                            right: 0,
                            child: CircleAvatar(
                              radius: 10,
                              backgroundColor: Color(0xFF689F38),
                              child: Icon(Icons.check,
                                  size: 14, color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (!widget.first)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "Cancel",
              style: TextStyle(color: Color(0xFF689F38)),
            ),
          ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF689F38),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: _saveProfile,
          child: const Text("Save"),
        ),
      ],
    );
  }
}
