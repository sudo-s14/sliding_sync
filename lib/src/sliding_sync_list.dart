/// SlidingSyncList — manages a filtered room subset with sliding window logic.

import 'enums.dart';
import 'models/request.dart';
import 'models/response.dart' show SyncListResponse;

class SlidingSyncList {
  final String name;
  final SyncMode syncMode;
  final int batchSize;
  final int? maxRoomsToFetch;
  final int timelineLimit;
  final List<List<String>> requiredState;
  final SlidingRoomFilter? filters;

  ListLoadingState _loadingState = ListLoadingState.notLoaded;
  int? _serverRoomCount;

  // Current window ranges — selective uses fixed ranges, paging/growing compute them.
  List<List<int>> _ranges;

  // For paging: tracks the next page start index.
  int _pageOffset = 0;

  SlidingSyncList({
    required this.name,
    this.syncMode = SyncMode.growing,
    this.batchSize = 20,
    this.maxRoomsToFetch,
    this.timelineLimit = 10,
    this.requiredState = const [],
    this.filters,
    List<List<int>>? initialRanges,
  }) : _ranges = initialRanges ?? [[0, batchSize - 1]];

  ListLoadingState get loadingState => _loadingState;
  int? get serverRoomCount => _serverRoomCount;
  List<List<int>> get ranges => List.unmodifiable(_ranges);

  int _clampEnd(int end, int? total, int? cap) {
    if (total != null && end >= total) end = total - 1;
    if (cap != null && end >= cap) end = cap - 1;
    return end;
  }

  /// Whether all rooms have been fetched.
  bool get _isFullyLoaded {
    final total = _serverRoomCount;
    final cap = maxRoomsToFetch ?? total;
    if (total == null) return false;

    switch (syncMode) {
      case SyncMode.selective:
        return true; // selective never grows
      case SyncMode.paging:
        return _pageOffset >= total || (cap != null && _pageOffset >= cap);
      case SyncMode.growing:
        if (_ranges.isEmpty) return false;
        final currentEnd = _ranges.first[1];
        return currentEnd >= total - 1 || (cap != null && currentEnd >= cap - 1);
    }
  }

  /// Called after processing a sync response for this list.
  void handleResponse(SyncListResponse listResponse) {
    _serverRoomCount = listResponse.count;

    // Record the synced range from SYNC ops.
    for (final op in listResponse.ops) {
      if (op.range != null) {
        _ranges = [op.range!];
        if (syncMode == SyncMode.paging) {
          _pageOffset = op.range![1] + 1;
        }
      }
    }

    _loadingState =
        _isFullyLoaded ? ListLoadingState.fullyLoaded : ListLoadingState.partiallyLoaded;
  }

  /// Compute the range to send in the next request, based on sync mode.
  List<int>? computeNextRange() {
    final total = _serverRoomCount;
    final cap = maxRoomsToFetch ?? total;

    switch (syncMode) {
      case SyncMode.selective:
        return _ranges.isNotEmpty ? _ranges.first : null;

      case SyncMode.paging:
        if (total != null && _pageOffset >= total) return null;
        if (cap != null && _pageOffset >= cap) return null;
        final end = _clampEnd(_pageOffset + batchSize - 1, total, cap);
        return [_pageOffset, end];

      case SyncMode.growing:
        // Grow from the last synced end position.
        final currentEnd = _ranges.isNotEmpty ? _ranges.first[1] : -1;
        final newEnd = _clampEnd(currentEnd + batchSize, total, cap);
        // If we can't grow further, re-send the current range for updates.
        if (newEnd <= currentEnd) return [0, currentEnd];
        return [0, newEnd];
    }
  }

  /// Build the list config portion of the request.
  SyncListConfig toConfig() {
    final range = computeNextRange();
    return SyncListConfig(
      range: range,
      timelineLimit: timelineLimit,
      requiredState: requiredState,
      filters: filters,
    );
  }
}
