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
  group('SlidingSync — list management', () {
    test('addList and getList', () {
      final sync = _createSync();
      final list = SlidingSyncList(name: 'rooms', batchSize: 10);

      sync.addList(list);
      expect(sync.getList('rooms'), same(list));
      expect(sync.getList('unknown'), isNull);
    });

    test('addList replaces list with same name', () {
      final sync = _createSync();
      final list1 = SlidingSyncList(name: 'rooms', batchSize: 10);
      final list2 = SlidingSyncList(name: 'rooms', batchSize: 20);

      sync.addList(list1);
      sync.addList(list2);
      expect(sync.getList('rooms'), same(list2));
    });
  });

  group('SlidingSync — room subscriptions', () {
    test('subscribeToRooms adds subscriptions', () {
      final sync = _createSync();
      sync.subscribeToRooms(
        ['!a:example.com', '!b:example.com'],
        const RoomSubscription(timelineLimit: 10),
      );

      final request = sync.buildRequest();
      expect(request.roomSubscriptions, contains('!a:example.com'));
      expect(request.roomSubscriptions, contains('!b:example.com'));
    });

    test('unsubscribeFromRooms removes subscriptions', () {
      final sync = _createSync();
      sync.subscribeToRooms(
        ['!a:example.com', '!b:example.com'],
        const RoomSubscription(timelineLimit: 10),
      );
      sync.unsubscribeFromRooms(['!a:example.com']);

      final request = sync.buildRequest();
      expect(request.roomSubscriptions, isNot(contains('!a:example.com')));
      expect(request.roomSubscriptions, contains('!b:example.com'));
    });

    test('subscriptions appear in request JSON', () {
      final sync = _createSync();
      sync.subscribeToRooms(
        ['!room:example.com'],
        const RoomSubscription(
          timelineLimit: 50,
          requiredState: [['m.room.topic', '']],
        ),
      );

      final json = sync.buildRequest().toJson();
      final subs = json['room_subscriptions'] as Map;
      expect(subs['!room:example.com']['timeline_limit'], 50);
    });
  });

  group('SlidingSync — extensions', () {
    test('enableExtension adds to request', () {
      final sync = _createSync();
      sync.enableExtension('e2ee');

      final request = sync.buildRequest();
      expect(request.extensions, contains('e2ee'));
      expect(request.extensions['e2ee']!.enabled, isTrue);
    });

    test('enableAllExtensions enables all five', () {
      final sync = _createSync();
      sync.enableAllExtensions();

      final request = sync.buildRequest();
      expect(request.extensions.keys, containsAll([
        'e2ee', 'to_device', 'account_data', 'typing', 'receipts',
      ]));
    });

    test('extensions appear in request JSON', () {
      final sync = _createSync();
      sync.enableExtension('typing');

      final json = sync.buildRequest().toJson();
      final exts = json['extensions'] as Map;
      expect(exts['typing']['enabled'], isTrue);
    });
  });

  group('SlidingSync — buildRequest', () {
    test('includes connId and timeout', () {
      final sync = _createSync();
      final request = sync.buildRequest();

      expect(request.connId, 'test');
      expect(request.timeout, 2000); // catchUpTimeout since no lists
    });

    test('pos is null on first request', () {
      final sync = _createSync();
      final request = sync.buildRequest();
      expect(request.pos, isNull);
    });

    test('includes list configs', () {
      final sync = _createSync();
      sync.addList(SlidingSyncList(
        name: 'all',
        syncMode: SyncMode.growing,
        batchSize: 10,
        timelineLimit: 5,
      ));

      final request = sync.buildRequest();
      expect(request.lists, contains('all'));
      expect(request.lists['all']!.timelineLimit, 5);
      expect(request.lists['all']!.range, [0, 9]);
    });

    test('request serializes to valid JSON', () {
      final sync = _createSync();
      sync.addList(SlidingSyncList(name: 'rooms', batchSize: 10));
      sync.subscribeToRooms(
        ['!r:ex.com'],
        const RoomSubscription(timelineLimit: 20),
      );
      sync.enableExtension('e2ee');

      final json = sync.buildRequest().toJson();
      expect(json['conn_id'], 'test');
      expect(json['lists'], isA<Map>());
      expect(json['room_subscriptions'], isA<Map>());
      expect(json['extensions'], isA<Map>());
    });
  });

  group('SlidingSync — handleResponse', () {
    test('updates pos from response', () {
      final sync = _createSync();
      sync.addList(SlidingSyncList(name: 'rooms', batchSize: 10));

      sync.handleResponse(const SlidingSyncResponse(pos: 'abc123'));

      final nextRequest = sync.buildRequest();
      expect(nextRequest.pos, 'abc123');
    });

    test('returns updated list names', () {
      final sync = _createSync();
      sync.addList(SlidingSyncList(name: 'rooms', batchSize: 10));

      final update = sync.handleResponse(SlidingSyncResponse(
        pos: '1',
        lists: {'rooms': _listResponse(50, [0, 9])},
      ));

      expect(update.updatedLists, ['rooms']);
    });

    test('returns updated room IDs', () {
      final sync = _createSync();

      final update = sync.handleResponse(const SlidingSyncResponse(
        pos: '1',
        rooms: {
          '!a:ex.com': SlidingRoomResponse(name: 'Room A', initial: true),
          '!b:ex.com': SlidingRoomResponse(name: 'Room B', initial: true),
        },
      ));

      expect(update.rooms.joined.keys,
          containsAll(['!a:ex.com', '!b:ex.com']));
    });

    test('ignores list responses for unknown lists', () {
      final sync = _createSync();

      final update = sync.handleResponse(SlidingSyncResponse(
        pos: '1',
        lists: {'unknown-list': _listResponse(10, [0, 9])},
      ));

      expect(update.updatedLists, isEmpty);
    });

    test('forwards response to list handleResponse', () {
      final sync = _createSync();
      final list = SlidingSyncList(name: 'rooms', batchSize: 10);
      sync.addList(list);

      sync.handleResponse(SlidingSyncResponse(
        pos: '1',
        lists: {'rooms': _listResponse(50, [0, 9])},
      ));

      expect(list.serverRoomCount, 50);
      expect(list.loadingState, ListLoadingState.partiallyLoaded);
    });
  });

  group('SlidingSync — timeout behavior', () {
    test('uses catchUpTimeout when lists are not fully synced', () {
      final sync = SlidingSync(
        client: http.Client(),
        connId: 'test',
        catchUpTimeout: const Duration(seconds: 2),
        longPollTimeout: const Duration(seconds: 30),
      );
      sync.addList(SlidingSyncList(name: 'rooms', batchSize: 10));

      final request = sync.buildRequest();
      expect(request.timeout, 2000);
    });

    test('uses longPollTimeout when all lists are fully synced', () {
      final sync = SlidingSync(
        client: http.Client(),
        connId: 'test',
        catchUpTimeout: const Duration(seconds: 2),
        longPollTimeout: const Duration(seconds: 30),
      );
      sync.addList(SlidingSyncList(
        name: 'rooms',
        syncMode: SyncMode.selective,
        initialRanges: [[0, 9]],
      ));

      // Selective lists become fullyLoaded after first response.
      sync.handleResponse(SlidingSyncResponse(
        pos: '1',
        lists: {'rooms': _listResponse(10, [0, 9])},
      ));

      expect(sync.isFullySynced, isTrue);
      final request = sync.buildRequest();
      expect(request.timeout, 30000);
    });

    test('switches from catchUp to longPoll as lists finish loading', () {
      final sync = SlidingSync(
        client: http.Client(),
        connId: 'test',
        catchUpTimeout: const Duration(seconds: 2),
        longPollTimeout: const Duration(seconds: 30),
      );
      sync.addList(SlidingSyncList(name: 'rooms', batchSize: 10));

      // Not yet synced — catchUp timeout.
      expect(sync.buildRequest().timeout, 2000);

      // Partially synced.
      sync.handleResponse(SlidingSyncResponse(
        pos: '1',
        lists: {'rooms': _listResponse(20, [0, 9])},
      ));
      expect(sync.isFullySynced, isFalse);
      expect(sync.buildRequest().timeout, 2000);

      // Fully synced.
      sync.handleResponse(SlidingSyncResponse(
        pos: '2',
        lists: {'rooms': _listResponse(20, [0, 19])},
      ));
      expect(sync.isFullySynced, isTrue);
      expect(sync.buildRequest().timeout, 30000);
    });
  });

  group('SlidingSync — isFullySynced', () {
    test('false when no lists', () {
      final sync = _createSync();
      expect(sync.isFullySynced, isFalse);
    });

    test('false when any list is not fully loaded', () {
      final sync = _createSync();
      sync.addList(SlidingSyncList(
        name: 'a',
        syncMode: SyncMode.selective,
        initialRanges: [[0, 9]],
      ));
      sync.addList(SlidingSyncList(name: 'b', batchSize: 10));

      // Only list 'a' responds.
      sync.handleResponse(SlidingSyncResponse(
        pos: '1',
        lists: {'a': _listResponse(10, [0, 9])},
      ));

      expect(sync.getList('a')!.loadingState, ListLoadingState.fullyLoaded);
      expect(sync.getList('b')!.loadingState, ListLoadingState.notLoaded);
      expect(sync.isFullySynced, isFalse);
    });

    test('true when all lists are fully loaded', () {
      final sync = _createSync();
      sync.addList(SlidingSyncList(
        name: 'a',
        syncMode: SyncMode.selective,
        initialRanges: [[0, 9]],
      ));
      sync.addList(SlidingSyncList(
        name: 'b',
        syncMode: SyncMode.selective,
        initialRanges: [[0, 4]],
      ));

      sync.handleResponse(SlidingSyncResponse(
        pos: '1',
        lists: {
          'a': _listResponse(10, [0, 9]),
          'b': _listResponse(5, [0, 4]),
        },
      ));

      expect(sync.isFullySynced, isTrue);
    });
  });

  group('SlidingSync — logging', () {
    group('formatRequestLog', () {
      test('includes pos, timeout, and conn_id', () {
        final sync = _createSync();
        final request = sync.buildRequest();
        final log = sync.formatRequestLog(request);

        expect(log, contains('>>> REQUEST'));
        expect(log, contains('pos=null'));
        expect(log, contains('timeout=2000ms'));
        expect(log, contains('conn_id=test'));
      });

      test('includes list ranges', () {
        final sync = _createSync();
        sync.addList(SlidingSyncList(name: 'rooms', batchSize: 10));

        final request = sync.buildRequest();
        final log = sync.formatRequestLog(request);

        expect(log, contains('list:rooms range=[0, 9]'));
      });

      test('includes subscriptions', () {
        final sync = _createSync();
        sync.subscribeToRooms(
          ['!a:ex.com'],
          const RoomSubscription(timelineLimit: 10),
        );

        final request = sync.buildRequest();
        final log = sync.formatRequestLog(request);

        expect(log, contains('subscriptions=[!a:ex.com]'));
      });

      test('includes extensions', () {
        final sync = _createSync();
        sync.enableExtension('e2ee');
        sync.enableExtension('typing');

        final request = sync.buildRequest();
        final log = sync.formatRequestLog(request);

        expect(log, contains('extensions=[e2ee, typing]'));
      });

      test('omits subscriptions and extensions when empty', () {
        final sync = _createSync();
        final request = sync.buildRequest();
        final log = sync.formatRequestLog(request);

        expect(log, isNot(contains('subscriptions=')));
        expect(log, isNot(contains('extensions=')));
      });

      test('shows pos after first response', () {
        final sync = _createSync();
        sync.handleResponse(const SlidingSyncResponse(pos: 'tok_42'));

        final request = sync.buildRequest();
        final log = sync.formatRequestLog(request);

        expect(log, contains('pos=tok_42'));
      });
    });

    group('formatResponseLog', () {
      test('includes pos', () {
        final sync = _createSync();
        const response = SlidingSyncResponse(pos: 'abc');
        final update = sync.handleResponse(response);
        final log = sync.formatResponseLog(response, update);

        expect(log, contains('<<< RESPONSE'));
        expect(log, contains('pos=abc'));
      });

      test('includes list count and ranges', () {
        final sync = _createSync();
        sync.addList(SlidingSyncList(name: 'rooms', batchSize: 10));

        final response = SlidingSyncResponse(
          pos: '1',
          lists: {'rooms': _listResponse(50, [0, 9])},
        );
        final update = sync.handleResponse(response);
        final log = sync.formatResponseLog(response, update);

        expect(log, contains('list:rooms count=50'));
      });

      test('logs room name and initial flag', () {
        final sync = _createSync();
        const response = SlidingSyncResponse(
          pos: '1',
          rooms: {
            '!a:ex.com': SlidingRoomResponse(name: 'General', initial: true),
          },
        );
        final update = sync.handleResponse(response);
        final log = sync.formatResponseLog(response, update);

        expect(log, contains('room:!a:ex.com'));
        expect(log, contains('name=General'));
        expect(log, contains('initial=true'));
      });

      test('logs timeline events', () {
        final sync = _createSync();
        final response = SlidingSyncResponse(
          pos: '1',
          rooms: {
            '!a:ex.com': SlidingRoomResponse(
              name: 'Chat',
              timeline: [
                {
                  'type': 'm.room.message',
                  'sender': '@alice:ex.com',
                  'event_id': '\$ev1',
                  'origin_server_ts': 1000,
                  'content': {'body': 'hello'},
                },
              ],
            ),
          },
        );
        final update = sync.handleResponse(response);
        final log = sync.formatResponseLog(response, update);

        expect(log, contains('timeline=1 events'));
        expect(log, contains('m.room.message from @alice:ex.com'));
      });

      test('logs required_state event types', () {
        final sync = _createSync();
        final response = SlidingSyncResponse(
          pos: '1',
          rooms: {
            '!a:ex.com': SlidingRoomResponse(
              requiredState: [
                <String, dynamic>{
                  'type': 'm.room.encryption',
                  'state_key': '',
                  'sender': '@bob:ex.com',
                  'event_id': '\$ev2',
                  'origin_server_ts': 1000,
                  'content': <String, dynamic>{},
                },
                <String, dynamic>{
                  'type': 'm.room.topic',
                  'state_key': '',
                  'sender': '@bob:ex.com',
                  'event_id': '\$ev3',
                  'origin_server_ts': 1000,
                  'content': <String, dynamic>{},
                },
              ],
            ),
          },
        );
        final update = sync.handleResponse(response);
        final log = sync.formatResponseLog(response, update);

        expect(log, contains('required_state=[m.room.encryption, m.room.topic]'));
      });

      test('logs notification counts', () {
        final sync = _createSync();
        const response = SlidingSyncResponse(
          pos: '1',
          rooms: {
            '!a:ex.com': SlidingRoomResponse(
              notificationCount: 5,
              highlightCount: 2,
            ),
          },
        );
        final update = sync.handleResponse(response);
        final log = sync.formatResponseLog(response, update);

        expect(log, contains('notifications=5'));
        expect(log, contains('highlights=2'));
      });

      test('logs invited rooms with invite_state', () {
        final sync = _createSync();
        final response = SlidingSyncResponse(
          pos: '1',
          rooms: {
            '!inv:ex.com': SlidingRoomResponse(
              inviteState: [
                {
                  'type': 'm.room.member',
                  'state_key': '@me:ex.com',
                  'sender': '@them:ex.com',
                  'content': {'membership': 'invite'},
                },
                {
                  'type': 'm.room.name',
                  'state_key': '',
                  'sender': '@them:ex.com',
                  'content': {'name': 'Secret Room'},
                },
              ],
            ),
          },
        );
        final update = sync.handleResponse(response);
        final log = sync.formatResponseLog(response, update);

        expect(log, contains('invited:!inv:ex.com'));
        expect(log, contains('invite_state=[m.room.member, m.room.name]'));
      });

      test('logs to_device extension', () {
        final sync = _createSync();
        final response = SlidingSyncResponse(
          pos: '1',
          extensions: {
            'to_device': {
              'next_batch': 'td_5',
              'events': [
                <String, dynamic>{
                  'type': 'm.room.encrypted',
                  'sender': '@a:ex.com',
                  'event_id': '\$td1',
                  'origin_server_ts': 1000,
                  'content': <String, dynamic>{},
                },
              ],
            },
          },
        );
        final update = sync.handleResponse(response);
        final log = sync.formatResponseLog(response, update);

        expect(log, contains('to_device: 1 events'));
        expect(log, contains('next_batch=td_5'));
      });

      test('includes loading state per list', () {
        final sync = _createSync();
        sync.addList(SlidingSyncList(name: 'rooms', batchSize: 10));

        final response = SlidingSyncResponse(
          pos: '1',
          lists: {'rooms': _listResponse(50, [0, 9])},
        );
        final update = sync.handleResponse(response);
        final log = sync.formatResponseLog(response, update);

        expect(log, contains('rooms:partiallyLoaded'));
      });

      test('shows FULLY SYNCED when all lists loaded', () {
        final sync = _createSync();
        sync.addList(SlidingSyncList(
          name: 'rooms',
          syncMode: SyncMode.selective,
          initialRanges: [[0, 9]],
        ));

        final response = SlidingSyncResponse(
          pos: '1',
          lists: {'rooms': _listResponse(10, [0, 9])},
        );
        final update = sync.handleResponse(response);
        final log = sync.formatResponseLog(response, update);

        expect(log, contains('[FULLY SYNCED]'));
      });

      test('omits FULLY SYNCED when not all lists loaded', () {
        final sync = _createSync();
        sync.addList(SlidingSyncList(name: 'rooms', batchSize: 10));

        final response = SlidingSyncResponse(
          pos: '1',
          lists: {'rooms': _listResponse(50, [0, 9])},
        );
        final update = sync.handleResponse(response);
        final log = sync.formatResponseLog(response, update);

        expect(log, isNot(contains('[FULLY SYNCED]')));
      });
    });
  });
}
