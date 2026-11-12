import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../../domain/text_parsers.dart';

// iPhone joins once the ML Kit text bundle is added to the iOS app (docs/IOS.md).
bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

Future<ParsedReceipt?> scan({required bool camera}) async {
  final photo = await ImagePicker().pickImage(source: camera ? ImageSource.camera : ImageSource.gallery, maxWidth: 2200, imageQuality: 92);
  if (photo == null) return null;
  final recognizer = TextRecognizer();
  try {
    final result = await recognizer.processImage(InputImage.fromFilePath(photo.path));
    return parseReceiptText(result.text);
  } finally {
    await recognizer.close();
  }
}
