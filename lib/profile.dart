import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mon/pages/auth/auth_screen.dart';
import 'package:mon/pages/home.dart';
import 'package:mon/pages/profile_edit.dart';
import 'package:mon/services/account.dart';
import 'package:mon/services/profile_avatar.dart';
import 'package:mon/widgets/app_message.dart';
import 'package:mon/widgets/how_to_play_dialog.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  /// The bundled asset this device picked. A path in the bundle works on every
  /// platform we ship; the old `dart:io` file copy did not exist on the web.
  String _avatarAsset = ProfileAvatar.appIcon;
  String _appVersion = "Loading...";
  String _userName = "Player Name";
  String? _accountEmail;
  bool _isEditing = false;
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    load();
  }

  Future<void> load() async {
    await _loadAvatar();
    await _loadAppVersion();
    await _loadUserName();
    final String? email = await Account.signedInEmail();
    if (!mounted) return;
    setState(() => _accountEmail = email);
  }

  Future<void> _signOut() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Your games stay linked to this account. Sign in again on any device '
          'to see them.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await Account.signOut();
    if (!mounted) return;
    // Signing out drops back to a guest on this device, not back to the
    // introduction: the local player and its games are still here.
    setState(() => _accountEmail = null);
    showMessage(context, 'Signed out. Playing as a guest on this device.');
  }

  /// Opens the same sign-in screen the first run offers, but comes back here on
  /// success so the name, avatar and games reload in place.
  Future<void> _signIn() async {
    final bool? signedIn = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => const AuthScreen(returnOnSuccess: true),
      ),
    );
    if (signedIn != true || !mounted) return;
    await load();
  }

  Future<void> _loadUserName() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('profile_name') ?? "Your Name";
    });
  }

  Future<void> _saveUserName() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final String name = _controller.text.trim();
    await prefs.setString('profile_name', name);
    await Account.updateProfile(name: name);
    setState(() {
      _userName = name;
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

  Future<void> _loadAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _avatarAsset = ProfileAvatar.saved(prefs));
  }

  void _contactSupport() async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'mkashif.ahmed10@gmail.com',
      query: 'subject=Bug Report or Help',
    );

    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    } else if (context.mounted) {
      showMessage(context, 'Unable to open email app.');
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

  Future<bool> _onWillPop(BuildContext context) async {
    // Navigating home replaces this route, so the default pop is suppressed.
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const WelcomePage()),
    );
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      // _onWillPop navigates itself and always reports that it handled it.
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        await _onWillPop(context);
      },
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
                      // Drawn at radius 60, so decode whatever the source is
                      // (the packaged icon is 736x736) down to 360px.
                      backgroundImage: ProfileAvatar.provider(
                        _avatarAsset,
                        cacheWidth: 360,
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 4,
                      child: InkWell(
                        onTap: () async {
                          final prefs = await SharedPreferences.getInstance();
                          final int? avatarIndex =
                              prefs.getInt("selected_avatar_index");

                          //await _pickAndCropImage();
                          // Add a small bounce animation or ripple effect here if you want
                          await showDialog(
                            context: context,
                            builder: (context) => ProfileDialog(
                              first: false,
                              // Nothing saved yet on a first open.
                              prevIndex: avatarIndex ?? 0,
                            ),
                          );

                          //  if (updated == true) {
                          await load();

                          // Reload UI after changes
                          setState(() {});
                          // }
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
                                color: Colors.green.withValues(alpha: 0.4),
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

              // The account. This is the thing that keeps the games attached
              // to a person rather than to a device.
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                color: const Color(0xFFE8F5E9),
                elevation: 2,
                child: ListTile(
                  leading: Icon(
                    _accountEmail == null
                        ? Icons.person_outline
                        : Icons.alternate_email,
                    color: const Color(0xFF689F38),
                  ),
                  title: Text(
                    _accountEmail == null ? 'Playing as a guest' : 'Account',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    _accountEmail ??
                        'Your games live on this device only. Sign in to keep '
                            'them across devices and reinstalls.',
                  ),
                  trailing: TextButton(
                    onPressed: _accountEmail == null ? _signIn : _signOut,
                    child: Text(
                      _accountEmail == null ? 'Sign in' : 'Sign out',
                      style: const TextStyle(color: Color(0xFF2E7D32)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

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

              // How to Play card: opens the same guide the home screen offers,
              // so the two entry points cannot disagree about how the game
              // works now (cards, houses, badges, removing a player).
              GestureDetector(
                onTap: () => HowToPlayGuide.show(context),
                child: Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  color: const Color(0xFFC8E6C9), // pale mint green
                  elevation: 3,
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          "How to Play",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2E7D32), // deep green
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          "Joining, paying, cards and houses, pausing a game, "
                          "and what the badges beside a name mean - a short "
                          "guide for players and for the banker.",
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF388E3C), // medium green
                          ),
                        ),
                        SizedBox(height: 6),
                        Align(
                          alignment: Alignment.bottomRight,
                          child: Text(
                            "Tap to know more",
                            style: TextStyle(
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
                      showMessage(context, 'Checking for updates...');
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
