import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

class ProfileDialog extends StatefulWidget {
  final bool first;
  const ProfileDialog({super.key, required this.first});

  @override
  State<ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<ProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  File? _profileImage;
  int? _selectedAvatarIndex;

  final List<String> avatarPaths = [
    'assets/avatars/girl1.jpg',
    'assets/avatars/girl2.jpg',
    'assets/avatars/girl3.jpg',
    'assets/avatars/girl4.jpg',
    'assets/avatars/girl5.jpg',
    'assets/avatars/girl6.jpg',
    'assets/avatars/girl7.jpg',
    'assets/avatars/boy1.jpg',
    'assets/avatars/boy2.jpg',
    'assets/avatars/boy3.jpg',
    'assets/avatars/boy4.jpg',
    'assets/avatars/boy5.jpg',
    'assets/avatars/boy6.jpg',
    'assets/avatars/boy7.jpg',
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    _nameController.text = prefs.getString('profile_name') ?? '';

    String? path = prefs.getString("profile_image");
    if (path != null && File(path).existsSync()) {
      setState(() => _profileImage = File(path));
    }

    _selectedAvatarIndex = prefs.getInt("selected_avatar_index");
  }

  Future<void> _pickAndCropImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      final cropped = await ImageCropper().cropImage(
        sourcePath: pickedFile.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        compressQuality: 90,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Image',
            toolbarColor: Colors.deepPurple,
            toolbarWidgetColor: Colors.white,
          ),
          IOSUiSettings(title: 'Crop Image'),
        ],
      );

      if (cropped != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString("profile_image", cropped.path);
        setState(() {
          _profileImage = File(cropped.path);
          _selectedAvatarIndex = null; // Clear avatar selection
        });
      }
    }
  }

  Future<void> _selectAvatarFromAssets(String assetPath, int index) async {
    final byteData = await rootBundle.load(assetPath);
    final Uint8List bytes = byteData.buffer.asUint8List();

    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/profile_avatar_$index.png';
    final file = File(filePath);

    // Remove old profile image file if needed
    if (await file.exists()) {
      await file.delete();
    }

    // Save selected avatar to file
    await file.writeAsBytes(bytes);

    // Save the selected avatar file path to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("profile_image", file.path);
    await prefs.setInt("selected_avatar_index", index); // optional

    setState(() {
      _selectedAvatarIndex = index;
      _profileImage = file;
    });
  }

  Future<void> _saveProfile() async {
    if (_formKey.currentState!.validate()) {
      final prefs = await SharedPreferences.getInstance();
      if (_nameController.text.isNotEmpty) {
        await prefs.setString('profile_name', _nameController.text);
      }
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor:
          const Color(0xFFF1F8E9), // soft light green like body cards
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
          children: [
            GestureDetector(
              onTap: _pickAndCropImage,
              child: CircleAvatar(
                radius: 40,
                backgroundImage:
                    _profileImage != null ? FileImage(_profileImage!) : null,
                backgroundColor: const Color(0xFFC8E6C9), // pale mint green
                child: _profileImage == null
                    ? const Icon(Icons.camera_alt,
                        size: 30, color: Color(0xFF689F38))
                    : null,
              ),
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
              children: List.generate(
                avatarPaths.length,
                (index) {
                  final isSelected = _selectedAvatarIndex == index;
                  return GestureDetector(
                    onTap: () async {
                      await _selectAvatarFromAssets(avatarPaths[index], index);
                    },
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 25,
                          backgroundImage: AssetImage(avatarPaths[index]),
                          backgroundColor: Colors.grey[200],
                        ),
                        if (isSelected)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color:
                                      const Color(0xFF689F38), // green border
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
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.image),
              label: const Text("Pick Custom Image"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF689F38),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _pickAndCropImage,
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
