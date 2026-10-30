/// The two emails the account screens send, in the BankPop design.
///
/// Both messages share one look - the cream page, the green button with the
/// offset border, the mark at the top - so somebody who gets both recognises
/// them as coming from the same game. The markup is the table-and-inline-style
/// kind a mail client can render: no external stylesheet, no flexbox, no width
/// that only works in a browser, and every colour written out on the element
/// that uses it, because Gmail and Outlook throw <style> blocks away.
///
/// The plain-text parts say the same thing, because a client that shows text
/// only (or a phone that is set to) must still get a working link or password.
class MailTemplates {
  const MailTemplates._();

  /// The BankPop mark. Hosted, so the mail does not depend on it being an
  /// attachment the client might strip.
  static const String _logoUrl =
      'https://res.cloudinary.com/dnsggymke/image/upload/v1793035142/'
      'play_icon_wejq6y.jpg';

  /// Where a person writes when the mail does not answer their question.
  static const String support = 'support@bankpop.com';

  /// The sign-off both mails end with.
  static const String _signOff =
      'Pass GO and collect your wins,<br/><strong>The BankPop Team</strong>';

  // ---------------------------------------------------------------------------
  // Verification
  // ---------------------------------------------------------------------------

  /// The mail a new account gets, and the one the Resend button repeats.
  ///
  /// [actionUrl] is the verification link; [appUrl] is the public address of
  /// the web build, used for the mark's link. Pass an empty [appUrl] and the
  /// mark is simply not a link.
  static String verificationHtml({
    required String actionUrl,
    required String appUrl,
  }) {
    final String link = _escape(actionUrl);
    return _shell(
      title: 'Verify your BankPop account',
      appUrl: appUrl,
      content: '''
<h2 style="margin:0;padding:0;margin-top:0;color:#2c2c2c;margin-bottom:0.83em">Welcome to the BankPop table! 🎲</h2>
<p style="margin:0;padding:0;margin-top:1em;margin-bottom:1em">We&#x27;re thrilled to have you join the game.</p>
<p style="margin:0;padding:0;margin-top:1em;margin-bottom:1em">Your account has been successfully created. Before you can start trading properties, scanning cards, and building your empire, we just need you to verify your email address to secure your vault.</p>
<p style="margin:32px 0;padding:0"><a href="$link" rel="noopener noreferrer nofollow" style="color:#ffffff;text-decoration-line:none;text-decoration:none;display:inline-block;outline:none;background-color:#689F38;padding:12px 24px;border-radius:6px;font-weight:bold;border:2px solid #2c2c2c;box-shadow:3px 3px 0px #2c2c2c" target="_blank">Verify Your Account</a></p>
<p style="margin:0;padding:0;margin-top:1em;margin-bottom:1em;font-size:13px;color:#6b6b6b">The button did not work? Paste this address into your browser:<br/><a href="$link" rel="noopener noreferrer nofollow" style="color:#689F38;text-decoration:none;word-break:break-all" target="_blank">$link</a></p>
<p style="margin:0;padding:0;margin-top:1em;margin-bottom:1em;font-size:13px;color:#6b6b6b">The link works once and expires in 24 hours.</p>
<p style="margin:0;padding:0;margin-top:1em;margin-bottom:1em">If you hit a snag or need a rule clarification, the Banker is just an email away at <a href="mailto:$support" rel="noopener noreferrer nofollow" style="color:#689F38;text-decoration-line:none;text-decoration:none;outline:none;font-weight:bold" target="_blank">$support</a>. We&#x27;ve got your back!</p>
<p style="margin:0;padding:0;margin-top:1em;margin-bottom:1em">$_signOff</p>
''',
    );
  }

  /// The same message for a client that shows text only.
  static String verificationText({required String actionUrl}) => '''
Welcome to the BankPop table!

Your account has been created. Open this link to verify your email address:
$actionUrl

The link works once and expires in 24 hours. If you did not create a
BankPop account, you can ignore this email.

If you hit a snag or need a rule clarification, write to $support.

Pass GO and collect your wins,
The BankPop Team
''';

  // ---------------------------------------------------------------------------
  // Password reset
  // ---------------------------------------------------------------------------

