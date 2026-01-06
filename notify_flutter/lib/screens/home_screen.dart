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
import 'package:share_plus/share_plus.dart';

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
  List<Note> _allNotesForCounting = [];

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
    
    // 1. Get EVERY note for the counters
    final allData = await db.query('notes');
    _allNotesForCounting = allData.map((json) => Note.fromMap(json)).toList();

    // 2. Get FILTERED notes for the UI
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

  int _getNoteCount(String? categoryId) {
    if (categoryId == null) return _allNotesForCounting.length;
    return _allNotesForCounting.where((n) => n.categoryId == categoryId).length;
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
    // Separate main categories from subcategories
    final mainCategories = _drawerCategories.where((c) => c.parentCategoryId == null).toList();

    return Drawer(
      child: Column(
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.blueGrey),
            child: Center(child: Text('TABS', style: TextStyle(color: Colors.white, fontSize: 24))),
          ),
          ListTile(//All Notes Tile
            leading: const Icon(Icons.all_inclusive),
            title: const Text('All Notes'),
            trailing: Text('${_getNoteCount(null)}', 
              style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            onTap: () {
              setState(() => _filterCategoryId = null);
              _refreshNotes();
              Navigator.pop(context);
            },
          ),
          Expanded(
            child: ListView(
              children: mainCategories.map((parent) {
                // Find children for this parent
                final children = _drawerCategories.where((c) => c.parentCategoryId == parent.id).toList();

                return Column(
                  children: [
                    // Parent Tile
                    ListTile(
                      leading: Icon(Icons.folder, color: Color(parent.colorValue)),
                      title: Text(parent.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      trailing: SizedBox(
                        width: 80, // Gives enough room for both the number and the icon
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text('${_getNoteCount(parent.id)}', 
                                style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              onPressed: () => _confirmDeleteCategory(parent),
                            ),
                          ],
                        ),
                      ),
                      onTap: () {
                        setState(() => _filterCategoryId = parent.id);
                        _refreshNotes();
                        Navigator.pop(context);
                      },
                    ),
                    // Child Tiles (Indented)
                    ...children.map((child) => ListTile(
                          contentPadding: const EdgeInsets.only(left: 40), // Indent
                          leading: Icon(Icons.label_outlined, color: Color(child.colorValue), size: 18),
                          title: Text(child.name, style: const TextStyle(fontSize: 14)),
                          trailing: SizedBox(
                            width: 70, 
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text('${_getNoteCount(child.id)}', 
                                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 18),
                                  onPressed: () => _confirmDeleteCategory(child),
                                ),
                              ],
                            ),
                          ),
                          onTap: () {
                            setState(() => _filterCategoryId = child.id);
                            _refreshNotes();
                            Navigator.pop(context);
                          },
                        )),
                  ],
                );
              }).toList(),
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
                onLongPress: () {
                  Share.share(
                    '${note.title}\n\n${note.content}',
                    subject: note.title,
                  );
                },
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
                    width: 16,
                    height: 16,
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
    Color _tempColor = Colors.grey;
    String? _selectedParentId; // To track if this is a sub-tab

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New Tab'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _categoryController,
                  decoration: const InputDecoration(hintText: 'Category Name'),
                ),
                const SizedBox(height: 15),
                // --- PARENT SELECTOR ---
                DropdownButtonFormField<String>(
                  value: _selectedParentId,
                  decoration: const InputDecoration(labelText: 'Parent Tab (Optional)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text("None (Main Tab)")),
                    ..._drawerCategories.map((cat) => DropdownMenuItem(
                          value: cat.id,
                          child: Text(cat.name),
                        )),
                  ],
                  onChanged: (val) => setDialogState(() => _selectedParentId = val),
                ),
                const SizedBox(height: 15),
                const Text("Pick Tab Color:"),
                BlockPicker(
                  pickerColor: _tempColor,
                  onColorChanged: (color) => setDialogState(() => _tempColor = color),
                ),
              ],
            ),
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
                    parentCategoryId: _selectedParentId, // Link established here
                  );
                  await DatabaseService.instance.createCategory(newCat);
                  _loadDrawerCategories();
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

  void _confirmDeleteCategory(Category cat) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${cat.name}"?'),
        content: const Text('This will remove the tab. Notes in this tab will become "Uncategorized" but will NOT be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              await DatabaseService.instance.deleteCategory(cat.id);
              _loadDrawerCategories();
              _refreshNotes();
              Navigator.pop(context);
            }, 
            child: const Text('Delete', style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );
  }
}