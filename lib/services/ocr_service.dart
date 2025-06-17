import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

// --- RESTORED TO SINGLETON ---
// It's safe now because it will only be used on the main thread.
class OcrService {
  static final OcrService _instance = OcrService._internal();
  factory OcrService() => _instance;
  OcrService._internal();

  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  static const int _roiX = 2450;
  static const int _roiY = 0;
  static const int _roiWidth = 1300;
  static const int _roiHeight = 1000;

  // --- NEW METHOD ---
  // This now takes the RAW, ORIGINAL image bytes.
  Future<DateTime?> processImageForTimestamp(Uint8List originalImageBytes) async {
    final originalImage = img.decodeImage(originalImageBytes);
    if (originalImage == null) return null;

    final roiImage = img.copyCrop(
      originalImage, x: _roiX, y: _roiY, width: _roiWidth, height: _roiHeight,
    );

    // The rest of the logic remains the same: save to a temp file and process.
    try {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/ocr_roi.jpg');
      await tempFile.writeAsBytes(img.encodeJpg(roiImage));

      final inputImage = InputImage.fromFilePath(tempFile.path);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

      await tempFile.delete();
      return _parseTextForUtcDateTime(recognizedText.text);
    } catch (e) {
      log("OCR Error during processing: $e");
      return null;
    }
  }

  /// Parses a block of text to find and construct a UTC DateTime object.
  DateTime? _parseTextForUtcDateTime(String text) {
    log("--- RAW OCR OUTPUT ---\n$text\n--- END RAW OCR OUTPUT ---");

    const monthMap = {
      'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
      'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
    };

    // --- NEW, MORE ROBUST LOGIC ---
    // First, remove all line breaks to treat the text as a single string.
    final singleLineText = text.replaceAll('\n', ' ');

    // Use a Regular Expression to find the entire timestamp pattern at once.
    // This is much more resilient to OCR errors like random line breaks.
    // Breakdown of the RegEx:
    // (\d{2}:\d{2}:\d{2})  - Group 1: Captures the time (e.g., "08:55:04")
    // \s*UTC\s*[/|]\s*    - Matches "UTC" and the separator
    // (\d{2}\s+\w{3}\s+\d{4}) - Group 2: Captures the date (e.g., "17 Jun 2025")
    final regExp = RegExp(r'(\d{2}:\d{2}:\d{2})\s*UTC\s*[/|]\s*(\d{2}\s+\w{3}\s+\d{4})');

    final match = regExp.firstMatch(singleLineText);

    if (match != null) {
      try {
        // match.group(1) will be the time part, e.g., "08:55:04"
        final timePart = match.group(1)!;
        // match.group(2) will be the date part, e.g., "17 Jun 2025"
        final datePart = match.group(2)!;

        final timeComponents = timePart.split(':');
        final dateComponents = datePart.split(' ');

        if (timeComponents.length < 3 || dateComponents.length < 3) return null;

        final hour = int.parse(timeComponents[0]);
        final minute = int.parse(timeComponents[1]);
        final second = int.parse(timeComponents[2]);

        final day = int.parse(dateComponents[0]);
        final month = monthMap[dateComponents[1]] ?? 0;
        final year = int.parse(dateComponents[2]);

        if (month == 0) return null;

        log("SUCCESS (RegEx): Parsed DateTime: $year-$month-$day $hour:$minute:$second UTC");
        return DateTime.utc(year, month, day, hour, minute, second);
      } catch (e) {
        log("OCR RegEx Parse Error: $e");
        return null;
      }
    } else {
      log("OCR Parse Error: Could not find the timestamp pattern using RegEx.");
      return null;
    }
  }

  /// Closes the text recognizer to free up resources.
  void dispose() {
    _textRecognizer.close();
  }
}