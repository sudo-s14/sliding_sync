/// Exception thrown by sliding sync operations.

class SlidingSyncException implements Exception {
  final String message;
  const SlidingSyncException(this.message);

  @override
  String toString() => 'SlidingSyncException: $message';
}
