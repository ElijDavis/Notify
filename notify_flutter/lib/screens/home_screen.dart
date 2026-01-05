import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../models/note_model.dart';
import 'package:uuid/uuid.dart';
import 'note_editor_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Note> _notes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshNotes();
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
                            await DatabaseService.instance.deleteNote(note.id);
                            _refreshNotes();
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