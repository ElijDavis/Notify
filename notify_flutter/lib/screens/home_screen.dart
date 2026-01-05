import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../models/note_model.dart';
import 'package:uuid/uuid.dart';
import 'note_editor_screen.dart';
import 'dart:async'; // Fixes 'StreamSubscription'
import 'package:supabase_flutter/supabase_flutter.dart'; // Fixes 'Supabase'

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
    // This listens for any change in the 'notes' table for the logged-in user
    _syncStream = Supabase.instance.client
        .from('notes')
        .stream(primaryKey: ['id'])
        .order('created_at')
        .listen((List<Map<String, dynamic>> data) async {
          // When the cloud changes, update local SQLite so they stay in sync
          await DatabaseService.instance.syncFromCloud();
          _refreshNotes(); // Update the UI list
        });

    // NEW: Listen for reminders
    Supabase.instance.client
      .from('reminders')
      .stream(primaryKey: ['id'])
      .listen((List<Map<String, dynamic>> data) async {
        await DatabaseService.instance.syncFromCloud();
        
        // Loop through reminders and schedule them!
        for (var rem in data) {
          DateTime time = DateTime.parse(rem['reminder_time']);
          if (time.isAfter(DateTime.now())) {
            NotificationService().scheduleNotification(
              rem['id'], 
              "Note Reminder", // You can pull the actual note title here later
              time
            );
          }
        }
      });
  }

  @override
  void dispose() {
    _syncStream.cancel(); // Stop listening when app closes
    super.dispose();
  }

  Future<void> _initialSync() async {
    await DatabaseService.instance.syncFromCloud(); // Pull from cloud
    _refreshNotes(); // Show them on the screen
  }

  // This function fetches the notes from the database
  Future<void> _refreshNotes() async {
    final data = await DatabaseService.instance.readAllNotes();
    setState(() {
      _notes = data;
      _isLoading = false;
    });
  }

  // Temporary function to add a quick note
  Future<void> _addTestNote() async {
    final newNote = Note(
      id: const Uuid().v4(),
      title: "Note #${_notes.length + 1}",
      content: "This is a note saved in my local database!",
      createdAt: DateTime.now().toIso8601String(),
    );

    await DatabaseService.instance.createNote(newNote);
    _refreshNotes(); // Refresh the list after adding
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
                          onPressed: () async {
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
                              await DatabaseService.instance.deleteNote(note.id);
                              _refreshNotes();
                            }
                          },
                        ),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => NoteEditorScreen(note: note), // Pass the existing note!
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
          // This tells Flutter to slide the Editor Screen over the Home Screen
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const NoteEditorScreen()),
          );
          
          // This line runs AFTER you come back from the editor
          _refreshNotes(); 
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}