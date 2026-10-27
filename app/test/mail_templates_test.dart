// The two mails are what a person sees before they can play: a wasted
// verification mail is an account nobody can use, and a reset mail that hides
// its password is an account nobody can recover. These pin the parts that must
// survive any rewrite of the markup: the link, the password, the sender's name
// and a plain-text version that carries both.

import 'package:flutter_test/flutter_test.dart';
import 'package:mon/services/mail_templates.dart';

void main() {
  group('the verification mail', () {
    const String link = 'https://bankpop.example/verify?token=abc123';
    const String appUrl = 'https://bankpop.example';

    test('carries the link in the button and again as text', () {
      final String html =
          MailTemplates.verificationHtml(actionUrl: link, appUrl: appUrl);

      expect(html, contains('Verify Your Account'));
      // The button, and the "paste this address" fallback beneath it, which
      // shows the link as text for a client that will not make it clickable.
      expect(html, contains('<a href="$link"'));
      expect(html, contains('>$link</a>'));
    });

    test('links the mark to the app', () {
      final String html =
          MailTemplates.verificationHtml(actionUrl: link, appUrl: appUrl);

      expect(html, contains('alt="BankPop Logo"'));
      expect(html, contains('<a href="$appUrl"'));
    });

    test('leaves the mark unlinked when the app has no public address', () {
      final String html =
          MailTemplates.verificationHtml(actionUrl: link, appUrl: '');

      expect(html, contains('alt="BankPop Logo"'));
      expect(html, isNot(contains('<a href=""')));
    });

    test('escapes a link that would end its attribute early', () {
      final String html = MailTemplates.verificationHtml(
        actionUrl: 'https://bankpop.example/verify?token=a&b="c',
        appUrl: appUrl,
      );

      expect(html, contains('token=a&amp;b=&quot;c'));
      expect(html, isNot(contains('token=a&b="c')));
    });

    test('says who to write to and from whom', () {
      final String html =
          MailTemplates.verificationHtml(actionUrl: link, appUrl: appUrl);

      expect(html, contains(MailTemplates.support));
      expect(html, contains('The BankPop Team'));
      expect(html, contains('expires in 24 hours'));
    });

    test('the text version still has the link', () {
      final String text = MailTemplates.verificationText(actionUrl: link);

      expect(text, contains(link));
      expect(text, contains('verify'));
      expect(text, contains(MailTemplates.support));
    });
  });

  group('the reset mail', () {
    const String password = 'aB3defghJK4m';
    const String appUrl = 'https://bankpop.example';

    test('shows the temporary password', () {
      final String html =
          MailTemplates.resetHtml(temporaryPassword: password, appUrl: appUrl);

      expect(html, contains(password));
      // In the box that is meant to be retyped from.
      expect(html, contains('letter-spacing:3px'));
      expect(html, contains('font-family:ui-monospace'));
    });

    test('promises a new password at sign-in, and no change until then', () {
      final String html =
          MailTemplates.resetHtml(temporaryPassword: password, appUrl: appUrl);

      expect(html, contains('choose a new password'));
      expect(html, contains('keeps working until you do'));
      expect(html, contains('nothing has changed'));
    });

    test('has no button, because there is nothing to open', () {
      final String html =
          MailTemplates.resetHtml(temporaryPassword: password, appUrl: appUrl);

      expect(html, isNot(contains('background-color:#689F38;padding')));
      expect(html, contains(MailTemplates.support));
    });

    test('the text version still has the password', () {
      final String text = MailTemplates.resetText(temporaryPassword: password);

      expect(text, contains(password));
      expect(text, contains('new password'));
      expect(text, contains(MailTemplates.support));
    });
  });

  test('both mails render a complete document a client can display', () {
    final String verify = MailTemplates.verificationHtml(
      actionUrl: 'https://bankpop.example/verify?token=abc',
      appUrl: 'https://bankpop.example',
    );
    final String reset = MailTemplates.resetHtml(
      temporaryPassword: 'aB3defghJK4m',
      appUrl: 'https://bankpop.example',
    );

    for (final String html in <String>[verify, reset]) {
      expect(html, startsWith('<!DOCTYPE html'));
      expect(html, endsWith('</html>'));
      expect(html, contains('charset=UTF-8'));
      expect(html, contains('BankPop Logo'));
      // Gmail drops <style> unless it is inline, so the colours have to be on
      // the elements themselves.
      expect(html, contains('background-color:#fff8f1'));
      expect(html, contains('max-width:600px'));
    }
  });
}
