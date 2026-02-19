/// Usage example for the sliding sync implementation.

import 'dart:io';

import 'package:sliding_sync/sliding_sync.dart';

Future<void> main() async {
  final httpClient = HttpClient();

  final slidingSync = SlidingSync(
    homeserverUrl: 'https://matrix.example.com',
    accessToken: 'syt_your_token_here',
    httpClient: httpClient,
  );

  // Add a growing list that fetches 20 rooms at a time.
  slidingSync.addList(SlidingSyncList(
    name: 'all-rooms',
    syncMode: SyncMode.growing,
    batchSize: 20,
    timelineLimit: 5,
    requiredState: [
      ['m.room.encryption', ''],
      ['m.room.topic', ''],
    ],
  ));

  // Add a selective list for invites only.
  slidingSync.addList(SlidingSyncList(
    name: 'invites',
    syncMode: SyncMode.selective,
    timelineLimit: 0,
    filters: const SlidingRoomFilter(isInvited: true),
    initialRanges: [[0, 9]],
  ));

  // Subscribe to a specific room for full updates.
  slidingSync.subscribeToRooms(
    ['!room123:example.com'],
    const RoomSubscription(
      timelineLimit: 50,
      requiredState: [['m.room.topic', '']],
    ),
  );

  // Enable E2EE + to-device extensions.
  slidingSync.enableExtension('e2ee');
  slidingSync.enableExtension('to_device');

  // Run the sync loop.
  await for (final update in slidingSync.sync()) {
    print(update);

    // Example: stop after fully loading the all-rooms list.
    final allRooms = slidingSync.getList('all-rooms');
    if (allRooms?.loadingState == ListLoadingState.fullyLoaded) {
      print(
        'All rooms loaded (${allRooms!.serverRoomCount} total). Stopping.',
      );
      slidingSync.stop();
    }
  }
}
