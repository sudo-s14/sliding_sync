/// Usage example for the sliding sync implementation.

import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:sliding_sync/sliding_sync.dart';

Future<void> main() async {
  final client = http.Client();

  final slidingSync = SlidingSync(
    homeserverUrl: Uri.parse('https://matrix.example.com'),
    accessToken: 'syt_your_token_here',
    client: client,
    // Fast polling while catching up, slow long-poll once fully synced.
    catchUpTimeout: const Duration(seconds: 2),
    longPollTimeout: const Duration(seconds: 30),
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
  // During catch-up: requests use 2s timeout for fast batching.
  // Once fully synced: requests use 30s timeout for long-polling.
  while (true) {
    try {
      final update = await slidingSync.syncOnce();
      print(update);

      if (slidingSync.isFullySynced) {
        print('Fully synced — now long-polling for updates.');
      }
    } on SlidingSyncException catch (e) {
      print('[SlidingSync] ${e.message}');
      await Future.delayed(const Duration(seconds: 1));
    } on TimeoutException {
      // Long-poll timed out — retry immediately.
      continue;
    } catch (e) {
      print('[SlidingSync] Unexpected error: $e');
      await Future.delayed(const Duration(seconds: 5));
    }
  }
}
