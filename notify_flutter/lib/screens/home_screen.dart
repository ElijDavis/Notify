import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../models/note_model.dart';
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

  @override
  void initState() {
    super.initState();
    _initialSync();
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
    final data = await DatabaseService.instance.readAllNotes();
    if (mounted) {
      setState(() {
        _notes = data;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Notes')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notes.isEmpty
              ? const Center(child: Text('No notes yet. Tap + to add one!'))
              : ListView.builder(
                  itemCount: _notes.length,
                  itemBuilder: (context, index) {
                    final note = _notes[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: ListTile(
                        title: Text(note.title),
                        subtitle: Text(note.content),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _confirmDelete(note.id),
                        ),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => NoteEditorScreen(note: note),
                            ),
                          );
                          _refreshNotes();
                        },
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          // Open Editor
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const NoteEditorScreen()),
          );
          // When returning from Editor, refresh the list
          _refreshNotes(); 
        },
        child: const Icon(Icons.add),
      ),
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
}