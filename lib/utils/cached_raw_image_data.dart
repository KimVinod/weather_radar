import 'dart:typed_data';

/// A simple data class to bundle the raw image bytes from the repository
/// along with the timestamp of when they were fetched/cached.
class CachedRawImageData {
  final Uint8List bytes;
  final DateTime timestamp;

  CachedRawImageData({required this.bytes, required this.timestamp});
}