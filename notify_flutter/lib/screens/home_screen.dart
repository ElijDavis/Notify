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
    setState(() => _isLoading = true);

    try {
      final db = await DatabaseService.instance.database;
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      // 1. Sync Categories YOU OWN
      final cloudCategories = await Supabase.instance.client
          .from('categories')
          .select()
          .eq('owner_id', user.id);

      for (var cat in cloudCategories) {
        await db.insert('categories', {
          'id': cat['id'],
          'name': cat['name'],
          'color_value': cat['color_value'],
          'parent_category_id': cat['parent_category_id'],
          'share_code': cat['share_code'],
          'owner_id': cat['owner_id'],
          // 'user_id' is intentionally omitted here to prevent SQLite errors
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      // 2. Sync Categories YOU JOINED (Shared with you)
      // We fetch the category details via the category_members relationship
      final memberRecords = await Supabase.instance.client
          .from('category_members')
          .select('category_id, categories(*)')
          .eq('user_id', user.id);

      for (var record in memberRecords) {
        if (record['categories'] != null) {
          final cat = record['categories'];
          await db.insert('categories', {
            'id': cat['id'],
            'name': cat['name'],
            'color_value': cat['color_value'],
            'parent_category_id': cat['parent_category_id'],
            'share_code': cat['share_code'],
            'owner_id': cat['owner_id'],
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      // 3. Sync ALL Notes (for both owned and joined categories)
      final localCats = await db.query('categories');
      final allVisibleCatIds = localCats.map((c) => c['id'] as String).toList();

      if (allVisibleCatIds.isNotEmpty) {
        final allNotesData = await Supabase.instance.client
            .from('notes')
            .select()
            .inFilter('category_id', allVisibleCatIds);

        for (var noteData in allNotesData) {
          // We ensure the note map matches your local SQLite note table columns
          await db.insert('notes', {
            'id': noteData['id'],
            'title': noteData['title'],
            'content': noteData['content'],
            'category_id': noteData['category_id'],
            'color_value': noteData['color_value'],
            'created_at': noteData['created_at'],
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      // 4. Update the Drawer and Global Count
      _loadDrawerCategories();
      final allData = await db.query('notes');
      _allNotesForCounting = allData.map((json) => Note.fromMap(json)).toList();

      // 5. Update the Main UI List based on current filter
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Sync failed: $e")),
        );
      }
    } finally {
      // This ensures the loading spinner stops even if an error occurs
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
                    // --- PARENT TILE ---
                    ListTile(
                      leading: Icon(Icons.folder, color: Color(parent.colorValue)),
                      title: Text(parent.name, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                      trailing: SizedBox(
                        width: 110, // Increased width to prevent overflow
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text('${_getNoteCount(parent.id)}', style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                            IconButton(
                              icon: const Icon(Icons.share, size: 18),
                              onPressed: () => _showShareTabDialog(parent),
                            ),
                            IconButton(
                              // This uses our new logic to decide whether to Delete or Leave
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

                    // --- CHILD TILES ---
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
                              icon: const Icon(Icons.share, size: 16),
                              onPressed: () => _showShareTabDialog(child), // Corrected to child
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 16),
                              onPressed: () => _confirmLeaveOrDelete(child), // Corrected to child
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
          ListTile(
            leading: const Icon(Icons.group_add, color: Colors.green),
            title: const Text('Join Shared Tab'),
            onTap: () {
              Navigator.pop(context);
              _showJoinTabDialog();
            },
          ),
          const Spacer(), // Pushes the logout button to the bottom
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('Logout', style: TextStyle(color: Colors.redAccent)),
            onTap: () async {
              // 1. Log out from Supabase
              await Supabase.instance.client.auth.signOut();
              
              // 2. Wipe the local database tables
              final db = await DatabaseService.instance.database;
              await db.delete('notes');
              await db.delete('categories');
              await db.delete('reminders');
              // Add any other tables like 'category_members' if you created them locally

              // 3. Navigate back to Auth screen
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context, 
                  MaterialPageRoute(builder: (context) => const AuthScreen()),
                  (route) => false, // Clears the entire navigation history
                );
              }
            },
          ),
          const SizedBox(height: 10), // Some breathing room at the bottom
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
                  initialValue: _selectedParentId,
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
                  final user = Supabase.instance.client.auth.currentUser; // Get your ID
                  
                  final newCat = Category(
                    id: const Uuid().v4(),
                    name: _categoryController.text,
                    colorValue: _tempColor.toARGB32(), // Updated to non-deprecated method
                    parentCategoryId: _selectedParentId,
                    ownerId: user?.id, // <--- This links the tab to YOU
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

  void _showJoinTabDialog() {
    final TextEditingController _codeController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join a Tab'),
        content: TextField(
          controller: _codeController,
          decoration: const InputDecoration(hintText: 'Enter 6-digit code'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final code = _codeController.text.trim();
              final user = Supabase.instance.client.auth.currentUser;

              // 1. Find the category with this code in Supabase
              final response = await Supabase.instance.client
                  .from('categories')
                  .select()
                  .eq('share_code', code)
                  .single();

              if (response != null && user != null) {
                // 2. Add the user as a member (Viewer by default)
                await Supabase.instance.client.from('category_members').insert({
                  'category_id': response['id'],
                  'user_id': user.id,
                  'permission_level': 'viewer', 
                });
                
                _loadDrawerCategories();
                Navigator.pop(context);
              }
            },
            child: const Text('Join'),
          ),
        ],
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

  void _confirmLeaveOrDelete(Category cat) {
    final user = Supabase.instance.client.auth.currentUser;
    
    // Use the user variable to check ownership
    // If the owner_id is missing (local only) or matches our ID, we are the owner
    bool isOwner = cat.ownerId == null || cat.ownerId == user?.id;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isOwner ? 'Delete Tab?' : 'Leave Tab?'),
        content: Text(isOwner 
          ? 'This will delete the tab for everyone.' 
          : 'You will no longer see this shared tab.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              await DatabaseService.instance.leaveOrDeleteCategory(cat.id);
              _loadDrawerCategories();
              _refreshNotes();
              Navigator.pop(context);
            }, 
            child: Text(
              isOwner ? 'Delete' : 'Leave', 
              style: const TextStyle(color: Colors.red)
            ),
          ),
        ],
      ),
    );
  }

  void _showShareTabDialog(Category cat) {
    // Generate a random 6-character code if it doesn't have one
    final String code = cat.shareCode ?? 
        (DateTime.now().millisecondsSinceEpoch.toString().substring(7));

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Share "${cat.name}"'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Give this code to a friend to let them join this tab:"),
            const SizedBox(height: 15),
            SelectableText(
              code,
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              // Save the code to Supabase so it becomes "active"
              await Supabase.instance.client
                  .from('categories')
                  .update({'share_code': code})
                  .eq('id', cat.id);
              Navigator.pop(context);
            },
            child: const Text('Activate & Close'),
          ),
        ],
      ),
    );
  }
}