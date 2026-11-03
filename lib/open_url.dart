import 'package:url_launcher/url_launcher.dart';

/// Opens a page in the phone's own browser. A variable so a test can watch
/// what would open.
Future<void> Function(Uri uri) openExternalUrl = (uri) async {
  await launchUrl(uri, mode: LaunchMode.externalApplication);
};
