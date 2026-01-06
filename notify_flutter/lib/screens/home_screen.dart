import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../services/database_service.dart';
import '../models/note_model.dart';
import '../models/category_model.dart';
import 'package:uuid/uuid.dart';
import 'note_editor_screen.dart';
import 'dart:async'; 
import 'dart:io'; // Required for Platform check
import 'package:supabase_flutter/supabase_flutter.dart'; 
import '../services/notification_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Note> _notes = [];
  bool _isLoading = true;
  late StreamSubscription<List<Map<String, dynamic>>> _syncStream;
  String? _filterCategoryId; // Null means "Show All"
  List<Category> _drawerCategories = [];

  @override
  void initState() {
    super.initState();
    _initialSync();
    _loadDrawerCategories();
    _setupRealtimeSync();
  }

  void _setupRealtimeSync() {
    // 1. Listen for Note changes
    _syncStream = Supabase.instance.client
        .from('notes')
        .stream(primaryKey: ['id'])
        .order('created_at')
        .listen((List<Map<String, dynamic>> data) async {
          await DatabaseService.instance.syncFromCloud();
          _refreshNotes();
        });

    Supabase.instance.client
      .from('categories')
      .stream(primaryKey: ['id'])
      .listen((data) {
        _loadDrawerCategories(); // <--- Placement #2
      });

    // 2. Listen for Reminders and trigger local notifications
    Supabase.instance.client
      .from('reminders')
      .stream(primaryKey: ['id'])
      .listen((List<Map<String, dynamic>> data) async {
        // Sync local DB first so we have the data
        await DatabaseService.instance.syncFromCloud();
        
        for (var rem in data) {
          DateTime time = DateTime.parse(rem['reminder_time']);
          
          // Only schedule if it's in the future
          if (time.isAfter(DateTime.now())) {
            NotificationService().scheduleNotification(
              // Convert UUID string to an integer ID for the notification engine
              rem['id'].toString(), 
              "Note Reminder", 
              time
            );
          }
        }
      });
  }

  @override
  void dispose() {
    _syncStream.cancel(); 
    super.dispose();
  }

  Future<void> _initialSync() async {
    try {
      await DatabaseService.instance.syncFromCloud();
    } catch (e) {
      print("Initial sync failed: $e");
    }
    _refreshNotes();
  }

  Future<void> _refreshNotes() async {
    final db = await DatabaseService.instance.database;
    List<Map<String, dynamic>> result;
    
    if (_filterCategoryId == null) {
      result = await db.query('notes', orderBy: 'created_at DESC');
    } else {
      result = await db.query(
        'notes', 
        where: 'category_id = ?', 
        whereArgs: [_filterCategoryId], 
        orderBy: 'created_at DESC'
      );
    }

    setState(() {
      _notes = result.map((json) => Note.fromMap(json)).toList();
      _isLoading = false;
    });
  }

@override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Notes')),
      drawer: _buildDrawer(), // Clean and readable
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notes.isEmpty
              ? const Center(child: Text('No notes yet. Tap + to add one!'))
              : _buildNoteList(), // Clean and readable
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const NoteEditorScreen()),
          );
          _refreshNotes(); 
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  // --- HELPER: DRAWER ---
  Widget _buildDrawer() {
    return Drawer(
      child: Column(
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.blueGrey),
            child: Center(child: Text('TABS', style: TextStyle(color: Colors.white, fontSize: 24))),
          ),
          ListTile(
            leading: const Icon(Icons.all_inclusive),
            title: const Text('All Notes'),
            onTap: () {
              setState(() => _filterCategoryId = null);
              _refreshNotes();
              Navigator.pop(context);
            },
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _drawerCategories.length,
              itemBuilder: (context, index) {
                final cat = _drawerCategories[index];
                return ListTile(
                  leading: Icon(Icons.label, color: Color(cat.colorValue)),
                  title: Text(cat.name),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () async {
                      await DatabaseService.instance.deleteCategory(cat.id);
                      _loadDrawerCategories();
                    },
                  ),
                  onTap: () {
                    setState(() => _filterCategoryId = cat.id);
                    _refreshNotes();
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Create New Tab'),
            onTap: () {
              Navigator.pop(context);
              _showCreateCategoryDialog();
            },
          ),
        ],
      ),
    );
  }

  // --- HELPER: NOTE LIST ---
  Widget _buildNoteList() {
    return ListView.builder(
      itemCount: _notes.length,
      itemBuilder: (context, index) {
        final note = _notes[index];
        
        // Find the color of the category assigned to this note
        Color categoryColor = Colors.transparent;
        if (note.categoryId != null) {
          try {
            categoryColor = Color(_drawerCategories
                .firstWhere((c) => c.id == note.categoryId)
                .colorValue);
          } catch (_) {
            categoryColor = Colors.transparent;
          }
        }

        return Card(
          color: Color(note.colorValue),
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Stack( // <--- This is where Part C (the badge) lives
            children: [
              ListTile(
                title: Text(note.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(note.content),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _confirmDelete(note.id),
                ),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => NoteEditorScreen(note: note)),
                  );
                  _refreshNotes();
                },
              ),
              // THE CATEGORY BADGE (Top Right Corner)
              if (note.categoryId != null)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: categoryColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(String id) async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Note?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ?? false;

    if (confirm) {
      await DatabaseService.instance.deleteNote(id);
      _refreshNotes();
    }
  }

  void _showCreateCategoryDialog() {
    final TextEditingController _categoryController = TextEditingController();
    Color _tempColor = Colors.grey; // Default color for the new tab

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder( // Needed to update color inside the dialog
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New Tab'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _categoryController,
                decoration: const InputDecoration(hintText: 'Category Name'),
              ),
              const SizedBox(height: 20),
              const Text("Pick Tab Color:"),
              const SizedBox(height: 10),
              // A simple horizontal scroll of colors
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: BlockPicker(
                  pickerColor: _tempColor,
                  onColorChanged: (color) => setDialogState(() => _tempColor = color),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (_categoryController.text.isNotEmpty) {
                  final newCat = Category(
                    id: const Uuid().v4(),
                    name: _categoryController.text,
                    colorValue: _tempColor.value,
                  );
                  await DatabaseService.instance.createCategory(newCat);
                  _loadDrawerCategories(); // Refresh the list
                  Navigator.pop(context);
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  //load categories for drawer
  Future<void> _loadDrawerCategories() async {
    final cats = await DatabaseService.instance.readCategories();
    setState(() {
      _drawerCategories = cats;
    });
  }
}