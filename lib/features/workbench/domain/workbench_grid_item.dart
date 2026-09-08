import '../data/workbench_models.dart';

/// Supported types of items in the 2D workbench grid.
enum WorkbenchGridItemType {
  /// Standard single unit app shortcut ($1 \times 1$).
  app,

  /// Full or partial width banner/announcement ($4 \times 1$, $4 \times 2$, etc.).
  banner,

  /// Functional widget card ($2 \times 1$ capsule, $2 \times 2$ dashboard card, etc.).
  cardWidget,

  /// Folder grouping multiple applications ($1 \times 1$ or $2 \times 2$).
  folder,

  /// Custom extensible widget.
  custom,
}

/// A 2D rectangular coordinate and span within the 4-column grid.
class GridRect {
  const GridRect({
    required this.x,
    required this.y,
    required this.spanX,
    required this.spanY,
  }) : assert(x >= 0 && x <= 3, 'x must be between 0 and 3'),
       assert(spanX >= 1 && spanX <= 4, 'spanX must be between 1 and 4'),
       assert(x + spanX <= 4, 'Item bounds (x + spanX) cannot exceed 4 columns'),
       assert(y >= 0, 'y must be non-negative'),
       assert(spanY >= 1, 'spanY must be at least 1');

  final int x;
  final int y;
  final int spanX;
  final int spanY;

  int get left => x;
  int get right => x + spanX;
  int get top => y;
  int get bottom => y + spanY;

  /// Whether this rectangle intersects with [other].
  bool intersects(GridRect other) {
    return left < other.right &&
        right > other.left &&
        top < other.bottom &&
        bottom > other.top;
  }

  /// Whether this rectangle contains cell coordinate ([cx], [cy]).
  bool containsCell(int cx, int cy) {
    return cx >= left && cx < right && cy >= top && cy < bottom;
  }

  GridRect copyWith({int? x, int? y, int? spanX, int? spanY}) {
    return GridRect(
      x: x ?? this.x,
      y: y ?? this.y,
      spanX: spanX ?? this.spanX,
      spanY: spanY ?? this.spanY,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GridRect &&
          runtimeType == other.runtimeType &&
          x == other.x &&
          y == other.y &&
          spanX == other.spanX &&
          spanY == other.spanY;

  @override
  int get hashCode => Object.hash(x, y, spanX, spanY);

  @override
  String toString() => 'GridRect(x: $x, y: $y, spanX: $spanX, spanY: $spanY)';
}

/// An individual item positioned on the 4-column workbench grid.
class WorkbenchGridItem {
  const WorkbenchGridItem({
    required this.id,
    required this.title,
    required this.type,
    required this.x,
    required this.y,
    this.subtitle,
    this.badge,
    this.spanX = 1,
    this.spanY = 1,
    this.edgeToEdge = false,
    this.appPayload,
    this.children,
    this.extra,
  }) : assert(x >= 0 && x <= 3, 'x must be between 0 and 3'),
       assert(spanX >= 1 && spanX <= 4, 'spanX must be between 1 and 4'),
       assert(x + spanX <= 4, 'Item bounds (x + spanX) cannot exceed 4 columns'),
       assert(y >= 0, 'y must be non-negative'),
       assert(spanY >= 1, 'spanY must be at least 1');

  final String id;
  final String title;
  final String? subtitle;
  final String? badge;
  final WorkbenchGridItemType type;
  final int x;
  final int y;
  final int spanX;
  final int spanY;

  /// Whether this item (usually 4 columns wide) expands to the viewport edges
  /// without horizontal padding or gutters.
  final bool edgeToEdge;

  /// Bound MiniApp or web application details (if type == app).
  final WorkbenchApp? appPayload;

  /// Nested child items if this item represents a folder.
  final List<WorkbenchGridItem>? children;

  /// Arbitrary extra properties (e.g. icon name, color, banner image, stats).
  final Map<String, dynamic>? extra;

  /// Geometric representation of this item in the 4-column grid.
  GridRect get rect => GridRect(x: x, y: y, spanX: spanX, spanY: spanY);

  WorkbenchGridItem copyWith({
    String? id,
    String? title,
    String? subtitle,
    String? badge,
    WorkbenchGridItemType? type,
    int? x,
    int? y,
    int? spanX,
    int? spanY,
    bool? edgeToEdge,
    WorkbenchApp? appPayload,
    List<WorkbenchGridItem>? children,
    Map<String, dynamic>? extra,
  }) {
    return WorkbenchGridItem(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      badge: badge ?? this.badge,
      type: type ?? this.type,
      x: x ?? this.x,
      y: y ?? this.y,
      spanX: spanX ?? this.spanX,
      spanY: spanY ?? this.spanY,
      edgeToEdge: edgeToEdge ?? this.edgeToEdge,
      appPayload: appPayload ?? this.appPayload,
      children: children ?? this.children,
      extra: extra ?? this.extra,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    if (subtitle != null) 'subtitle': subtitle,
    if (badge != null) 'badge': badge,
    'type': type.name,
    'x': x,
    'y': y,
    'spanX': spanX,
    'spanY': spanY,
    'edgeToEdge': edgeToEdge,
    if (appPayload != null) 'appPayload': appPayload!.toJson(),
    if (children != null)
      'children': children!.map((c) => c.toJson()).toList(),
    if (extra != null) 'extra': extra,
  };

  factory WorkbenchGridItem.fromJson(Map<String, dynamic> json) {
    return WorkbenchGridItem(
      id: json['id'] as String,
      title: json['title'] as String,
      subtitle: json['subtitle'] as String?,
      badge: json['badge'] as String?,
      type: WorkbenchGridItemType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => WorkbenchGridItemType.app,
      ),
      x: json['x'] as int? ?? 0,
      y: json['y'] as int? ?? 0,
      spanX: json['spanX'] as int? ?? 1,
      spanY: json['spanY'] as int? ?? 1,
      edgeToEdge: json['edgeToEdge'] as bool? ?? false,
      appPayload:
          json['appPayload'] != null
              ? WorkbenchApp.fromJson(
                json['appPayload'] as Map<String, dynamic>,
              )
              : null,
      children:
          json['children'] != null
              ? (json['children'] as List)
                  .map(
                    (c) => WorkbenchGridItem.fromJson(c as Map<String, dynamic>),
                  )
                  .toList()
              : null,
      extra:
          json['extra'] != null
              ? Map<String, dynamic>.from(json['extra'] as Map)
              : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkbenchGridItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          subtitle == other.subtitle &&
          badge == other.badge &&
          type == other.type &&
          x == other.x &&
          y == other.y &&
          spanX == other.spanX &&
          spanY == other.spanY &&
          edgeToEdge == other.edgeToEdge;

  @override
  int get hashCode => Object.hash(id, title, subtitle, badge, type, x, y, spanX, spanY, edgeToEdge);

  @override
  String toString() =>
      'WorkbenchGridItem(id: $id, title: $title, subtitle: $subtitle, badge: $badge, type: $type, x: $x, y: $y, spanX: $spanX, spanY: $spanY)';
}