  /// The temporary password, sent when somebody asks to reset theirs.
  ///
  /// The password is shown in a bordered box rather than in a link: the person
  /// types it into the sign-in screen, and the app then asks for a new
  /// password. A link would need its own token, its own expiry and its own
  /// table, and the temporary password already has all three.
  static String resetHtml({
    required String temporaryPassword,
    required String appUrl,
  }) {
    final String password = _escape(temporaryPassword);
    return _shell(
      title: 'Your BankPop temporary password',
      appUrl: appUrl,
      content: '''
<h2 style="margin:0;padding:0;margin-top:0;color:#2c2c2c;margin-bottom:0.83em">Here is your temporary password 🔑</h2>
<p style="margin:0;padding:0;margin-top:1em;margin-bottom:1em">Somebody asked to reset the password on this BankPop account, so we made a temporary one for you.</p>
<p style="margin:24px 0;padding:16px;background-color:#ffffff;border:2px solid #2c2c2c;box-shadow:3px 3px 0px #2c2c2c;border-radius:6px;text-align:center;font-family:ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;font-size:24px;letter-spacing:3px;font-weight:bold;color:#2c2c2c;word-break:break-all">$password</p>
<p style="margin:0;padding:0;margin-top:1em;margin-bottom:1em">Sign in with it, and the app asks you to choose a new password straight away. Your usual password keeps working until you do.</p>
<p style="margin:0;padding:0;margin-top:1em;margin-bottom:1em">If you did not ask for this, you can ignore this email - nothing has changed, and the temporary password can be replaced by asking again.</p>
<p style="margin:0;padding:0;margin-top:1em;margin-bottom:1em">Stuck? The Banker is an email away at <a href="mailto:$support" rel="noopener noreferrer nofollow" style="color:#689F38;text-decoration-line:none;text-decoration:none;outline:none;font-weight:bold" target="_blank">$support</a>.</p>
<p style="margin:0;padding:0;margin-top:1em;margin-bottom:1em">$_signOff</p>
''',
    );
  }

  /// The same message for a client that shows text only.
  static String resetText({required String temporaryPassword}) => '''
Here is your temporary BankPop password:

$temporaryPassword

Sign in with it, and the app asks you to choose a new password straight
away. Your usual password keeps working until you do.

If you did not ask for this, you can ignore this email - nothing has
changed.

Stuck? Write to $support.

Pass GO and collect your wins,
The BankPop Team
''';

  // ---------------------------------------------------------------------------
  // The frame both mails sit in
  // ---------------------------------------------------------------------------

  /// The cream page, the mark, and the content in the middle.
  static String _shell({
    required String title,
    required String appUrl,
    required String content,
  }) {
    final String mark = '<img alt="BankPop Logo" src="$_logoUrl" '
        'style="display:block;outline:none;border:none;'
        'text-decoration:none;max-width:100%;height:48px;'
        'vertical-align:middle;margin-bottom:16px;border-radius:12px"/>';
    final String logo = appUrl.isEmpty
        ? mark
        : '<a href="${_escape(appUrl)}" '
            'style="color:#067df7;text-decoration-line:none" '
            'target="_blank">$mark</a>';
    return '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" '
        '"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">'
        '<html dir="ltr" lang="en"><head>'
        '<meta content="width=device-width" name="viewport"/>'
        '<meta content="text/html; charset=UTF-8" http-equiv="Content-Type"/>'
        '<meta content="x-apple-disable-message-reformatting" '
        'name="x-apple-disable-message-reformatting"/>'
        '<meta content="IE=edge" http-equiv="X-UA-Compatible"/>'
        '<meta content="telephone=no,address=no,email=no,date=no,url=no" '
        'name="format-detection"/>'
        '<style>@media (prefers-color-scheme: dark){li::marker{'
        'color:#c4c4c4}}</style>'
        '<title>${_escape(title)}</title>'
        '</head>'
        '<body dir="ltr" lang="en" style="background-color:#fff8f1;'
        'margin:0;padding:0">'
        '<table border="0" width="100%" cellpadding="0" cellspacing="0" '
        'role="presentation" align="center"><tbody><tr>'
        '<td dir="ltr" lang="en" style="background-color:#fff8f1;'
        'margin:0;padding:8px">'
        '<table align="left" width="100%" border="0" cellpadding="0" '
        'cellspacing="0" role="presentation" style="max-width:600px;'
        'width:100%;background-color:#fff8f1">'
        '<tbody><tr style="width:100%"><td style="padding:0">'
        '<div style="margin:0;padding:0;font-family:system-ui, sans-serif, '
        'Arial;font-size:16px;background-color:#fff8f1;color:#2c2c2c">'
        '<div style="margin:auto;padding:32px 16px;max-width:600px">'
        '$logo$content'
        '</div></div>'
        '</td></tr></tbody></table>'
        '</td></tr></tbody></table>'
        '</body></html>';
  }

  /// Enough escaping for a value that goes into an attribute or into text.
  /// Tokens and passwords are already URL- and letter-safe, but the app URL is
  /// a setting and a `&` in it would otherwise end an attribute early.
  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
