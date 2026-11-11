import '../../domain/text_parsers.dart';
import 'scanner_stub.dart' if (dart.library.io) 'scanner_mobile.dart' as impl;

/// Reads a receipt photo on the phone (on-device text recognition; the photo
/// never leaves the phone). Not available in the web app.
abstract final class ReceiptScanner {
  static bool get supported => impl.supported;

  /// Opens the camera (or gallery) and returns what was read, or null if
  /// the person cancelled.
  static Future<ParsedReceipt?> scan({bool camera = true}) => impl.scan(camera: camera);
}
