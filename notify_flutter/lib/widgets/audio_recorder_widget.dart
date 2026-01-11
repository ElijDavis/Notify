import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'dart:async';
import 'dart:io' show Platform;

class AudioRecorderWidget extends StatefulWidget {
  final Function(String path) onStop;
  // Removed onSpeechResult since we aren't transcribing anymore
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
        final directory = await getTemporaryDirectory();
        
        // Proper path handling for Windows vs Mobile
        final String path = Platform.isWindows 
            ? '${directory.path}\\temp_${DateTime.now().millisecondsSinceEpoch}.m4a'
            : '${directory.path}/temp_${DateTime.now().millisecondsSinceEpoch}.m4a';

        setState(() {
          _isRecording = true;
          _recordDuration = 0;
        });

        // Start the audio file recorder
        await _recorder.start(const RecordConfig(), path: path);

        _timer = Timer.periodic(const Duration(seconds: 1), (t) {
          setState(() => _recordDuration++);
        });
      }
    } catch (e) {
      debugPrint("Recording Start Error: $e");
    }
  }

  Future<void> _stop() async {
    try {
      final path = await _recorder.stop();
      _timer?.cancel();
      
      setState(() => _isRecording = false);
      if (path != null) widget.onStop(path);
    } catch (e) { 
      debugPrint("Recording Stop Error: $e"); 
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_isRecording)
          Text(
            "${_recordDuration}s",
            style: const TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        IconButton(
          iconSize: 36, 
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: Icon(
            _isRecording ? Icons.stop_circle : Icons.mic_none,
            color: _isRecording ? Colors.red : Colors.blue,
          ),
          onPressed: _isRecording ? _stop : _start,
        ),
      ],
    );
  }
}