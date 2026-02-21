import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sliding_sync/sliding_sync.dart';
import 'package:test/test.dart';

SlidingSync _createSync() {
  return SlidingSync(
    client: http.Client(),
    connId: 'test',
    catchUpTimeout: const Duration(seconds: 2),
    longPollTimeout: const Duration(seconds: 30),
  );
}

SyncListResponse _listResponse(int count, [List<int>? range]) {
  return SyncListResponse(
    count: count,
    ops: range != null ? [SyncOp(range: range)] : [],
  );
}

void main() {
  // ── SyncState JSON serialization ──

  group('SyncState — toJson / fromJson', () {
    test('round-trips with all fields', () {
      const state = SyncState(
        pos: 'tok_5',
        toDeviceSince: 'td_batch_3',
        lists: {
          'rooms': SyncListState(range: [0, 49], serverRoomCount: 100),
          'dms': SyncListState(range: [0, 9], serverRoomCount: 10),
        },
      );

      final json = state.toJson();
      final restored = SyncState.fromJson(json);

      expect(restored.pos, 'tok_5');
      expect(restored.toDeviceSince, 'td_batch_3');
      expect(restored.lists['rooms']!.range, [0, 49]);
      expect(restored.lists['rooms']!.serverRoomCount, 100);
      expect(restored.lists['dms']!.range, [0, 9]);
      expect(restored.lists['dms']!.serverRoomCount, 10);
    });

    test('round-trips through JSON string encoding', () {
      const state = SyncState(
        pos: 'abc',
        toDeviceSince: 'xyz',
        lists: {
          'rooms': SyncListState(range: [0, 19], serverRoomCount: 50),
        },
      );

      final jsonString = jsonEncode(state.toJson());
      final decoded = SyncState.fromJson(
        jsonDecode(jsonString) as Map<String, dynamic>,
      );

      expect(decoded.pos, 'abc');
      expect(decoded.toDeviceSince, 'xyz');
      expect(decoded.lists['rooms']!.range, [0, 19]);
    });

    test('handles null fields', () {
      const state = SyncState();

      final json = state.toJson();
      expect(json, isEmpty);

      final restored = SyncState.fromJson(json);
      expect(restored.pos, isNull);
      expect(restored.toDeviceSince, isNull);
      expect(restored.lists, isEmpty);
    });

    test('handles empty JSON', () {
      final restored = SyncState.fromJson({});

      expect(restored.pos, isNull);
      expect(restored.toDeviceSince, isNull);
      expect(restored.lists, isEmpty);
    });
  });

  group('SyncListState — toJson / fromJson', () {
    test('round-trips with all fields', () {
      const state = SyncListState(range: [0, 29], serverRoomCount: 75);

      final json = state.toJson();
      final restored = SyncListState.fromJson(json);

      expect(restored.range, [0, 29]);
      expect(restored.serverRoomCount, 75);
    });

    test('handles null fields', () {
      const state = SyncListState();

      final json = state.toJson();
      expect(json, isEmpty);

      final restored = SyncListState.fromJson(json);
      expect(restored.range, isNull);
      expect(restored.serverRoomCount, isNull);
    });
  });

  // ── SlidingSyncList export / restore ──

  group('SlidingSyncList — exportState', () {
    test('exports range and server room count after sync', () {
      final list = SlidingSyncList(
        name: 'rooms',
        syncMode: SyncMode.growing,
        batchSize: 10,
      );

      list.handleResponse(_listResponse(50, [0, 9]));
      final state = list.exportState();

      expect(state.range, [0, 9]);
      expect(state.serverRoomCount, 50);
    });

    test('exports initial state before any sync', () {
      final list = SlidingSyncList(name: 'rooms', batchSize: 10);
      final state = list.exportState();

      expect(state.range, [0, 9]);
      expect(state.serverRoomCount, isNull);
    });
  });

  group('SlidingSyncList — restoreState', () {
    test('growing list resumes from restored range', () {
      final list = SlidingSyncList(
        name: 'rooms',
        syncMode: SyncMode.growing,
        batchSize: 10,
      );

      list.restoreState(
        const SyncListState(range: [0, 39], serverRoomCount: 100),
      );

      expect(list.ranges, [
        [0, 39]
      ]);
      expect(list.serverRoomCount, 100);
      expect(list.loadingState, ListLoadingState.partiallyLoaded);

      // Should grow from [0, 39] to [0, 49].
      expect(list.computeNextRange(), [0, 49]);
    });

    test('growing list restored as fully loaded when range covers all rooms', () {
      final list = SlidingSyncList(
        name: 'rooms',
        syncMode: SyncMode.growing,
        batchSize: 10,
      );

      list.restoreState(
        const SyncListState(range: [0, 49], serverRoomCount: 50),
      );

      expect(list.loadingState, ListLoadingState.fullyLoaded);
    });

    test('paging list resumes from correct page offset', () {
      final list = SlidingSyncList(
        name: 'rooms',
        syncMode: SyncMode.paging,
        batchSize: 20,
      );

      list.restoreState(
        const SyncListState(range: [20, 39], serverRoomCount: 100),
      );

      // pageOffset should be 40, so next page is [40, 59].
      expect(list.computeNextRange(), [40, 59]);
    });

    test('selective list restores range', () {
      final list = SlidingSyncList(
        name: 'rooms',
        syncMode: SyncMode.selective,
        initialRanges: [[0, 9]],
      );

      list.restoreState(
        const SyncListState(range: [0, 9], serverRoomCount: 10),
      );

      expect(list.loadingState, ListLoadingState.fullyLoaded);
      expect(list.computeNextRange(), [0, 9]);
    });
  });

  // ── SlidingSync export / restore ──

  group('SlidingSync — exportState', () {
    test('exports pos and toDeviceSince after sync', () {
      final sync = _createSync();
      sync.enableExtension('to_device');

      sync.handleResponse(const SlidingSyncResponse(
        pos: 'tok_7',
        extensions: {
          'to_device': {'next_batch': 'td_99', 'events': []},
        },
      ));

      final state = sync.exportState();

      expect(state.pos, 'tok_7');
      expect(state.toDeviceSince, 'td_99');
    });

    test('exports list states', () {
      final sync = _createSync();
      sync.addList(SlidingSyncList(name: 'rooms', batchSize: 10));
      sync.addList(SlidingSyncList(name: 'dms', batchSize: 5));

      sync.handleResponse(SlidingSyncResponse(
        pos: '1',
        lists: {
          'rooms': _listResponse(50, [0, 9]),
          'dms': _listResponse(8, [0, 4]),
        },
      ));

      final state = sync.exportState();

      expect(state.lists['rooms']!.range, [0, 9]);
      expect(state.lists['rooms']!.serverRoomCount, 50);
      expect(state.lists['dms']!.range, [0, 4]);
      expect(state.lists['dms']!.serverRoomCount, 8);
    });

    test('exports null pos and toDeviceSince before any sync', () {
      final sync = _createSync();
      final state = sync.exportState();

      expect(state.pos, isNull);
      expect(state.toDeviceSince, isNull);
    });
  });

  group('SlidingSync — restoreState', () {
    test('restores pos into next request', () {
      final sync = _createSync();

      sync.restoreState(const SyncState(pos: 'saved_pos'));

      final request = sync.buildRequest();
      expect(request.pos, 'saved_pos');
    });

    test('restores toDeviceSince into next request', () {
      final sync = _createSync();
      sync.enableExtension('to_device');

      sync.restoreState(const SyncState(toDeviceSince: 'td_42'));

      final request = sync.buildRequest();
      final ext = request.extensions['to_device']!;
      expect(ext, isA<ToDeviceExtension>());
      expect((ext as ToDeviceExtension).since, 'td_42');
    });

    test('restores list states for matching lists', () {
      final sync = _createSync();
      sync.addList(SlidingSyncList(
        name: 'rooms',
        syncMode: SyncMode.growing,
        batchSize: 10,
      ));

      sync.restoreState(const SyncState(
        pos: 'tok_5',
        lists: {
          'rooms': SyncListState(range: [0, 39], serverRoomCount: 100),
        },
      ));

      // List should resume growing from [0, 39].
      final request = sync.buildRequest();
      expect(request.pos, 'tok_5');
      expect(request.lists['rooms']!.range, [0, 49]);
    });

    test('ignores list states for unknown lists', () {
      final sync = _createSync();
      sync.addList(SlidingSyncList(name: 'rooms', batchSize: 10));

      // 'unknown' list is in state but not in sync — should not crash.
      sync.restoreState(const SyncState(
        lists: {
          'rooms': SyncListState(range: [0, 9], serverRoomCount: 50),
          'unknown': SyncListState(range: [0, 4], serverRoomCount: 5),
        },
      ));

      expect(sync.getList('rooms')!.serverRoomCount, 50);
      expect(sync.getList('unknown'), isNull);
    });
  });

  // ── Full round-trip: export → serialize → deserialize → restore ──

  group('SlidingSync — full persistence round-trip', () {
    test('export, serialize, deserialize, restore into fresh instance', () {
      // First session: sync a few ticks.
      final sync1 = _createSync();
      sync1.addList(SlidingSyncList(
        name: 'rooms',
        syncMode: SyncMode.growing,
        batchSize: 10,
      ));
      sync1.enableExtension('to_device');

      sync1.handleResponse(SlidingSyncResponse(
        pos: 'tok_1',
        lists: {'rooms': _listResponse(50, [0, 9])},
        extensions: {
          'to_device': {'next_batch': 'td_1', 'events': []},
        },
      ));
      sync1.handleResponse(SlidingSyncResponse(
        pos: 'tok_2',
        lists: {'rooms': _listResponse(50, [0, 19])},
        extensions: {
          'to_device': {'next_batch': 'td_2', 'events': []},
        },
      ));

      // Export and serialize.
      final exported = sync1.exportState();
      final jsonString = jsonEncode(exported.toJson());

      // Second session: fresh instance, restore.
      final sync2 = _createSync();
      sync2.addList(SlidingSyncList(
        name: 'rooms',
        syncMode: SyncMode.growing,
        batchSize: 10,
      ));
      sync2.enableExtension('to_device');

      final restored = SyncState.fromJson(
        jsonDecode(jsonString) as Map<String, dynamic>,
      );
      sync2.restoreState(restored);

      // Verify the restored instance picks up where sync1 left off.
      final request = sync2.buildRequest();
      expect(request.pos, 'tok_2');
      expect(request.lists['rooms']!.range, [0, 29]); // grows from [0, 19]
      expect(
        (request.extensions['to_device']! as ToDeviceExtension).since,
        'td_2',
      );
    });
  });
}
