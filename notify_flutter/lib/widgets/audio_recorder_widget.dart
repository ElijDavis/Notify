import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'dart:async';

class AudioRecorderWidget extends StatefulWidget {
  final Function(String path) onStop;
  final Function(String) onSpeechResult;
  const AudioRecorderWidget({super.key, required this.onStop, required this.onSpeechResult});

  @override
  State<AudioRecorderWidget> createState() => _AudioRecorderWidgetState();
}

class _AudioRecorderWidgetState extends State<AudioRecorderWidget> {
  late AudioRecorder _recorder;
  final stt.SpeechToText _speech = stt.SpeechToText();
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
      // 1. Initialize Speech
      bool available = await _speech.initialize(
        onStatus: (status) => print('Speech Status: $status'),
        onError: (error) => print('Speech Error: $error'),
      );

      if (await _recorder.hasPermission() && available) {
        final directory = await getTemporaryDirectory();
        final path = '${directory.path}\\temp_record_${DateTime.now().millisecondsSinceEpoch}.m4a';

        // 2. Start Audio Recording
        await _recorder.start(const RecordConfig(), path: path);

        // 3. Start Live Transcription
        _speech.listen(
          onResult: (result) {
            // This sends the words to your NoteEditor as you speak
            widget.onSpeechResult(result.recognizedWords);
          },
          listenMode: stt.ListenMode.dictation, // Pro Tip 2: Keeps it listening longer
        );

        setState(() {
          _isRecording = true;
          _recordDuration = 0;
        });

        _timer = Timer.periodic(const Duration(seconds: 1), (t) {
          setState(() => _recordDuration++);
        });
      }
    } catch (e) { print("Start Error: $e"); }
  }

  Future<void> _stop() async {
    try {
      final path = await _recorder.stop();
      await _speech.stop(); // Stop the speech engine
      _timer?.cancel();
      
      setState(() => _isRecording = false);
      if (path != null) widget.onStop(path);
    } catch (e) { print("Stop Error: $e"); }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min, // Vital: don't take extra space
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Only show timer if recording, and keep it very small
        if (_isRecording)
          Text(
            "${_recordDuration}s",
            style: const TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
              fontSize: 12, // Reduced size
            ),
          ),
        IconButton(
          // Reduce the icon size slightly to ensure it fits in 76px
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