import 'package:http/http.dart' as http;
import 'package:sliding_sync/sliding_sync.dart';
import 'package:test/test.dart';

void main() {
  test('growing mode full flow: buildRequest + handleResponse for 4 ticks', () {
    final sync = SlidingSync(
      homeserverUrl: Uri.parse('https://example.com'),
      accessToken: 'token',
      client: http.Client(),
    );
    sync.addList(SlidingSyncList(
      name: 'rooms',
      syncMode: SyncMode.growing,
      batchSize: 10,
    ));

    // ── Tick 1 ──
    var request = sync.buildRequest();
    var listConfig = request.lists['rooms']!;
    print('Tick 1 request range: ${listConfig.range}');
    expect(listConfig.range, [0, 9], reason: 'Tick 1: initial range');

    // Server responds with [0, 9], 50 total.
    sync.handleResponse(SlidingSyncResponse(
      pos: '1',
      lists: {
        'rooms': SyncListResponse(
          count: 50,
          ops: [SyncOp(range: [0, 9])],
        ),
      },
    ));
    print('After tick 1: ranges=${sync.getList("rooms")!.ranges}, state=${sync.getList("rooms")!.loadingState}');

    // ── Tick 2 ──
    request = sync.buildRequest();
    listConfig = request.lists['rooms']!;
    print('Tick 2 request range: ${listConfig.range}');
    expect(listConfig.range, [0, 19], reason: 'Tick 2: grown by batchSize');

    sync.handleResponse(SlidingSyncResponse(
      pos: '2',
      lists: {
        'rooms': SyncListResponse(
          count: 50,
          ops: [SyncOp(range: [0, 19])],
        ),
      },
    ));
    print('After tick 2: ranges=${sync.getList("rooms")!.ranges}, state=${sync.getList("rooms")!.loadingState}');

    // ── Tick 3 ──
    request = sync.buildRequest();
    listConfig = request.lists['rooms']!;
    print('Tick 3 request range: ${listConfig.range}');
    expect(listConfig.range, [0, 29], reason: 'Tick 3: grown by batchSize');

    sync.handleResponse(SlidingSyncResponse(
      pos: '3',
      lists: {
        'rooms': SyncListResponse(
          count: 50,
          ops: [SyncOp(range: [0, 29])],
        ),
      },
    ));
    print('After tick 3: ranges=${sync.getList("rooms")!.ranges}, state=${sync.getList("rooms")!.loadingState}');

    // ── Tick 4 ──
    request = sync.buildRequest();
    listConfig = request.lists['rooms']!;
    print('Tick 4 request range: ${listConfig.range}');
    expect(listConfig.range, [0, 39], reason: 'Tick 4: grown by batchSize');

    sync.handleResponse(SlidingSyncResponse(
      pos: '4',
      lists: {
        'rooms': SyncListResponse(
          count: 50,
          ops: [SyncOp(range: [0, 39])],
        ),
      },
    ));
    print('After tick 4: ranges=${sync.getList("rooms")!.ranges}, state=${sync.getList("rooms")!.loadingState}');

    // ── Tick 5 ──
    request = sync.buildRequest();
    listConfig = request.lists['rooms']!;
    print('Tick 5 request range: ${listConfig.range}');
    expect(listConfig.range, [0, 49], reason: 'Tick 5: final batch');

    sync.handleResponse(SlidingSyncResponse(
      pos: '5',
      lists: {
        'rooms': SyncListResponse(
          count: 50,
          ops: [SyncOp(range: [0, 49])],
        ),
      },
    ));
    print('After tick 5: ranges=${sync.getList("rooms")!.ranges}, state=${sync.getList("rooms")!.loadingState}');
    expect(sync.getList('rooms')!.loadingState, ListLoadingState.fullyLoaded);
    expect(sync.isFullySynced, isTrue);
  });
}
