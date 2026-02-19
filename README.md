# Sliding Sync (MSC4186) — Dart Reference Implementation

A minimal Dart implementation of the Matrix [Simplified Sliding Sync](https://github.com/matrix-org/matrix-spec-proposals/pull/4186) protocol, based on the architecture of [matrix-rust-sdk](https://github.com/matrix-org/matrix-rust-sdk).

This is a **learning/reference implementation** — not production-ready.

## Project Structure

```
sliding_sync/
├── pubspec.yaml
├── lib/
│   ├── sliding_sync.dart                # Barrel export (single import)
│   └── src/
│       ├── enums.dart                   # SyncMode, ListLoadingState
│       ├── exception.dart               # SlidingSyncException
│       ├── models/
│       │   ├── request.dart             # Request models (filter, list config, subscription, extensions)
│       │   ├── response.dart            # Response models (SyncOp, room response, list response)
│       │   └── update_summary.dart      # UpdateSummary
│       ├── sliding_sync_list.dart       # SlidingSyncList (window + mode logic)
│       └── sliding_sync.dart            # SlidingSync (main engine + syncOnce)
└── bin/
    └── example.dart                     # Usage example
```

## Usage

```dart
import 'dart:io';
import 'package:sliding_sync/sliding_sync.dart';

final httpClient = HttpClient();

final slidingSync = SlidingSync(
  homeserverUrl: 'https://matrix.example.com',
  accessToken: 'syt_your_token_here',
  httpClient: httpClient,
  catchUpTimeout: Duration(seconds: 2),   // fast polling while loading
  longPollTimeout: Duration(seconds: 30), // slow poll once fully synced
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

// Subscribe to a specific room for full updates.
slidingSync.subscribeToRooms(
  ['!room123:example.com'],
  const RoomSubscription(timelineLimit: 50),
);

// Enable extensions.
slidingSync.enableExtension('e2ee');
slidingSync.enableExtension('to_device');

// Single sync tick.
final update = await slidingSync.syncOnce();
print('Lists: ${update.lists}, Rooms: ${update.rooms}');

// Or run in a loop — automatically uses fast timeout during catch-up,
// then switches to long-poll once all lists are fully synced.
while (true) {
  try {
    final update = await slidingSync.syncOnce();
    print(update);
    if (slidingSync.isFullySynced) {
      print('Fully synced — now long-polling for updates.');
    }
  } on SlidingSyncException catch (e) {
    print('Sync error: ${e.message}');
    await Future.delayed(Duration(seconds: 1));
  }
}
```

## What is Sliding Sync?

Sliding Sync is the **3rd-generation sync mechanism** for Matrix, replacing the v2 `/sync` endpoint. The v2 endpoint scales **O(n)** with room count — accounts with thousands of rooms can take minutes for initial sync.

Sliding Sync uses a **sliding window**: clients specify which portion of their room list they want (e.g., rooms 0–20) and only receive data for those rooms. Performance is **O(1)** regardless of room count.

### v2 Sync vs Sliding Sync

| Aspect | v2 `/sync` | Sliding Sync |
|--------|-----------|--------------|
| Room data | ALL rooms every time | Only requested ranges |
| Scaling | O(n) with room count | O(1) |
| Initial sync | Minutes for large accounts | Near-instant |
| Bandwidth | Heavy | Minimal (deltas only) |
| State loading | All state, all rooms | Selective `required_state` |

## Core Concepts

### 1. Lists

Filtered room subsets with sliding window ranges. Each list has a sync mode:

- **Selective** — Fixed ranges, no auto-advancement (`[0, 9]`)
- **Paging** — Batch-by-batch: `[0, 19]`, then `[20, 39]`, then `[40, 59]`...
- **Growing** — Expanding window: `[0, 19]`, then `[0, 39]`, then `[0, 59]`...

### 2. Room Subscriptions

Explicit subscriptions to specific room IDs, independent of any list window. Useful when a user opens a room that needs real-time updates.

### 3. Extensions (disabled by default)

| Extension | Purpose |
|-----------|---------|
| `e2ee` | Encryption key management |
| `to_device` | Device-to-device messaging (key sharing) |
| `account_data` | Per-user settings, ignored users |
| `typing` | Typing indicators |
| `receipts` | Read receipts |

Enable all at once with `slidingSync.enableAllExtensions()`.

## List Loading States

```
NotLoaded → Preloaded (from cache)
    ↓           ↓
PartiallyLoaded ↔ FullyLoaded
```

## Protocol Details (MSC4186)

**Endpoint:** `POST /_matrix/client/unstable/org.matrix.msc4186/sync?pos=<token>&timeout=<ms>`

### Query Parameters

| Parameter | Description |
|-----------|-------------|
| `pos` | Position token from previous response (omitted on first request) |
| `timeout` | Long-polling duration in ms (2000 during catch-up, 30000 once synced) |

### Request Body (JSON)

| Field | Description |
|-------|-------------|
| `conn_id` | Connection identifier |
| `lists` | Map of list configurations (range, timeline_limit, required_state, filters) |
| `room_subscriptions` | Map of room IDs to subscription configs |
| `extensions` | Optional data requests (e2ee, to_device, etc.) |

### Response

| Field | Description |
|-------|-------------|
| `pos` | New position token for next request |
| `lists` | SYNC ops with room IDs per list |
| `rooms` | Map of room updates (timeline, state, `initial` flag) |
| `extensions` | Extension response data |

### Filters

- `is_dm` — Direct messages only
- `is_encrypted` — Encrypted rooms only
- `is_invited` — Invitations only
- `spaces` — Rooms in specific spaces
- `room_types` — Filter by room type

### Error Handling

- `M_UNKNOWN_POS` — Server expired the connection; client resets `pos` and retries from scratch
- Timeout — Long-poll expired; client re-sends immediately

## MSC3575 vs MSC4186

| | MSC3575 (Original) | MSC4186 (Simplified/Native) |
|---|---|---|
| **Status** | Deprecated (Jan 2025) | Current/Production |
| **Requires** | External sliding sync proxy | Native in Synapse v1.114+ |
| **Endpoint** | Proxy-based | `POST /_matrix/client/v4/sync` |
| **Room ordering** | Server-determined | Client-side sorting |

This implementation targets **MSC4186 only**.

## Sources

- [matrix-rust-sdk repo](https://github.com/matrix-org/matrix-rust-sdk)
- [MSC3575: Sliding Sync](https://github.com/matrix-org/matrix-spec-proposals/pull/3575)
- [MSC4186: Simplified Sliding Sync](https://github.com/matrix-org/matrix-spec-proposals/pull/4186)
- [matrix-rust-sdk sliding_sync docs](https://matrix-org.github.io/matrix-rust-sdk/matrix_sdk/sliding_sync/index.html)
