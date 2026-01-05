import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';

class DatabaseService {
  static Database? _db;
  final _uuid = const Uuid();

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    String path = join(await getDatabasesPath(), 'personal_notes.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE notes(
            id TEXT PRIMARY KEY, 
            title TEXT, 
            content TEXT, 
            created_at TEXT, 
            updated_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE reminders(
            id TEXT PRIMARY KEY, 
            note_id TEXT, 
            trigger_at TEXT, 
            is_completed INTEGER,
            FOREIGN KEY (note_id) REFERENCES notes (id) ON DELETE CASCADE
          )
        ''');
        // Add settings table here as well
      },
    );
  }

  // Example: Adding a note with a unique ID
  Future<void> createNote(String title, String content) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.insert('notes', {
      'id': _uuid.v4(), // Generates a unique ID like '550e8400-e29b...'
      'title': title,
      'content': content,
      'created_at': now,
      'updated_at': now,
    });
  }
}