import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:mon/pages/home.dart';
import 'package:mon/pages/profile_edit.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'theme_provider.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  File? _profileImage;
  String _appVersion = "Loading...";
  String _userName = "Player Name";
  bool _isEditing = false;
  bool showHelp = false;
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    load();
  }

  Future<void> load() async {
    await _loadProfileImage();
    await _loadAppVersion();
    await _loadUserName();
  }

  Future<void> _loadUserName() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('profile_name') ?? "Your Name";
    });
  }

  Future<void> _saveUserName() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_name', _controller.text);
    setState(() {
      _userName = _controller.text;
      _isEditing = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadAppVersion() async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _appVersion = "${packageInfo.version} (${packageInfo.buildNumber})";
    });
  }

  Future<void> _loadProfileImage() async {
    final prefs = await SharedPreferences.getInstance();
    String? path = prefs.getString('profile_image');
    if (path != null && File(path).existsSync()) {
      setState(() => _profileImage = File(path));
    }
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
        setState(() => _profileImage = File(cropped.path));
      }
    }
  }

  void _contactSupport() async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'mkashif.ahmed10@gmail.com',
      query: 'subject=Bug Report or Help',
    );

    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Unable to open email app.")),
      );
    }
  }

  bool _isExpanded = false;

  final String aboutPreviewText =
      "Welcome to BankPop – Bye-Bye Paper Money, Hello Game Night Magic!\n\n"
      "No more crumpled bills, missing coins, or “Wait, who’s the banker?” moments!... ";

  final String aboutFullText =
      "\n\nWith BankPop, your board games just got a major upgrade. We’ve turned game money into easy-peasy, tap-and-go fun — right on your phone or tablet!\n\n"
      "Whether you're buying a theme park, collecting rent from your siblings, or making a million-dollar deal (in-game, of course 😄), BankPop keeps the action fast, fair, and way more fun.\n\n"
      "Made for families, kids, and anyone who loves game night without the money mess!";

  Widget roleContent({
    required String role,
    required List<String> scanPayPoints,
    required List<String> instantPayPoints,
  }) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "ScanPay",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Color(0xFFF57F17), // calm green
            ),
          ),
          const SizedBox(height: 8),
          ...scanPayPoints.map(bullet),
          const SizedBox(height: 16),
          const Text(
            "InstantPay",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Color(0xFFF57F17), // darker green
            ),
          ),
          const SizedBox(height: 8),
          ...instantPayPoints.map(bullet),
        ],
      ),
    );
  }

  Widget bullet(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "•  ",
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFF827717), // deep green bullet
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF827717), // main text green
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _onWillPop(BuildContext context) async {
    // Perform any logic you need here before popping.
    // In this case, navigate to the WelcomePage using pushReplacement.
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const WelcomePage()),
    );

    // Returning false to prevent the default pop behavior, as we've already handled the navigation.
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    ThemeMode currentMode = themeProvider.themeMode;

    return WillPopScope(
      onWillPop: () => _onWillPop(context),
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const WelcomePage()),
                );
              },
              icon: Icon(
                CupertinoIcons.chevron_back,
                size: 22.sp,
                color: Colors.white,
              )),
          title: const Text(
            "Profile",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 1.1,
            ),
          ),
          backgroundColor: const Color(0xFF689F38), // fresh green
          elevation: 0,
        ),
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            setState(() {
              _isEditing = false;
              _isExpanded = false;
              showHelp = false;
            });
            FocusScope.of(context).unfocus();
          },
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundColor: const Color(
                          0xFFC8E6C9), // pale mint green bg for subtle pop
                      backgroundImage: _profileImage != null
                          ? FileImage(_profileImage!)
                          : const AssetImage('assets/images/play_icon.jpg')
                              as ImageProvider,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 4,
                      child: InkWell(
                        onTap: () async {
                          //await _pickAndCropImage();
                          // Add a small bounce animation or ripple effect here if you want
                          bool? updated = await showDialog(
                            context: context,
                            builder: (context) => const ProfileDialog(
                              first: false,
                            ),
                          );

                          if (updated == true) {
                            await load();

                            // Reload UI after changes
                            setState(() {});
                          }
                        },
                        borderRadius: BorderRadius.circular(30),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF8BC34A),
                                Color(0xFF689F38)
                              ], // lively green gradient
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.green.withOpacity(0.4),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.edit,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: _isEditing
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 220,
                            child: TextField(
                              controller: _controller..text = _userName,
                              autofocus: true,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w600),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: const Color(0xFFE8F5E9),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                              ),
                              onSubmitted: (_) => _saveUserName(),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.check,
                                color: Color(0xFF689F38)),
                            onPressed: _saveUserName,
                            tooltip: "Save",
                          ),
                        ],
                      )
                    : GestureDetector(
                        onTap: () {
                          /* setState(() {
                            _isEditing = true;
                          }); */
                        },
                        child: Text(
                          _userName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF33691E), // dark green
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 30),

              // Theme selection card
              /* Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                color: const Color(0xFFF1F8E9), // soft light green
                elevation: 3,
                child: ListTile(
                  title: const Text(
                    "Theme",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text("Choose how the app looks"),
                  trailing: DropdownButton<ThemeMode>(
                    value: currentMode,
                    dropdownColor: const Color(0xFFF1F8E9),
                    items: const [
                      DropdownMenuItem(
                        value: ThemeMode.system,
                        child: Text("System Default"),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.light,
                        child: Text("Light"),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.dark,
                        child: Text("Dark"),
                      ),
                    ],
                    onChanged: (mode) {
                      if (mode != null) {
                        themeProvider.setThemeMode(mode);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20), */

              // About the Game card
              GestureDetector(
                onTap: () {
                  setState(() {
                    _isExpanded = !_isExpanded;
                  });
                },
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  color: const Color(0xFFFFF9C4),
                  elevation: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "About the Game",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFF57F17),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isExpanded
                              ? aboutPreviewText + aboutFullText
                              : aboutPreviewText,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF827717),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _isExpanded = !_isExpanded;
                            });
                          },
                          child: Align(
                            alignment: Alignment.bottomRight,
                            child: Text(
                              _isExpanded ? "Read less" : "Read more",
                              style: const TextStyle(
                                color: Color(0xFFF57F17), // same as title color
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // How to Play card
              GestureDetector(
                onTap: () {
                  setState(() {
                    showHelp = !showHelp;
                  });
                },
                child: Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  color: const Color(0xFFC8E6C9), // pale mint green
                  elevation: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "How to Play",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2E7D32), // deep green
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (!showHelp)
                          const Text(
                            "Tap to start a new game, manage your in-game money easily, and enjoy the seamless experience without any mess. Just follow the intuitive prompts and have fun!",
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF388E3C), // medium green
                            ),
                          ),
                        if (showHelp)
                          SizedBox(
                            width: double.maxFinite,
                            child: DefaultTabController(
                              length: 2,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const TabBar(
                                    labelColor: Color(0xFF33691E),
                                    unselectedLabelColor: Colors.grey,
                                    indicatorColor: Color(0xFF689F38),
                                    tabs: [
                                      Tab(text: "Player"),
                                      Tab(text: "Banker"),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    height: 50.h,
                                    child: TabBarView(
                                      children: [
                                        // Player tab
                                        roleContent(
                                          role: "Player",
                                          scanPayPoints: [
                                            "Join a game hosted by the banker.",
                                            "Manage your in-game balance digitally.",
                                            "Tap to pay rent, buy property, or collect income.",
                                            "Use the app instead of paper money or cards.",
                                            "Keep an eye on your balance and transactions.",
                                          ],
                                          instantPayPoints: [
                                            "Join a game instantly without scanning.",
                                            "Manage your in-game balance digitally.",
                                            "Tap to pay rent, buy property, or collect income.",
                                            "Use the app instead of paper money or cards.",
                                            "Monitor your balance at all times.",
                                          ],
                                        ),
                                        // Banker tab
                                        roleContent(
                                          role: "Banker",
                                          scanPayPoints: [
                                            "Start a new game and assign starting balances.",
                                            "Oversee all player transactions digitally.",
                                            "Adjust balances manually if needed.",
                                            "Ensure fair play and assist players.",
                                            "End the game when a winner is declared.",
                                          ],
                                          instantPayPoints: [
                                            "Quickly start a game without scanning.",
                                            "Oversee all player transactions digitally.",
                                            "Adjust balances manually if needed.",
                                            "Ensure fair play and assist players.",
                                            "End the game when a winner is declared.",
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        Align(
                          alignment: Alignment.bottomRight,
                          child: Text(
                            showHelp ? "Tap to close" : "Tap to know more",
                            style: const TextStyle(
                              color: Color(0xFF2E7D32),
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Version and update check card
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                color: const Color(0xFFF1F8E9),
                elevation: 3,
                child: ListTile(
                  title: const Text(
                    "App Version",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(_appVersion),
                  trailing: TextButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text("Checking for updates...")),
                      );
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFF8BC34A),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      "Check Update",
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Contact & Report Bugs card
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                color: const Color(0xFFFFF3E0), // soft peach background
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Contact & Report Bugs",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFEF6C00), // bright orange/coral
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Found a bug or need help? We'd love to hear from you! Tap the button below to get in touch with our support team.",
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF6D4C41), // soft brown
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            _contactSupport();
                            // You can launch email or open a contact form here
                            // Example using url_launcher:
                            // launchUrl(Uri.parse("mailto:support@yourapp.com"));
                            /*  ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text("Opening contact support...")),
                            ); */
                          },
                          icon: const Icon(Icons.bug_report_outlined),
                          label: const Text("Contact Us"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                const Color(0xFFFFA726), // vibrant coral-orange
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
