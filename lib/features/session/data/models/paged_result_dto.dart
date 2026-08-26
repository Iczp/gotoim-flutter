class PagedResultDto<T> {
  const PagedResultDto({required this.items, required this.totalCount});

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
    return PagedResultDto<T>(
      items: items,
      totalCount:
          rawCount is num
              ? rawCount.toInt()
              : int.tryParse('$rawCount') ?? items.length,
    );
  }

  final List<T> items;
  final int totalCount;
}
