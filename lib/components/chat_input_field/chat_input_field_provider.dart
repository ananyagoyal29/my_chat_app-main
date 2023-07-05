import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:chat_package/models/chat_message.dart';
import 'package:chat_package/models/media/chat_media.dart';
import 'package:chat_package/models/media/media_type.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:stop_watch_timer/stop_watch_timer.dart';
import 'package:http/http.dart' as http;

class ChatInputFieldProvider extends ChangeNotifier {
  final Function(ChatMessage? audioMessage, bool cancel) handleRecord;
  final VoidCallback onSlideToCancelRecord;
  final Function(ChatMessage? imageMessage) handleImageSelect;
  final Function(ChatMessage text) onTextSubmit;
  final TextEditingController textController;
  final double cancelPosition;

  late Record _record = Record();
  double _position = 0;
  int _duration = 0;
  bool _isRecording = false;
  int _recordTime = 0;
  bool isText = false;
  double _height = 70;
  final StopWatchTimer _stopWatchTimer = StopWatchTimer();
  final _formKey = GlobalKey<FormState>();

  int get duration => _duration;
  bool get isRecording => _isRecording;
  int get recordTime => _recordTime;
  GlobalKey<FormState> get formKey => _formKey;

  set height(double val) => _height = val;

  Permission micPermission = Permission.microphone;
  ChatInputFieldProvider({
    required this.onTextSubmit,
    required this.textController,
    required this.handleRecord,
    required this.onSlideToCancelRecord,
    required this.cancelPosition,
    required this.handleImageSelect,
  });

  void onAnimatedButtonTap() {
    _formKey.currentState?.save();
    if (isText && textController.text.isNotEmpty) {
      final textMessage = ChatMessage(isSender: true, text: textController.text);
      onTextSubmit(textMessage);
    }
    textController.clear();
    isText = false;
    notifyListeners();
  }

  void onAnimatedButtonLongPress() async {
    final permissionStatus = await micPermission.request();

    if (permissionStatus.isGranted) {
      if (!isText) {
        _stopWatchTimer.onStartTimer();
        _stopWatchTimer.rawTime.listen((value) {
          _recordTime = value;
          print('rawTime $value ${StopWatchTimer.getDisplayTime(_recordTime)}');
          notifyListeners();
        });

        textController.clear();
        recordAudio();

        _isRecording = true;
        notifyListeners();
      }
    }
    if (permissionStatus.isPermanentlyDenied) {
      openAppSettings();
    }
  }

  void onAnimatedButtonLongPressMoveUpdate(LongPressMoveUpdateDetails details) async {
    if (!isText && _isRecording) {
      _duration = 0;
      _position = details.localPosition.dx * -1;
      notifyListeners();
    }
  }

  void onAnimatedButtonLongPressEnd(LongPressEndDetails details) async {
    final source = await stopRecord();
    _stopWatchTimer.onStopTimer();
    _stopWatchTimer.onResetTimer();

    if (!isText && await micPermission.isGranted) {
      if (_position > cancelPosition - _height || source == null) {
        log('canceled');
        handleRecord(null, true);
        onSlideToCancelRecord();
      } else {
        final audioMessage = ChatMessage(
          isSender: true,
          chatMedia: ChatMedia(
            url: source,
            mediaType: MediaType.audioMediaType(),
          ),
        );
        handleRecord(audioMessage, false);
        try {
          await uploadFileToFirebase(source);
        } catch (e) {
          log('Error uploading file: $e');
          // Handle the error gracefully
        }
      }

      _duration = 600;
      _position = 0;
      _isRecording = false;
      notifyListeners();
    }
  }

  void recordAudio() async {
    if (await _record.isRecording()) {
      _record.stop();
    }

    await _record.start(
      bitRate: 128000,
    );
  }

  Future<String?> stopRecord() async {
    return await _record.stop();
  }

  double getPosition() {
    if (_position < 0) {
      return 0;
    } else if (_position > cancelPosition - _height) {
      return cancelPosition - _height;
    } else {
      return _position;
    }
  }

  void pickImage(int type) async {
    final cameraPermission = Permission.camera;
    final storagePermission = Permission.camera;
    if (type == 1) {
      final permissionStatus = await cameraPermission.request();
      if (permissionStatus.isGranted) {
        final path = await _getImagePathFromSource(1);
        final imageMessage = _getImageMessageFromPath(path);
        handleImageSelect(imageMessage);
        return;
      } else {
        handleImageSelect(null);
        return;
      }
    } else {
      final permissionStatus = await storagePermission.request();
      if (permissionStatus.isGranted) {
        final path = await _getImagePathFromSource(2);
        final imageMessage = _getImageMessageFromPath(path);
        handleImageSelect(imageMessage);
        return;
      } else {
        handleImageSelect(null);
        return;
      }
    }
  }

  Future<String?> _getImagePathFromSource(int type) async {
    final result = await ImagePicker().pickImage(
      imageQuality: 70,
      maxWidth: 1440,
      source: type == 1 ? ImageSource.camera : ImageSource.gallery,
    );
    return result?.path;
  }

  ChatMessage? _getImageMessageFromPath(String? path) {
    if (path != null) {
      final imageMessage = ChatMessage(
        isSender: true,
        chatMedia: ChatMedia(
          url: path,
          mediaType: MediaType.imageMediaType(),
        ),
      );
      return imageMessage;
    } else {
      return null;
    }
  }

  void onTextFieldValueChanged(String value) {
    if (value.isNotEmpty) {
      textController.text = value;
      isText = true;
      notifyListeners();
    } else {
      isText = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    textController.dispose();
    super.dispose();
  }
}

Future<String> uploadFileToFirebase(String filePath) async {
  File file = File(filePath);

  if (!file.existsSync()) {
    throw Exception('File does not exist!');
  }

  String fileName = file.path.split('/').last;
  try {
    final storage = FirebaseStorage.instance;
    final ref = storage.ref().child('voice_messages').child(fileName);
    final task = await ref.putFile(file);
    final snapshot = await task;
    final downloadUrl = await snapshot.ref.getDownloadURL();

    final documentReference = await FirebaseFirestore.instance.collection('voice_messages').add({
      'fileName': fileName,
      'downloadUrl': downloadUrl,
      'duration': 0, // Add the duration field if needed
      'timestamp': FieldValue.serverTimestamp(), // Add a timestamp field
    });

    // Send the audio file for transcription
    final transcription = await transcribeAudio(file);
    if (transcription != null) {
      await documentReference.update({'transcription': transcription});
    }

    return downloadUrl;
  } catch (e) {
    throw Exception('Error uploading file to Firebase: $e');
  }
}


Future<String?> transcribeAudio(File file) async {
  final apiUrl = 'API_ENDPOINT_HERE'; // Replace with the actual API endpoint

  try {
    final response = await http.post(
      Uri.parse(apiUrl),
      headers: {'Content-Type': 'audio/mpeg'},
      body: await file.readAsBytes(),
    );

    if (response.statusCode == 200) {
      final decodedResponse = jsonDecode(response.body);
      final transcription = decodedResponse['transcription'];
      return transcription;
    } else {
      log('Transcription failed. Status code: ${response.statusCode}');
      return null;
    }
  } catch (e) {
    log('Error during transcription: $e');
    return null;
  }
}

