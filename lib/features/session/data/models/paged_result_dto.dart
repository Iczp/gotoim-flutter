class PagedResultDto<T> {
  const PagedResultDto({
    required this.items,
    required this.totalCount,
    this.hasMore,
    this.nextCursorTicks,
    this.nextCursorId,
  });

  factory PagedResultDto.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic> json) itemFromJson,
  ) {
    final rawItems = json['items'];
    final items =
        rawItems is List
            ? rawItems
                .whereType<Map>()
                .map((item) => itemFromJson(item.cast<String, dynamic>()))
                .toList(growable: false)
            : List<T>.empty(growable: false);
    final rawCount = json['totalCount'];
    final extra = json['extra'];
    final nextCursor = extra is Map && extra['nextCursor'] is Map
        ? (extra['nextCursor'] as Map)
        : null;
    final rawHasMore = extra is Map ? extra['hasMore'] : null;
    final cursorTicks = nextCursor != null
        ? (nextCursor['cursorScore'] is num
            ? (nextCursor['cursorScore'] as num).toInt()
            : int.tryParse('${nextCursor['cursorScore']}'))
        : (extra is Map && extra['nextCursorTicks'] is num
            ? (extra['nextCursorTicks'] as num).toInt()
            : null);
    final cursorId = nextCursor != null
        ? nextCursor['cursorId']?.toString()
        : (extra is Map ? extra['nextCursorId']?.toString() : null);
    return PagedResultDto<T>(
      items: items,
      totalCount:
          rawCount is num
              ? rawCount.toInt()
              : int.tryParse('$rawCount') ?? items.length,
      hasMore: rawHasMore is bool ? rawHasMore : null,
      nextCursorTicks: cursorTicks,
      nextCursorId: cursorId,
    );
  }

  final List<T> items;
  final int totalCount;
  final bool? hasMore;
  final int? nextCursorTicks;
  final String? nextCursorId;
}
