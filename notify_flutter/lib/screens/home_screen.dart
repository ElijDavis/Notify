import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:notify_flutter/screens/auth_screen.dart';
import 'package:sqflite/sqflite.dart';
import '../services/database_service.dart';
import '../models/note_model.dart';
import '../models/category_model.dart';
import 'package:uuid/uuid.dart';
import 'note_editor_screen.dart';
import 'dart:async'; 
import 'dart:io'; 
import 'package:supabase_flutter/supabase_flutter.dart'; 
import '../services/notification_service.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:math';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Note> _notes = [];
  bool _isLoading = true;
  late StreamSubscription<List<Map<String, dynamic>>> _syncStream;
  String? _filterCategoryId; 
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
  // NOTES STREAM
  _syncStream = Supabase.instance.client
      .from('notes')
      .stream(primaryKey: ['id'])
      .order('created_at')
      .listen((List<Map<String, dynamic>> data) async {
        await DatabaseService.instance.syncFromCloud();
        _refreshNotes();
      }, onError: (error) {
        // This is key! It prevents the "Lost Connection" crash.
        print("Realtime Sync Issue: $error");
      });

  // CATEGORIES STREAM
  Supabase.instance.client
    .from('categories')
    .stream(primaryKey: ['id'])
    .listen((data) {
      _loadDrawerCategories(); 
    }, onError: (error) => print("Category Stream Error: $error"));

  // REMINDERS STREAM
  Supabase.instance.client
    .from('reminders')
    .stream(primaryKey: ['id'])
    .listen((List<Map<String, dynamic>> data) async {
      await DatabaseService.instance.syncFromCloud();
      // ... reminder logic
    }, onError: (error) => print("Reminder Stream Error: $error"));

  //member_categories stream
  // Add this inside your _setupRealtimeSync function
  Supabase.instance.client
    .from('category_members')
    .stream(primaryKey: ['id'])
    .listen((data) {
      // When I am added to a new category, refresh the categories and notes!
      _loadDrawerCategories(); 
      DatabaseService.instance.syncFromCloud();
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
  setState(() => _isLoading = true);

  try {
    final db = await DatabaseService.instance.database;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    // 1. Fetch Categories using the RPC (Owned + Invited)
    final List<dynamic> allCats = await Supabase.instance.client.rpc('get_visible_categories');

    for (var cat in allCats) {
      await db.insert('categories', {
        'id': cat['id'],
        'name': cat['name'],
        'color_value': cat['color_value'],
        'parent_category_id': cat['parent_category_id'],
        'owner_id': cat['owner_id'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    // 2. Fetch the updated local category IDs to use as a filter
    final localCats = await db.query('categories');
    final allVisibleCatIds = localCats.map((c) => c['id'] as String).toList();

    if (allVisibleCatIds.isNotEmpty) {
      try {
        // FIXED: We specify columns explicitly to avoid the "users table" permission error.
        // We do NOT select 'user_id' or '*' here.
        final allNotesData = await Supabase.instance.client
            .from('notes')
            .select('id, title, content, category_id, color_value, created_at')
            .inFilter('category_id', allVisibleCatIds);

        for (var noteData in allNotesData) {
          await db.insert('notes', {
            'id': noteData['id'],
            'title': noteData['title'],
            'content': noteData['content'],
            'category_id': noteData['category_id'],
            'color_value': noteData['color_value'],
            'created_at': noteData['created_at'],
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      } catch (e) {
        print("Note Sync Error (likely RLS): $e");
      }
    }

    // 3. UI Updates: Refresh drawer and counts
    _loadDrawerCategories();
    final allData = await db.query('notes');
    _allNotesForCounting = allData.map((json) => Note.fromMap(json)).toList();

    // 4. Update the main list view based on active filter
    List<Map<String, dynamic>> result;
    if (_filterCategoryId == null) {
      result = await db.query('notes', orderBy: 'created_at DESC');
    } else {
      result = await db.query(
        'notes',
        where: 'category_id = ?',
        whereArgs: [_filterCategoryId],
        orderBy: 'created_at DESC',
      );
    }

    setState(() {
      _notes = result.map((json) => Note.fromMap(json)).toList();
    });

  } catch (e) {
    print("Refresh Error: $e");
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}

  int _getNoteCount(String? categoryId) {
    if (categoryId == null) return _allNotesForCounting.length;
    return _allNotesForCounting.where((n) => n.categoryId == categoryId).length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Notes')),
      drawer: _buildDrawer(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notes.isEmpty
              ? const Center(child: Text('No notes yet. Tap + to add one!'))
              : _buildNoteList(),
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

  Widget _buildDrawer() {
    final mainCategories = _drawerCategories.where((c) => c.parentCategoryId == null).toList();

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
                final children = _drawerCategories.where((c) => c.parentCategoryId == parent.id).toList();

                return Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.folder, color: Color(parent.colorValue)),
                      title: Text(parent.name, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                      trailing: SizedBox(
                        width: 110,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text('${_getNoteCount(parent.id)}', style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                            IconButton(
                              icon: const Icon(Icons.person_add_alt_1, size: 18), // Figma-style Icon
                              onPressed: () => _showFigmaInviteDialog(parent),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18),
                              onPressed: () => _confirmLeaveOrDelete(parent),
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
                    ...children.map((child) => ListTile(
                      contentPadding: const EdgeInsets.only(left: 40, right: 8),
                      leading: Icon(Icons.label_outlined, color: Color(child.colorValue), size: 18),
                      title: Text(child.name, style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis),
                      trailing: SizedBox(
                        width: 110,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text('${_getNoteCount(child.id)}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            IconButton(
                              icon: const Icon(Icons.person_add_alt_1, size: 16),
                              onPressed: () => _showFigmaInviteDialog(child),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 16),
                              onPressed: () => _confirmLeaveOrDelete(child),
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
          const Spacer(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('Logout', style: TextStyle(color: Colors.redAccent)),
            onTap: () async {
              await Supabase.instance.client.auth.signOut();
              final db = await DatabaseService.instance.database;
              await db.delete('notes');
              await db.delete('categories');
              await db.delete('reminders');
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context, 
                  MaterialPageRoute(builder: (context) => const AuthScreen()),
                  (route) => false,
                );
              }
            },
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildNoteList() {
    return ListView.builder(
      itemCount: _notes.length,
      itemBuilder: (context, index) {
        final note = _notes[index];
        Color categoryColor = Colors.transparent;
        if (note.categoryId != null) {
          try {
            categoryColor = Color(_drawerCategories
                .firstWhere((c) => c.id == note.categoryId)
                .colorValue);
          } catch (_) {}
        }

        return Card(
          color: Color(note.colorValue),
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Stack(
            children: [
              ListTile(
                title: Text(note.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(note.content),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _confirmDelete(note.id),
                ),
                onLongPress: () {
                  Share.share('${note.title}\n\n${note.content}', subject: note.title);
                },
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => NoteEditorScreen(note: note)),
                  );
                  _refreshNotes();
                },
              ),
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
    String? _selectedParentId;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New Tab'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: _categoryController, decoration: const InputDecoration(hintText: 'Category Name')),
                const SizedBox(height: 15),
                DropdownButtonFormField<String>(
                  initialValue: _selectedParentId,
                  decoration: const InputDecoration(labelText: 'Parent Tab (Optional)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text("None (Main Tab)")),
                    ..._drawerCategories.where((c) => c.parentCategoryId == null).map((cat) => DropdownMenuItem(value: cat.id, child: Text(cat.name))),
                  ],
                  onChanged: (val) => setDialogState(() => _selectedParentId = val),
                ),
                const SizedBox(height: 15),
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
                  final user = Supabase.instance.client.auth.currentUser;
                  final String newId = const Uuid().v4();
                  await Supabase.instance.client.from('categories').insert({
                    'id': newId,
                    'name': _categoryController.text,
                    'color_value': _tempColor.toARGB32(),
                    'parent_category_id': _selectedParentId,
                    'owner_id': user?.id,
                  });
                  _refreshNotes();
                  if (mounted) Navigator.pop(context);
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadDrawerCategories() async {
    final categories = await DatabaseService.instance.readCategories();
    if (mounted) setState(() => _drawerCategories = categories);
  }

  void _confirmLeaveOrDelete(Category cat) {
    final user = Supabase.instance.client.auth.currentUser;
    bool isOwner = cat.ownerId == null || cat.ownerId == user?.id;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isOwner ? 'Delete Tab?' : 'Leave Tab?'),
        content: Text(isOwner ? 'This will delete the tab for everyone.' : 'You will no longer see this shared tab.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              await DatabaseService.instance.leaveOrDeleteCategory(cat.id);
              _refreshNotes();
              Navigator.pop(context);
            }, 
            child: Text(isOwner ? 'Delete' : 'Leave', style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // FIGMA STYLE DIALOG
void _showFigmaInviteDialog(Category cat) {
    final TextEditingController _emailController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Invite to ${cat.name}'),
        content: TextField(
          controller: _emailController,
          decoration: const InputDecoration(hintText: 'Enter user email'),
          keyboardType: TextInputType.emailAddress,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final email = _emailController.text.trim().toLowerCase();
              if (email.isNotEmpty) {
                try {
                  // Use the new service method we added
                  await DatabaseService.instance.inviteUserToCategory(cat.id, email);
                  
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Invite sent to $email"))
                    );
                    // Refresh to ensure the UI knows about the new member link
                    _refreshNotes();
                  }
                } catch (e) {
                  print("Invite Error: $e");
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Could not send invite. Check your internet."))
                  );
                }
              }
            },
            child: const Text('Invite'),
          ),
        ],
      ),
    );
  }
}