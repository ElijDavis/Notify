import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'dart:async';

class AudioRecorderWidget extends StatefulWidget {
  final Function(String path) onStop;
  const AudioRecorderWidget({super.key, required this.onStop});

  @override
  State<AudioRecorderWidget> createState() => _AudioRecorderWidgetState();
}

class _AudioRecorderWidgetState extends State<AudioRecorderWidget> {
  late AudioRecorder _recorder;
  bool _isRecording = false;
  int _recordDuration = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _recorder = AudioRecorder();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      if (await _recorder.hasPermission()) {

        // 1. Get a valid Windows folder
        final directory = await getTemporaryDirectory();
        // 2. Create a specific file path
        final path = '${directory.path}\\temp_record_${DateTime.now().millisecondsSinceEpoch}.m4a';

        await _recorder.start(RecordConfig(), path: path);
        setState(() {
          _isRecording = true;
          _recordDuration = 0;
        });
        _timer = Timer.periodic(const Duration(seconds: 1), (t) {
          setState(() => _recordDuration++);
        });
      }
    } catch (e) { print(e); }
  }

  Future<void> _stop() async {
    final path = await _recorder.stop();
    _timer?.cancel();
    setState(() => _isRecording = false);
    if (path != null) widget.onStop(path);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      // Centers everything and prevents it from stretching vertically
      mainAxisSize: MainAxisSize.min, 
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Using a fixed-height container for the timer so the mic button 
        // doesn't shift down when the text appears.
        SizedBox(
          height: 20, 
          child: _isRecording 
            ? Text(
                "${_recordDuration}s", 
                style: const TextStyle(
                  color: Colors.red, 
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              )
            : const SizedBox.shrink(),
        ),
        IconButton(
          iconSize: 48,
          // Removed extra padding to save space
          padding: EdgeInsets.zero, 
          constraints: const BoxConstraints(),
          icon: Icon(
            _isRecording ? Icons.stop_circle : Icons.mic_none, 
            color: _isRecording ? Colors.red : Colors.blue,
          ),
          onPressed: _isRecording ? _stop : _start,
        ),
        // Small label so the user knows what the button is for
        Text(
          _isRecording ? "Recording..." : "Tap to Record",
          style: TextStyle(
            fontSize: 10, 
            color: _isRecording ? Colors.red : Colors.grey[600],
          ),
        ),
      ],
    );
  }
}