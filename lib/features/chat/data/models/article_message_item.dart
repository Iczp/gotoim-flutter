/// Display snapshot of one article; reading uses its public URL.
class ArticleMessageItem {
  const ArticleMessageItem({
    required this.title,
    this.description = '',
    this.coverImageUrl = '',
    this.author = '',
    this.originalUrl = '',
  });

  factory ArticleMessageItem.fromJson(Map<dynamic, dynamic> json) {
    String text(String key, [String? fallback]) =>
        (json[key] ?? (fallback == null ? null : json[fallback]))
            ?.toString()
            .trim() ??
        '';
    return ArticleMessageItem(
      title: text('title'),
      description: text('description', 'summary'),
      coverImageUrl: text('coverImageUrl', 'coverUrl'),
      author: text('author'),
      originalUrl: text('originalUrl', 'url'),
    );
  }

  final String title;
  final String description;
  final String coverImageUrl;
  final String author;
  final String originalUrl;

  /// Ordered groups and legacy single-article messages share this parser.
  static List<ArticleMessageItem> fromContent(Object? content) {
    final Object? source = content is Map
        ? (content['items'] ?? content['articleList'] ?? content)
        : content;
    final values = source is List ? source : <Object?>[source];
    return List<ArticleMessageItem>.unmodifiable(
      values
          .whereType<Map>()
          .map(ArticleMessageItem.fromJson)
          .where(
            (item) => item.title.isNotEmpty || item.originalUrl.isNotEmpty,
          ),
    );
  }

  Map<String, String> toJson() => {
    'title': title,
    'description': description,
    'coverImageUrl': coverImageUrl,
    'author': author,
    'originalUrl': originalUrl,
  };
}
