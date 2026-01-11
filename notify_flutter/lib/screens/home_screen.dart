/*import 'package:audioplayers/audioplayers.dart';
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

  // Audio Player for home screen notes
  final AudioPlayer _homePlayer = AudioPlayer();
  String? _playingNoteId; // To track which note is currently making sound

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
    _homePlayer.dispose(); 
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
            .select('id, title, content, category_id, color_value, created_at, audio_url')
            .inFilter('category_id', allVisibleCatIds);

        for (var noteData in allNotesData) {
          await db.insert('notes', {
            'id': noteData['id'],
            'title': noteData['title'],
            'content': noteData['content'],
            'category_id': noteData['category_id'],
            'color_value': noteData['color_value'],
            'created_at': noteData['created_at'],
            'audio_url': noteData['audio_url'],
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
  }*/

  import 'package:audioplayers/audioplayers.dart';
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
  List<Note> _allFetchedNotes = []; // Added to keep a master list for searching
  bool _isLoading = true;
  late StreamSubscription<List<Map<String, dynamic>>> _syncStream;
  String? _filterCategoryId; 
  List<Category> _drawerCategories = [];
  List<Note> _allNotesForCounting = [];

  // --- SEARCH & USER MEDAL ADDITIONS ---
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  final user = Supabase.instance.client.auth.currentUser;

  // Audio Player for home screen notes
  final AudioPlayer _homePlayer = AudioPlayer();
  String? _playingNoteId; 

  @override
  void initState() {
    super.initState();
    _initialSync();
    _loadDrawerCategories();
    _setupRealtimeSync();
    
    // Listen to search changes
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
        _filterNotesLocally();
      });
    });
  }

  // Filter the current list based on search text
  void _filterNotesLocally() {
    setState(() {
      _notes = _allFetchedNotes.where((note) {
        final titleMatch = note.title.toLowerCase().contains(_searchQuery);
        final contentMatch = note.content.toLowerCase().contains(_searchQuery);
        return titleMatch || contentMatch;
      }).toList();
    });
  }

  // ... (Keep your _setupRealtimeSync, dispose, _initialSync methods exactly as they are)

  @override
  void dispose() {
    _syncStream.cancel();
    _homePlayer.dispose(); 
    _searchController.dispose(); // Clean up controller
    super.dispose();
  }

  // ... (Keep your _setupRealtimeSync exactly as it is)
  void _setupRealtimeSync() {
    _syncStream = Supabase.instance.client
        .from('notes')
        .stream(primaryKey: ['id'])
        .order('created_at')
        .listen((List<Map<String, dynamic>> data) async {
          await DatabaseService.instance.syncFromCloud();
          _refreshNotes();
        }, onError: (error) => print("Realtime Sync Issue: $error"));

    Supabase.instance.client
      .from('categories')
      .stream(primaryKey: ['id'])
      .listen((data) => _loadDrawerCategories());

    Supabase.instance.client
      .from('category_members')
      .stream(primaryKey: ['id'])
      .listen((data) {
        _loadDrawerCategories(); 
        DatabaseService.instance.syncFromCloud();
      });
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

      final List<dynamic> allCats = await Supabase.instance.client.rpc('get_visible_categories');
      for (var cat in allCats) {
        await db.insert('categories', {
          'id': cat['id'], 'name': cat['name'], 'color_value': cat['color_value'],
          'parent_category_id': cat['parent_category_id'], 'owner_id': cat['owner_id'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      _loadDrawerCategories();
      final allData = await db.query('notes');
      _allNotesForCounting = allData.map((json) => Note.fromMap(json)).toList();

      List<Map<String, dynamic>> result;
      if (_filterCategoryId == null) {
        result = await db.query('notes', orderBy: 'created_at DESC');
      } else {
        result = await db.query('notes', where: 'category_id = ?', whereArgs: [_filterCategoryId], orderBy: 'created_at DESC');
      }

      setState(() {
        _allFetchedNotes = result.map((json) => Note.fromMap(json)).toList();
        _filterNotesLocally(); // Apply search filter to the newly refreshed notes
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
    // Get user initial for the medal
    String userInitial = user?.email?.substring(0, 1).toUpperCase() ?? "U";

    return Scaffold(
      drawer: _buildDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            // --- CUSTOM HEADER WITH MEDAL & SEARCH ---
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Builder(
                    builder: (context) => GestureDetector(
                      onTap: () => Scaffold.of(context).openDrawer(),
                      child: CircleAvatar(
                        radius: 22,
                        backgroundColor: Colors.blueGrey.shade800,
                        child: Text(userInitial, 
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          hintText: 'Search your notes...',
                          prefixIcon: Icon(Icons.search, color: Colors.grey),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  // Inside your Column, under the Search Bar Row
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: const Text("All"),
                          selected: _filterCategoryId == null,
                          onSelected: (_) => setState(() => _filterCategoryId = null),
                        ),
                        const SizedBox(width: 8),
                        ..._drawerCategories.where((c) => c.parentCategoryId == null).map((cat) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: ChoiceChip(
                              label: Text(cat.name),
                              selected: _filterCategoryId == cat.id,
                              onSelected: (selected) {
                                setState(() => _filterCategoryId = selected ? cat.id : null);
                                _refreshNotes();
                              },
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // --- NOTE LIST ---
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _notes.isEmpty
                      ? Center(child: Text(_searchQuery.isEmpty ? 'No notes yet.' : 'No matches found.'))
                      : _buildNoteList(),
            ),
          ],
        ),
      ),
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

  // ... (Keep your _buildDrawer, _buildNoteList, and dialog methods exactly as they are)
  // Note: Inside _buildNoteList, ensure it uses the _notes list which is now filtered!

  Widget _buildDrawer() {
    final user = Supabase.instance.client.auth.currentUser;
    // Use the username from user_metadata if it exists, otherwise use 'New User'
    final String userName = user?.userMetadata?['username'] ?? "New User";
    final mainCategories = _drawerCategories.where((c) => c.parentCategoryId == null).toList();

    return Drawer(
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: Colors.blueGrey),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Text(
                userName.substring(0, 1).toUpperCase(),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blueGrey),
              ),
            ),
            accountName: Text(userName, style: const TextStyle(fontWeight: FontWeight.bold)),
            accountEmail: Text(user?.email ?? "No email found"),
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
              padding: EdgeInsets.zero,
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
                              icon: const Icon(Icons.person_add_alt_1, size: 18),
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
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('Logout', style: TextStyle(color: Colors.redAccent)),
            onTap: () async {
              await Supabase.instance.client.auth.signOut();
              // ... your existing local DB cleanup logic
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
                subtitle: Text(note.content, maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // --- AUDIO BUTTON ---
                    if (note.audioUrl != null)
                      StreamBuilder<PlayerState>(
                        stream: _homePlayer.onPlayerStateChanged,
                        builder: (context, snapshot) {
                          final state = snapshot.data;
                          final isThisNotePlaying = state == PlayerState.playing && _playingNoteId == note.id;

                          return IconButton(
                            icon: Icon(
                              isThisNotePlaying ? Icons.stop_circle : Icons.play_circle_outline,
                              color: isThisNotePlaying ? Colors.red : Colors.blue,
                            ),
                            onPressed: () async {
                              if (isThisNotePlaying) {
                                await _homePlayer.stop();
                                setState(() => _playingNoteId = null);
                              } else {
                                await _homePlayer.stop(); // Stop any previous audio
                                _playingNoteId = note.id;
                                await _homePlayer.play(UrlSource(note.audioUrl!));
                              }
                            },
                          );
                        },
                      ),
                    // --- DELETE BUTTON ---
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _confirmDelete(note.id),
                    ),
                  ],
                ),
                onLongPress: () {
                  Share.share('${note.title}\n\n${note.content}', subject: note.title);
                },
                onTap: () async {
                  await _homePlayer.stop(); // Stop music if we navigate away
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => NoteEditorScreen(note: note)),
                  );
                  _refreshNotes();
                },
              ),
              // --- CATEGORY DOT ---
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