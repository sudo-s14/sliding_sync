/// Usage example for the sliding sync implementation.

import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:sliding_sync/sliding_sync.dart';

Future<void> main() async {
  // Configure sync state early — client is available before login.
  final slidingSync = SlidingSyncBuilder()
    .setClient(http.Client())
    .setConnId('main')
    .addList(SlidingSyncList(
      name: 'all-rooms',
      syncMode: SyncMode.growing,
      batchSize: 20,
      timelineLimit: 5,
      requiredState: [
        ['m.room.encryption', ''],
        ['m.room.topic', ''],
      ],
    ))
    .addList(SlidingSyncList(
      name: 'invites',
      syncMode: SyncMode.selective,
      timelineLimit: 0,
      filters: const SlidingRoomFilter(isInvited: true),
      initialRanges: [[0, 9]],
    ))
    .subscribeToRooms(
      ['!room123:example.com'],
      const RoomSubscription(
        timelineLimit: 50,
        requiredState: [['m.room.topic', '']],
      ),
    )
    .enableExtension('e2ee')
    .enableExtension('to_device')
    .build();

  // Connection details — available after login.
  final homeserverUrl = Uri.parse('https://matrix.example.com');
  const accessToken = 'syt_your_token_here';
  const userId = '@user:example.com';

  // Run the sync loop — pass connection details at call time.
  while (true) {
    try {
      final update = await slidingSync.syncOnce(
        homeserverUrl: homeserverUrl,
        accessToken: accessToken,
        userId: userId,
        catchUpTimeout: const Duration(seconds: 2),
        longPollTimeout: const Duration(seconds: 30),
      );
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
