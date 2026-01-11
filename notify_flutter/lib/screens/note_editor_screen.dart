import 'package:flutter/material.dart';
import 'package:notify_flutter/widgets/audio_recorder_widget.dart';
import '../models/note_model.dart';
import '../models/category_model.dart';
import '../services/database_service.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart'; // Add this import
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite/sqflite.dart'; // For ConflictAlgorithm
import 'package:audioplayers/audioplayers.dart';
import 'dart:io';


class NoteEditorScreen extends StatefulWidget {
  final Note? note; // If null, we are creating a new note
  const NoteEditorScreen({super.key, this.note});

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _localAudioPath; // This stores the path of the recording before it's uploaded

  // Audio playback state
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isPlaying = false;

  DateTime? _selectedReminder; // This stores the chosen date and time
  Color _selectedColor = Colors.white; // Default color
  List<Category> _categories = [];
  String? _selectedCategoryId;
  bool _canEdit = true;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _contentController = TextEditingController(text: widget.note?.content ?? '');
    _selectedCategoryId = widget.note?.categoryId; // Load existing category if it exists
    _checkPermissions();
    _loadCategories();
    if (widget.note != null) {
      _selectedColor = Color(widget.note!.colorValue);
    }

    // Audio Player Listeners
    _audioPlayer.onDurationChanged.listen((d) {
      if (!mounted) return; // <--- ADD THIS
      setState(() => _duration = d);
    });

