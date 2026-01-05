import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/note_model.dart'; // Import your model
import 'package:supabase_flutter/supabase_flutter.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('notes.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path, 
      version: 2, 
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE reminders (
          id TEXT PRIMARY KEY,
          note_id TEXT,
          reminder_time TEXT,
          is_completed INTEGER,
          FOREIGN KEY (note_id) REFERENCES notes (id) ON DELETE CASCADE
        )
      ''');
    }
  }

  Future _createDB(Database db, int version) async {
    // Create Notes Table
    await db.execute('''
      CREATE TABLE notes (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // Create Reminders Table
    await db.execute('''
      CREATE TABLE reminders (
        id TEXT PRIMARY KEY,
        note_id TEXT,
        reminder_time TEXT,
        is_completed INTEGER,
        FOREIGN KEY (note_id) REFERENCES notes (id) ON DELETE CASCADE
      )
    ''');
  }

  // --- NEW FUNCTIONS TO INTERACT WITH NOTES ---

  // 1. Save a Note
  // Change your createNote function to this:
  /*Future<void> createNote(Note note) async {
    final db = await instance.database;
    
    // conflictAlgorithm: ConflictAlgorithm.replace is the magic line.
    // It handles both NEW notes and EDITED notes automatically.
    await db.insert(
      'notes', 
      note.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace, 
    );
  }*/
  final _supabase = Supabase.instance.client;

  Future<void> createNote(Note note) async {
    final db = await instance.database;
    
    // 1. Save locally first (Instant feedback for the user)
    await db.insert(
      'notes', 
      note.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace, 
    );

    // 2. Sync to the Cloud (Supabase)
    try {
      await _supabase.from('notes').upsert({
        'id': note.id,
        'title': note.title,
        'content': note.content,
        'created_at': note.createdAt,
      });
      print("Sync Successful!");
    } catch (e) {
      // If there's no internet, the app keeps running locally.
      // We can handle re-syncing later.
      print("Sync Failed: $e");
    }
  }

  // 2. Get All Notes
  Future<List<Note>> readAllNotes() async {
    final db = await instance.database;
    final result = await db.query('notes', orderBy: 'created_at DESC');

    return result.map((json) => Note.fromMap(json)).toList();
  }

  // 3. Delete a Note
  Future<int> deleteNote(String id) async {
    final db = await instance.database;
    return await db.delete(
      'notes',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}