import 'package:url_launcher/url_launcher.dart';

Future<void> openUploadedDocument(Future<String> Function() resolveUrl) async {
  final url = await resolveUrl();
  if (!await launchUrl(Uri.parse(url), mode: LaunchMode.platformDefault)) {
    throw StateError('Could not open document');
  }
}