    _audioPlayer.onPositionChanged.listen((p) {
      if (!mounted) return; // <--- ADD THIS
      setState(() => _position = p);
    });

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (!mounted) return; // <--- ADD THIS
      setState(() => _isPlaying = state == PlayerState.playing);
    });
  }

  Future<void> _loadCategories() async {
    final cats = await DatabaseService.instance.readCategories();
    
    setState(() {
      _categories = cats;

      // SAFETY CHECK: 
      // If the note has a categoryId, but that ID isn't in our new list of categories...
      if (_selectedCategoryId != null) {
        bool categoryExists = _categories.any((cat) => cat.id == _selectedCategoryId);
        
        if (!categoryExists) {
          // ...then reset it to null so the dropdown doesn't crash!
          _selectedCategoryId = null;
        }
      }
    });
  }

  void _pickColor() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pick a note color'),
        content: SingleChildScrollView(
          child: BlockPicker(
            pickerColor: _selectedColor,
            onColorChanged: (color) {
              setState(() => _selectedColor = color);
              Navigator.pop(context);
            },
          ),
        ),
      ),
    );
  }

  Future<void> _saveNote() async {
    final id = widget.note?.id ?? const Uuid().v4();
    final user = Supabase.instance.client.auth.currentUser;
    String? finalAudioUrl = widget.note?.audioUrl; // Placeholder for audio URL handling

    // 1. If we have a new local recording, upload it first
    if (_localAudioPath != null) {
      final file = File(_localAudioPath!);
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.m4a';
      
      try {
        await Supabase.instance.client.storage
            .from('note-audios')
            .upload(fileName, file);
            
        finalAudioUrl = Supabase.instance.client.storage
            .from('note-audios')
            .getPublicUrl(fileName);
      } catch (e) {
        print("Audio upload failed: $e");
      }
    }
    
    // 1. Save the Note (This handles both Local + Supabase)
    final note = Note(
      id: id,
      title: _titleController.text,
      content: _contentController.text,
      createdAt: widget.note?.createdAt ?? DateTime.now().toIso8601String(),
      colorValue: _selectedColor.toARGB32(), // <--- Add this!
      categoryId: _selectedCategoryId,
      audioUrl: finalAudioUrl, // <--- SAVES THE AUDIO URL
      userId: user?.id,
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

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  Future<void> _checkPermissions() async {
    // If it's a new note or has no category, you can edit it
    if (widget.note == null || widget.note?.categoryId == null) return;

    final user = Supabase.instance.client.auth.currentUser;
    
    // Check if I am a member and what my level is
    final response = await Supabase.instance.client
        .from('category_members')
        .select('permission_level')
        .eq('category_id', widget.note!.categoryId!)
        .eq('user_id', user!.id)
        .maybeSingle();

    if (response != null && response['permission_level'] == 'viewer') {
      setState(() {
        _canEdit = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Note'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              if (_titleController.text.isNotEmpty || _contentController.text.isNotEmpty) {
                Share.share(
                  '${_titleController.text}\n\n${_contentController.text}',
                  subject: 'Sharing Note: ${_titleController.text}',
                );
              }
            },
          ),
          IconButton(
            icon: Icon(
              Icons.alarm,
              color: _selectedReminder != null ? Colors.blue : null,
            ),
            onPressed: _pickReminder,
          ),
          IconButton(icon: const Icon(Icons.save), onPressed: _saveNote),
          IconButton(
            icon: Icon(Icons.palette, color: _selectedColor),
            onPressed: _pickColor,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Reminders Chip
            if (_selectedReminder != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10.0),
                child: Chip(
                  backgroundColor: Colors.blue.withValues(alpha: 0.1),
                  label: Text("Reminder: ${_selectedReminder.toString().substring(0, 16)}"),
                  onDeleted: () => setState(() => _selectedReminder = null),
                  deleteIcon: const Icon(Icons.close, size: 18),
                ),
              ),

            // 2. Playback UI (Shows up if audio exists)
          // NEW PRO AUDIO PLAYER CARD
          if (widget.note?.audioUrl != null || _localAudioPath != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.blueGrey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Play/Pause Button
                      IconButton(
                        icon: Icon(
                          _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                          color: Colors.blue,
                          size: 42,
                        ),
                        onPressed: () async {
                          if (_isPlaying) {
                            await _audioPlayer.pause();
                          } else {
                            if (_localAudioPath != null) {
                              await _audioPlayer.play(DeviceFileSource(_localAudioPath!));
                            } else if (widget.note?.audioUrl != null) {
                              await _audioPlayer.play(UrlSource(widget.note!.audioUrl!));
                            }
                          }
                        },
                      ),
                      // Stop Button
                      IconButton(
                        icon: const Icon(Icons.stop_circle, color: Colors.red, size: 30),
                        onPressed: () => _audioPlayer.stop(),
                      ),
                      // Seek Bar (Slider)
                      Expanded(
                        child: Column(
                          children: [
                            Slider(
                              min: 0,
                              max: _duration.inSeconds.toDouble() > 0 
                                  ? _duration.inSeconds.toDouble() 
                                  : 1.0,
                              value: _position.inSeconds.toDouble().clamp(
                                  0.0, 
                                  _duration.inSeconds.toDouble() > 0 
                                      ? _duration.inSeconds.toDouble() 
                                      : 1.0
                              ),
                              onChanged: (value) async {
                                await _audioPlayer.seek(Duration(seconds: value.toInt()));
                              },
                            ),
                            // Time Indicators
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(_formatDuration(_position), style: const TextStyle(fontSize: 10)),
                                  Text(_formatDuration(_duration), style: const TextStyle(fontSize: 10)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 3. Title
            TextField(
              controller: _titleController,
              enabled: _canEdit,
              decoration: const InputDecoration(hintText: 'Title', border: InputBorder.none),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),

            // 4. Category Dropdown
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: DropdownButtonFormField<String>(
                initialValue: _selectedCategoryId,
                decoration: const InputDecoration(
                  labelText: 'Assign to Tab',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.tab),
                ),
                items: _categories.map((cat) {
                  return DropdownMenuItem(value: cat.id, child: Text(cat.name));
                }).toList(),
                onChanged: (value) => setState(() => _selectedCategoryId = value),
                hint: const Text("Select a Category"),
              ),
            ),

            // 5. Content
            Expanded(
              child: TextField(
                controller: _contentController,
                enabled: _canEdit,
                maxLines: null,
                decoration: const InputDecoration(hintText: 'Start typing...', border: InputBorder.none),
              ),
            ),
          ],
        ),
      ),
      // 6. BOTTOM RECORDER (The "Figma" Style)
      bottomNavigationBar: Container(
        height: 100, // Explicitly set the container height
        color: Theme.of(context).bottomAppBarTheme.color, // Keep the same color
        child: SafeArea( // Put SafeArea INSIDE the container
          child: Center(
            child: AudioRecorderWidget(
              onStop: (path) {
                setState(() => _localAudioPath = path);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Audio recorded!")),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _audioPlayer.dispose(); // <-- Add this here
    super.dispose();
  }
}