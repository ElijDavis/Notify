import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/note_model.dart'; 
import '../models/category_model.dart';
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
      version: 3, // Bumping to 3 for Categories and Visual Polish
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  // Handles existing users transitioning between versions
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
    if (oldVersion < 3) {
      // Add visual polish columns to notes
      await db.execute('ALTER TABLE notes ADD COLUMN color_value INTEGER DEFAULT 4294967295');
      await db.execute('ALTER TABLE notes ADD COLUMN category_id TEXT');

      // Create new Knowledge Base tables
      await db.execute('''
        CREATE TABLE categories (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          color_value INTEGER,
          parent_category_id TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE note_categories (
          id TEXT PRIMARY KEY,
          note_id TEXT,
          category_id TEXT,
          FOREIGN KEY (note_id) REFERENCES notes (id) ON DELETE CASCADE,
          FOREIGN KEY (category_id) REFERENCES categories (id) ON DELETE CASCADE
        )
      ''');
    }
  }

  // Sets up the database from scratch for new installs
  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE notes (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL,
        color_value INTEGER DEFAULT 4294967295,
        category_id TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE reminders (
        id TEXT PRIMARY KEY,
        note_id TEXT,
        reminder_time TEXT,
        is_completed INTEGER,
        FOREIGN KEY (note_id) REFERENCES notes (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        color_value INTEGER,
        parent_category_id TEXT
      )
    ''');
  }

  // --- SYNC & CRUD FUNCTIONS ---

  Future<void> createNote(Note note) async {
    final db = await instance.database;
    final user = Supabase.instance.client.auth.currentUser;

    await db.insert('notes', note.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

    if (user != null) {
      try {
        await Supabase.instance.client.from('notes').upsert({
          ...note.toMap(),
          'user_id': user.id,
        });
        print("Sync Successful!");
      } catch (e) {
        print("Cloud sync failed: $e");
      }
    }
  }

  Future<List<Note>> readAllNotes() async {
    final db = await instance.database;
    final result = await db.query('notes', orderBy: 'created_at DESC');
    return result.map((json) => Note.fromMap(json)).toList();
  }

  Future<void> deleteNote(String id) async {
    final db = await instance.database;
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
    await Supabase.instance.client.from('notes').delete().eq('id', id);
  }

  Future<void> syncFromCloud() async {
    final supabase = Supabase.instance.client;
    final db = await instance.database;

    final cloudNotes = await supabase.from('notes').select();
    for (var noteData in cloudNotes) {
      await db.insert('notes', {
        'id': noteData['id'],
        'title': noteData['title'],
        'content': noteData['content'],
        'created_at': noteData['created_at'],
        'color_value': noteData['color_value'],
        'category_id': noteData['category_id'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    final cloudReminders = await supabase.from('reminders').select();
    for (var remData in cloudReminders) {
      await db.insert('reminders', {
        'id': remData['id'],
        'note_id': remData['note_id'],
        'reminder_time': remData['reminder_time'],
        'is_completed': remData['is_completed'] ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> saveReminder(String id, String noteId, DateTime time) async {
    final db = await instance.database;
    final user = Supabase.instance.client.auth.currentUser;

    await db.insert('reminders', {
      'id': id,
      'note_id': noteId,
      'reminder_time': time.toIso8601String(),
      'is_completed': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    if (user != null) {
      try {
        await Supabase.instance.client.from('reminders').upsert({
          'id': id,
          'note_id': noteId,
          'reminder_time': time.toIso8601String(),
          'is_completed': false,
          'user_id': user.id,
        });
        print("Reminder synced to cloud!");
      } catch (e) {
        print("Reminder cloud sync failed: $e");
      }
    }
  }

  //category functions

  // 1. Create/Sync Category
  Future<void> createCategory(Category category) async {
    final db = await instance.database;
    final user = Supabase.instance.client.auth.currentUser;

    await db.insert('categories', category.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

    if (user != null) {
      try {
        await Supabase.instance.client.from('categories').upsert({
          ...category.toMap(),
          'user_id': user.id,
        });
      } catch (e) {
        print("Category sync failed: $e");
      }
    }
  }

  // 2. Read Categories
  Future<List<Category>> readCategories() async {
    final db = await instance.database;
    final result = await db.query('categories', orderBy: 'name ASC');
    return result.map((json) => Category.fromMap(json)).toList();
  }

  Future<void> deleteCategory(String id) async {
    final db = await instance.database;
    await db.delete('categories', where: 'id = ?', whereArgs: [id]);
    await Supabase.instance.client.from('categories').delete().eq('id', id);
  }
}