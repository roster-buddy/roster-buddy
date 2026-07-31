import '../models/document_type.dart';
import '../models/parse_result.dart';
import 'base_parser.dart';

class BaseRosterParser implements BaseParser {
  @override
  DocumentType get supportedType => DocumentType.baseRoster;

  @override
  bool canParse(List<String> pageText) {
    final text = pageText.join('\n').toUpperCase();

    return text.contains('WEEK') && text.contains('SUN');
  }

  @override
  Future<ParseResult> parse({required List<String> pageText}) async {
    // TODO: Stage 1 - Detect pages
    // TODO: Stage 2 - Detect grid
    // TODO: Stage 3 - Find driver
    // TODO: Stage 4 - Extract duties
    // TODO: Stage 5 - Validate
    // TODO: Stage 6 - Build ParseResult

    return ParseResult(
      documentType: DocumentType.baseRoster,
      duties: const [],
      driverFound: false,
      pagesProcessed: pageText.length,
      weeksDetected: 0,
    );
  }
}
