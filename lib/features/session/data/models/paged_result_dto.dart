class PagedResultDto<T> {
  const PagedResultDto({
    required this.items,
    required this.totalCount,
    this.hasMore,
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
    final rawHasMore = extra is Map ? extra['hasMore'] : null;
    return PagedResultDto<T>(
      items: items,
      totalCount:
          rawCount is num
              ? rawCount.toInt()
              : int.tryParse('$rawCount') ?? items.length,
      hasMore: rawHasMore is bool ? rawHasMore : null,
    );
  }

  final List<T> items;
  final int totalCount;
  final bool? hasMore;
}
