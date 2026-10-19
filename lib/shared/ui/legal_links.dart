import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// The privacy policy, terms and help pages, served by Firebase Hosting
/// from web/ (privacy.html, terms.html, support.html).
abstract final class LegalLinks {
  static const _site = 'https://notely-b1aec.web.app';
  static final privacy = Uri.parse('$_site/privacy.html');
  static final terms = Uri.parse('$_site/terms.html');
  static final support = Uri.parse('$_site/support.html');
}

/// Opens [url] in the browser.
Future<void> openLink(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

/// "Privacy Policy · Terms of Use", small and centred, under a sign-in or
/// purchase button.
class LegalFooter extends StatelessWidget {
  const LegalFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final style = TextButton.styleFrom(
      textStyle: Theme.of(context).textTheme.bodySmall,
      visualDensity: VisualDensity.compact,
    );
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton(
          style: style,
          onPressed: () => openLink(LegalLinks.privacy),
          child: const Text('Privacy Policy'),
        ),
        Text('·', style: Theme.of(context).textTheme.bodySmall),
        TextButton(
          style: style,
          onPressed: () => openLink(LegalLinks.terms),
          child: const Text('Terms of Use'),
        ),
      ],
    );
  }
}
