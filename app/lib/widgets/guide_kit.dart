import 'package:flutter/material.dart';
import 'package:mon/widgets/game_controls.dart';

/// The pieces the two guide screens ("How to use" and "Game rules") are built
/// from.
///
/// Both pages used to be one long run of paragraphs, one card after another,
/// which is the shape nobody reads: a new player could not tell where to start
/// or which sentence mattered. These widgets give the pages landmarks - a
/// numbered step, a short strip that says where to begin, a tip that is visibly
/// not part of the instructions, and the real buttons drawn beside the words
/// that describe them.
abstract final class GuideStyle {
  static const Color paper = Color(0xFFFFF8E1);
  static const Color card = Color(0xFFFFFFFF);
  static const Color ink = Color(0xFF33691E);
  static const Color body = Color(0xFF4E5A3A);
  static const Color muted = Color(0xFF6B7A57);
  static const Color green = Color(0xFF689F38);
  static const Color greenDeep = Color(0xFF2E7D32);
  static const Color soft = Color(0xFFF1F8E9);
  static const Color amber = Color(0xFFF9A825);
  static const Color amberInk = Color(0xFF827717);
  static const Color amberCard = Color(0xFFFFF9C4);
  static const Color line = Color(0xFFE3E8D3);
}

/// The heading of a guide page: what this page is for, in one sentence, with
/// the handful of concepts it covers as chips.
class GuideHero extends StatelessWidget {
  const GuideHero({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.chips = const <String>[],
    this.tint = GuideStyle.green,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> chips;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: GuideStyle.soft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tint.withValues(alpha: 0.35), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: tint),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16.5,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    color: GuideStyle.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: GuideStyle.body,
            ),
          ),
          if (chips.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final String chip in chips)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: GuideStyle.line),
                    ),
                    child: Text(
                      chip,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: GuideStyle.ink,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One stop on the quick-start strip: a number, a word, and what to do there.
class GuideStop {
  const GuideStop({
    required this.icon,
    required this.label,
    required this.detail,
  });

  final IconData icon;
  final String label;
  final String detail;
}

/// "Start here": the three or four things to do first, in order, as one strip.
///
/// It scrolls sideways rather than wrapping, so it stays a single line of
/// thought on a narrow phone and can be swiped through with a thumb.
class GuideQuickStart extends StatelessWidget {
  const GuideQuickStart({super.key, required this.stops});

  final List<GuideStop> stops;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Row(
          children: <Widget>[
            Icon(Icons.bolt, size: 18, color: GuideStyle.amber),
            SizedBox(width: 6),
            Text(
              'Start here',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: GuideStyle.amberInk,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(bottom: 4),
          // Inside a horizontal viewport the height is unbounded, so the cards
          // cannot simply be stretched to one another's height: IntrinsicHeight
          // measures them first and hands the row a finite one.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (int i = 0; i < stops.length; i++) ...<Widget>[
                  _StopCard(number: i + 1, stop: stops[i]),
                  if (i != stops.length - 1)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Center(
                        child: Icon(
                          Icons.arrow_forward,
                          size: 16,
                          color: GuideStyle.amber,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StopCard extends StatelessWidget {
  const _StopCard({required this.number, required this.stop});

  final int number;
  final GuideStop stop;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 148,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: GuideStyle.amberCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GuideStyle.amber.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: GuideStyle.amber,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$number',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(stop.icon, size: 16, color: GuideStyle.amberInk),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            stop.label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: GuideStyle.amberInk,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            stop.detail,
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.3,
              color: Color(0xFF8D6E00),
            ),
          ),
        ],
      ),
    );
  }
}

/// A numbered section: the badge, the heading, and the things to know, each on
/// its own line so one can be found without reading the rest.
class GuideCard extends StatelessWidget {
  const GuideCard({
    super.key,
    required this.number,
    required this.title,
    required this.lines,
    this.icon,
    this.tag,
    this.tagColor = GuideStyle.greenDeep,
    this.footer,
  });

  /// Where this sits in the page's order. The numbers are what let a reader
  /// jump back to "the third card" instead of hunting for a heading.
  final int number;
  final String title;
  final List<String> lines;
  final IconData? icon;

  /// A short label above the heading, e.g. "the app enforces this" or "agree at
  /// the table".
  final String? tag;
  final Color tagColor;

  /// A last line set apart from the rest, for the one thing to remember.
  final String? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      decoration: BoxDecoration(
        color: GuideStyle.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: GuideStyle.line),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.brown.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: GuideStyle.green,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  '$number',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (tag != null) ...<Widget>[
                      Text(
                        tag!.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9.5,
                          letterSpacing: 0.6,
                          fontWeight: FontWeight.w800,
                          color: tagColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    Row(
                      children: <Widget>[
                        if (icon != null) ...<Widget>[
                          Icon(icon, size: 16, color: GuideStyle.green),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 15,
                              height: 1.2,
                              fontWeight: FontWeight.w800,
                              color: GuideStyle.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final String line in lines) _Point(text: line),
          if (footer != null) ...<Widget>[
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: GuideStyle.soft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                footer!,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: GuideStyle.ink,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One line inside a card, with a dot in the margin so a list of three reads as
/// three things rather than a paragraph.
class _Point extends StatelessWidget {
  const _Point({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 36, bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            margin: const EdgeInsets.only(top: 6, right: 7),
            width: 4,
            height: 4,
            decoration: const BoxDecoration(
              color: GuideStyle.green,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.8,
                height: 1.38,
                color: GuideStyle.body,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A tip or a warning: deliberately not the same shape as the instructions, so
/// it is read as an aside.
class GuideCallout extends StatelessWidget {
  const GuideCallout({
    super.key,
    required this.text,
    this.icon = Icons.lightbulb_outline,
    this.warning = false,
  });

  final String text;
  final IconData icon;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final Color tint = warning ? const Color(0xFFEF6C00) : GuideStyle.greenDeep;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: warning ? const Color(0xFFFFF3E0) : GuideStyle.soft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tint.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 16, color: tint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.3,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: warning ? const Color(0xFF8A4B00) : GuideStyle.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A heading for a run of things that are not numbered steps, e.g. the buttons.
class GuideHeading extends StatelessWidget {
  const GuideHeading({super.key, required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Row(
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 17, color: GuideStyle.green),
            const SizedBox(width: 7),
          ],
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: GuideStyle.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A real button from the game screen, drawn beside the sentence that explains
/// it: the picture a player has to recognise, and the words to recognise it by.
class GuideButtonRow extends StatelessWidget {
  const GuideButtonRow({super.key, required this.control, this.line});

  final GameControl control;

  /// The explanation. Defaults to the control's own, so a button and its
  /// documentation cannot drift apart.
  final String? line;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: GuideStyle.paper,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: GuideStyle.line),
            ),
            child: control.art == null
                ? Icon(control.icon, size: 19, color: control.color)
                : Padding(
                    padding: const EdgeInsets.all(4),
                    child: Image.asset(control.art!, fit: BoxFit.contain),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  control.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: GuideStyle.ink,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  line ?? control.detail,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.32,
                    color: GuideStyle.body,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The note at the foot of a page, for the caveat that belongs to everything
/// above it.
class GuideFootnote extends StatelessWidget {
  const GuideFootnote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11.5,
          height: 1.4,
          fontStyle: FontStyle.italic,
          color: GuideStyle.muted,
        ),
      ),
    );
  }
}
