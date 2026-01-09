import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'dart:async';
import 'dart:io' show Platform; // Add this import at the top

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

  /*Future<void> _start() async {
    try {
      bool isMobile = Platform.isAndroid || Platform.isIOS;
      bool speechAvailable = false;

      // 1. Only try to initialize speech if we are on a mobile device
      if (isMobile) {
        speechAvailable = await _speech.initialize(
          onStatus: (status) => print('Speech Status: $status'),
          onError: (error) => print('Speech Error: $error'),
        );
      }

      if (await _recorder.hasPermission()) {
        final directory = await getTemporaryDirectory();
        // Logic for Windows vs Mobile paths
        final path = Platform.isWindows 
            ? '${directory.path}\\temp_${DateTime.now().millisecondsSinceEpoch}.m4a'
            : '${directory.path}/temp_${DateTime.now().millisecondsSinceEpoch}.m4a';

        await _recorder.start(const RecordConfig(), path: path);

        // 2. Only start listening if speech is available (Mobile)
        if (isMobile && speechAvailable) {
          /*_speech.listen(
            onResult: (result) => widget.onSpeechResult(result.recognizedWords),
            listenMode: stt.ListenMode.dictation,
          );*/

          _speech.listen(
            onResult: (result) {
              widget.onSpeechResult(result.recognizedWords);
            },
            listenMode: stt.ListenMode.dictation, // Optimized for long notes
            pauseFor: const Duration(seconds: 10), // Wait 10 seconds before timing out
            cancelOnError: false, // Don't kill the session if it misses one word
            partialResults: true, // This is crucial! It shows text AS you speak
          );
        } else if (Platform.isWindows) {
          print("Speech-to-Text is not supported on Windows yet. Recording audio only.");
        }

        setState(() {
          _isRecording = true;
          _recordDuration = 0;
        });
        _timer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() => _recordDuration++));
      }
    } catch (e) {
      print("Start Error: $e");
    }
  }*/

  Future<void> _start() async {
    print("--- RECORDING START SEQUENCE ---");
    try {
      // 1. Initialize Speech Engine
      bool available = await _speech.initialize(
        onStatus: (status) => print('SPEECH STATUS: $status'),
        onError: (error) => print('SPEECH ERROR: $error'),
      );

      if (available && await _recorder.hasPermission()) {
        setState(() {
          _recordDuration = 0;
          _isRecording = true;
        });

        // 2. START SPEECH FIRST
        print("DEBUG: Starting Speech Engine...");
        /*await _speech.listen(
          onResult: (result) {
            print("WORDS HEARD: ${result.recognizedWords}");
            widget.onSpeechResult(result.recognizedWords);
          },
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
        );*/

        // 3. WAIT a bit for the speech engine to "own" the mic
        await Future.delayed(const Duration(milliseconds: 800));

        // 4. START AUDIO FILE RECORDER SECOND
        final directory = await getTemporaryDirectory();
        final path = '${directory.path}/temp_${DateTime.now().millisecondsSinceEpoch}.m4a';
        
        print("DEBUG: Starting File Recorder...");
        await _recorder.start(const RecordConfig(), path: path);

        _timer = Timer.periodic(const Duration(seconds: 1), (t) {
          setState(() => _recordDuration++);
        });
      }
    } catch (e) {
      print("STARTUP CRASH: $e");
    }
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