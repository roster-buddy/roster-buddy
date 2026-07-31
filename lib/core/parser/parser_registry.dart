import '../models/document_type.dart';
import 'base_parser.dart';

class ParserRegistry {
  ParserRegistry(this.parsers);

  final List<BaseParser> parsers;

  BaseParser? parserFor(DocumentType type) {
    for (final parser in parsers) {
      if (parser.supportedType == type) {
        return parser;
      }
    }
    return null;
  }

  bool supports(DocumentType type) {
    return parserFor(type) != null;
  }

  List<DocumentType> get supportedTypes =>
      parsers.map((p) => p.supportedType).toList();
}
