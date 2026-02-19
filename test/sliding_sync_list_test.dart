import 'package:sliding_sync/sliding_sync.dart';
import 'package:test/test.dart';

/// Helper to simulate a server response for a list.
SyncListResponse _response(int count, [List<int>? range]) {
  return SyncListResponse(
    count: count,
    ops: range != null ? [SyncOp(range: range)] : [],
  );
}

void main() {
  group('SlidingSyncList — initial state', () {
    test('defaults to notLoaded', () {
      final list = SlidingSyncList(name: 'test');
      expect(list.loadingState, ListLoadingState.notLoaded);
      expect(list.serverRoomCount, isNull);
    });

    test('default range is [0, batchSize - 1]', () {
      final list = SlidingSyncList(name: 'test', batchSize: 10);
      expect(list.ranges, [
        [0, 9]
      ]);
    });

    test('respects initialRanges', () {
      final list = SlidingSyncList(
        name: 'test',
        initialRanges: [
          [5, 15]
        ],
      );
      expect(list.ranges, [
        [5, 15]
      ]);
    });
  });

  group('SlidingSyncList — selective mode', () {
    test('returns fixed range and never advances', () {
      final list = SlidingSyncList(
        name: 'sel',
        syncMode: SyncMode.selective,
        initialRanges: [
          [0, 9]
        ],
      );

      expect(list.computeNextRange(), [0, 9]);

      // Simulate response.
      list.handleResponse(_response(100, [0, 9]));

      // Range stays the same.
      expect(list.computeNextRange(), [0, 9]);
      expect(list.loadingState, ListLoadingState.fullyLoaded);
    });
  });

  group('SlidingSyncList — growing mode', () {
    test('grows by batchSize each tick', () {
      final list = SlidingSyncList(
        name: 'grow',
        syncMode: SyncMode.growing,
        batchSize: 20,
      );

      // First request range.
      expect(list.computeNextRange(), [0, 39]);

      // Server responds with synced range [0, 39], 100 total rooms.
      list.handleResponse(_response(100, [0, 39]));
      expect(list.loadingState, ListLoadingState.partiallyLoaded);

      // Next tick should grow to [0, 59].
      expect(list.computeNextRange(), [0, 59]);

      list.handleResponse(_response(100, [0, 59]));
      expect(list.computeNextRange(), [0, 79]);

      list.handleResponse(_response(100, [0, 79]));
      expect(list.computeNextRange(), [0, 99]);

      // After syncing [0, 99] with 100 rooms, should be fully loaded.
      list.handleResponse(_response(100, [0, 99]));
      expect(list.loadingState, ListLoadingState.fullyLoaded);
    });

    test('clamps to server room count', () {
      final list = SlidingSyncList(
        name: 'grow',
        syncMode: SyncMode.growing,
        batchSize: 50,
      );

      // Server only has 30 rooms.
      list.handleResponse(_response(30, [0, 29]));
      expect(list.loadingState, ListLoadingState.fullyLoaded);
      // Can't grow further, re-sends current range.
      expect(list.computeNextRange(), [0, 29]);
    });

    test('respects maxRoomsToFetch', () {
      final list = SlidingSyncList(
        name: 'grow',
        syncMode: SyncMode.growing,
        batchSize: 20,
        maxRoomsToFetch: 40,
      );

      list.handleResponse(_response(200, [0, 19]));
      expect(list.loadingState, ListLoadingState.partiallyLoaded);
      expect(list.computeNextRange(), [0, 39]);

      list.handleResponse(_response(200, [0, 39]));
      expect(list.loadingState, ListLoadingState.fullyLoaded);
    });

    test('does not double-increment ranges', () {
      final list = SlidingSyncList(
        name: 'grow',
        syncMode: SyncMode.growing,
        batchSize: 10,
      );

      // Initial range is [0, 9]. computeNextRange grows to [0, 19].
      list.handleResponse(_response(50, [0, 19]));
      // After handleResponse stores [0, 19], next compute should be [0, 29] — not [0, 39].
      expect(list.computeNextRange(), [0, 29]);

      list.handleResponse(_response(50, [0, 29]));
      expect(list.computeNextRange(), [0, 39]);

      list.handleResponse(_response(50, [0, 39]));
      expect(list.computeNextRange(), [0, 49]);

      list.handleResponse(_response(50, [0, 49]));
      expect(list.loadingState, ListLoadingState.fullyLoaded);
    });
  });

  group('SlidingSyncList — paging mode', () {
    test('pages through rooms in batches', () {
      final list = SlidingSyncList(
        name: 'page',
        syncMode: SyncMode.paging,
        batchSize: 20,
      );

      // First page.
      expect(list.computeNextRange(), [0, 19]);

      list.handleResponse(_response(50, [0, 19]));
      expect(list.loadingState, ListLoadingState.partiallyLoaded);
      expect(list.computeNextRange(), [20, 39]);

      list.handleResponse(_response(50, [20, 39]));
      expect(list.computeNextRange(), [40, 49]);

      list.handleResponse(_response(50, [40, 49]));
      expect(list.loadingState, ListLoadingState.fullyLoaded);
      expect(list.computeNextRange(), isNull);
    });

    test('respects maxRoomsToFetch', () {
      final list = SlidingSyncList(
        name: 'page',
        syncMode: SyncMode.paging,
        batchSize: 20,
        maxRoomsToFetch: 30,
      );

      list.handleResponse(_response(100, [0, 19]));
      expect(list.computeNextRange(), [20, 29]);

      list.handleResponse(_response(100, [20, 29]));
      expect(list.loadingState, ListLoadingState.fullyLoaded);
      expect(list.computeNextRange(), isNull);
    });
  });

  group('SlidingSyncList — toConfig', () {
    test('builds SyncListConfig with current range', () {
      final list = SlidingSyncList(
        name: 'cfg',
        syncMode: SyncMode.selective,
        timelineLimit: 5,
        requiredState: [
          ['m.room.topic', '']
        ],
        filters: const SlidingRoomFilter(isDm: true),
        initialRanges: [
          [0, 9]
        ],
      );

      final config = list.toConfig();
      expect(config.range, [0, 9]);
      expect(config.timelineLimit, 5);
      expect(config.requiredState, [
        ['m.room.topic', '']
      ]);
      expect(config.filters?.isDm, true);
    });
  });

  group('SlidingSyncList — edge cases', () {
    test('handles response with no ops', () {
      final list = SlidingSyncList(
        name: 'edge',
        syncMode: SyncMode.growing,
        batchSize: 10,
      );

      // Response with count but no ops — ranges stay at initial.
      list.handleResponse(_response(50));
      expect(list.serverRoomCount, 50);
      expect(list.loadingState, ListLoadingState.partiallyLoaded);
    });

    test('handles server with zero rooms', () {
      final list = SlidingSyncList(
        name: 'empty',
        syncMode: SyncMode.growing,
        batchSize: 10,
      );

      list.handleResponse(const SyncListResponse(count: 0));
      expect(list.serverRoomCount, 0);
    });

    test('paging with exact batch boundary', () {
      final list = SlidingSyncList(
        name: 'exact',
        syncMode: SyncMode.paging,
        batchSize: 25,
      );

      list.handleResponse(_response(50, [0, 24]));
      expect(list.computeNextRange(), [25, 49]);

      list.handleResponse(_response(50, [25, 49]));
      expect(list.loadingState, ListLoadingState.fullyLoaded);
      expect(list.computeNextRange(), isNull);
    });
  });
}
