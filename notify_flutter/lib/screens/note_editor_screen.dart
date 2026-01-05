import 'package:flutter/material.dart';
import '../models/note_model.dart';
import '../services/database_service.dart';
import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart';

class NoteEditorScreen extends StatefulWidget {
  final Note? note; // If null, we are creating a new note
  const NoteEditorScreen({super.key, this.note});

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;

  DateTime? _selectedReminder; // This stores the chosen date and time

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _contentController = TextEditingController(text: widget.note?.content ?? '');
  }

  /*Future<void> _saveNote() async {
    final id = widget.note?.id ?? const Uuid().v4();
    
    // 1. Save the Note as usual
    final note = Note(
      id: id,
      title: _titleController.text,
      content: _contentController.text,
      createdAt: widget.note?.createdAt ?? DateTime.now().toIso8601String(),
    );
    await DatabaseService.instance.createNote(note);

    // 2. If a reminder was picked, save it to the reminders table
    if (_selectedReminder != null) {
      final db = await DatabaseService.instance.database;
      await db.insert(
        'reminders',
        {
          'id': const Uuid().v4(),
          'note_id': id,
          'reminder_time': _selectedReminder!.toIso8601String(),
          'is_completed': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    if (mounted) Navigator.pop(context);
  }*/

  Future<void> _saveNote() async {
    final id = widget.note?.id ?? const Uuid().v4();
    
    // 1. Save the Note (This handles both Local + Supabase)
    final note = Note(
      id: id,
      title: _titleController.text,
      content: _contentController.text,
      createdAt: widget.note?.createdAt ?? DateTime.now().toIso8601String(),
    );
    await DatabaseService.instance.createNote(note);

    // 2. Save the Reminder using the service (This handles both Local + Supabase)
    if (_selectedReminder != null) {
      await DatabaseService.instance.saveReminder(
        const Uuid().v4(), 
        id, 
        _selectedReminder!,
      );
    }

    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickReminder() async {
    // 1. Pick Date
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedReminder ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );

    if (pickedDate == null) return;

    // 2. Pick Time
    if (!mounted) return;
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedReminder ?? DateTime.now()),
    );

    if (pickedTime == null) return;

    // 3. Combine them into one DateTime object
    setState(() {
      _selectedReminder = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Note'),
        actions: [
          IconButton(
            icon: Icon(
              Icons.alarm,
              color: _selectedReminder != null ? Colors.blue : null, // Blue if set
            ),
            onPressed: _pickReminder,
          ),
          IconButton(icon: const Icon(Icons.save), onPressed: _saveNote)],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, // Aligns text to the left
          children: [
            // NEW: Show the selected time ONLY if it exists
            if (_selectedReminder != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10.0),
                child: Chip(
                  backgroundColor: Colors.blue.withOpacity(0.1),
                  label: Text("Reminder: ${_selectedReminder.toString().substring(0, 16)}"),
                  onDeleted: () => setState(() => _selectedReminder = null), 
                  deleteIcon: const Icon(Icons.close, size: 18),
                ),
              ),

            // Your existing Title TextField
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(hintText: 'Title', border: InputBorder.none),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),

            // Your existing Content TextField
            Expanded(
              child: TextField(
                controller: _contentController,
                maxLines: null,
                decoration: const InputDecoration(hintText: 'Start typing...', border: InputBorder.none),
              ),
            ),
          ],
        ),
      ),
    );
  }
}