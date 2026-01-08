class Note {
  final String id;
  final String title;
  final String content;
  final String createdAt;
  final int colorValue; // Store the color as an integer
  final String? categoryId; // For your future "Tabs" feature
  final String? audioUrl;
  final String? userId;

  Note({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    this.colorValue = 0xFFFFFFFF, // Default to White
    this.categoryId,
    this.audioUrl,
    this.userId,
  });

  // Convert a Note object into a Map (to save to SQLite)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'created_at': createdAt,
      'color_value': colorValue,
      'category_id': categoryId,
      'audio_url': audioUrl,
      'user_id': userId,
    };
  }

  // Convert a Map from SQLite into a Note object (to show in UI)
  factory Note.fromMap(Map<String, dynamic> map) {
    return Note(
      id: map['id'],
      title: map['title'],
      content: map['content'],
      createdAt: map['created_at'],
      colorValue: map['color_value'] ?? 0xFFFFFFFF,
      categoryId: map['category_id'],
      audioUrl: map['audio_url'],
      userId: map['user_id'],
    );
  }
}