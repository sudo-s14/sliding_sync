/// Summary of changes after a sync iteration.

class UpdateSummary {
  final List<String> lists;
  final List<String> rooms;

  const UpdateSummary({this.lists = const [], this.rooms = const []});

  @override
  String toString() => 'UpdateSummary(lists: $lists, rooms: $rooms)';
}
