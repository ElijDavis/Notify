/*import 'package:flutter/material.dart';
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

  String _generateRandomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random();
    // Using Random.secure() or just a better random seed
    return List.generate(6, (index) => chars[random.nextInt(chars.length)]).join();
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
                TextField(
                  controller: _categoryController,
                  decoration: const InputDecoration(hintText: 'Category Name'),
                ),
                const SizedBox(height: 15),
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
                    final user = Supabase.instance.client.auth.currentUser;
                    final String newId = const Uuid().v4();
                    final String newShareCode = _generateRandomCode();

                    final newCat = Category(
                      id: newId,
                      name: _categoryController.text,
                      colorValue: _tempColor.toARGB32(),
                      parentCategoryId: _selectedParentId,
                      ownerId: user?.id,
                      shareCode: newShareCode,
                    );

                    try {
                      // 1. Double check if this ID exists in the cloud (Safety check)
                      final existing = await Supabase.instance.client
                          .from('categories')
                          .select()
                          .eq('id', newId)
                          .maybeSingle();

                      if (existing == null) {
                        // 2. If it doesn't exist, insert it
                        await Supabase.instance.client.from('categories').insert({
                          'id': newCat.id,
                          'name': newCat.name,
                          'color_value': newCat.colorValue,
                          'parent_category_id': newCat.parentCategoryId,
                          'owner_id': newCat.ownerId,
                          'share_code': newCat.shareCode,
                        });
                        
                        // 3. Save locally
                        await DatabaseService.instance.createCategory(newCat);
                      }

                      _loadDrawerCategories();
                      if (mounted) Navigator.pop(context);
                      
                    } catch (e) {
                      print("Final Sync Error: $e");
                      // If we still get a 23505, we just ignore it and close because the data is already there!
                      if (e.toString().contains('23505')) {
                        Navigator.pop(context);
                      }
                    }
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
            onPressed: () {
              final code = _codeController.text.trim();
              if (code.isNotEmpty) {
                Navigator.pop(context); // Close dialog first
                _joinSharedTab(code);   // Use the robust function you wrote!
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
    final categories = await DatabaseService.instance.readCategories();
    
    // ALWAYS check if the widget is still on screen before calling setState
    if (mounted) {
      setState(() {
        _drawerCategories = categories;
      });
    }
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
    // If for some reason an old category doesn't have a code, we generate one now
    final String code = cat.shareCode ?? "NO CODE";

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Share "${cat.name}"'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Share this code with others to collaborate:"),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                code,
                style: const TextStyle(
                  fontSize: 32, 
                  fontWeight: FontWeight.bold, 
                  letterSpacing: 4,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _joinSharedTab(String code) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    // Show a loading indicator while we process the join
    setState(() => _isLoading = true);

    try {
      // 1. Find the category with this code in Supabase
      // maybeSingle() prevents the crash if the code doesn't exist
      final category = await Supabase.instance.client
          .from('categories')
          .select()
          .eq('share_code', code.trim())
          .maybeSingle();

      if (category == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Invalid share code. Please check and try again.")),
          );
        }
        return;
      }

      // 2. Check if already a member to prevent duplicate errors
      final existingMember = await Supabase.instance.client
          .from('category_members')
          .select()
          .eq('category_id', category['id'])
          .eq('user_id', user.id)
          .maybeSingle();

      if (existingMember == null) {
        // 3. Add user to category_members in Supabase
        await Supabase.instance.client.from('category_members').insert({
          'category_id': category['id'],
          'user_id': user.id,
        });
      }

      // 4. Run the full sync to pull the new category and its notes into SQLite
      await _refreshNotes(); 
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Successfully joined '${category['name']}'")),
        );
      }
    } catch (e) {
      print("Join Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error joining tab: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

}*/

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
        _loadDrawerCategories(); 
      });

    Supabase.instance.client
      .from('reminders')
      .stream(primaryKey: ['id'])
      .listen((List<Map<String, dynamic>> data) async {
        await DatabaseService.instance.syncFromCloud();
        for (var rem in data) {
          DateTime time = DateTime.parse(rem['reminder_time']);
          if (time.isAfter(DateTime.now())) {
            NotificationService().scheduleNotification(
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

      // FIGMA LOGIC: Fetch categories using the RPC function we created
      // This gets everything: Owned + Invited by email
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

      final localCats = await db.query('categories');
      final allVisibleCatIds = localCats.map((c) => c['id'] as String).toList();

      if (allVisibleCatIds.isNotEmpty) {
        final allNotesData = await Supabase.instance.client
            .from('notes')
            .select()
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
      }

      _loadDrawerCategories();
      final allData = await db.query('notes');
      _allNotesForCounting = allData.map((json) => Note.fromMap(json)).toList();

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
                  await Supabase.instance.client.from('category_members').insert({
                    'category_id': cat.id,
                    'invited_email': email,
                  });
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Invite sent to $email")));
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invite failed. Check RLS policies.")));
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