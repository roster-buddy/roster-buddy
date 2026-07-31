import '../models/document_type.dart';
import '../models/parse_result.dart';

abstract class BaseParser {
  /// The type of document this parser understands.
  DocumentType get supportedType;

  /// Parse OCR text into a structured ParseResult.
  Future<ParseResult> parse({required List<String> pageText});

  /// Quick check to see if this parser is suitable.
  bool canParse(List<String> pageText);
}
