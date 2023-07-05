import 'dart:convert';
import 'dart:developer';

import 'package:chat_package/chat_package.dart';
import 'package:chat_package/models/chat_message.dart';
import 'package:chat_package/models/media/chat_media.dart';
import 'package:chat_package/models/media/media_type.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

Future main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'chat ui example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key? key}) : super(key: key);

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<ChatMessage> messages = [
    ChatMessage(
      isSender: true,
      text: 'this is a banana',
      // chatMedia: ChatMedia(
      //   url:
      //       'https://images.pexels.com/photos/7194915/pexels-photo-7194915.jpeg?auto=compress&cs=tinysrgb&h=750&w=1260',
      //   mediaType: MediaType.imageMediaType(),
      // ),
    ),
    ChatMessage(
      isSender: false,
      // chatMedia: ChatMedia(
      //   url:
      //       'https://images.pexels.com/photovar/pexels-photo-7194915.jpeg?auto=compress&cs=tinysrgb&h=750&w=1260',
      //   mediaType: MediaType.imageMediaType(),
      // ),
    ),
    ChatMessage(isSender: false, text: 'wow that is cool'),
  ];

  final scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: ChatScreen(
        scrollController: scrollController,
        messages: messages,
        onSlideToCancelRecord: () {
          log('not sent');
        },
        onTextSubmit: (textMessage) {
          setState(() {
            messages.add(textMessage);
            saveChatMessage(textMessage);

            scrollController
                .jumpTo(scrollController.position.maxScrollExtent + 50);
          });
        },
        handleRecord: (audioMessage, canceled) {
          if (!canceled && audioMessage != null) {
            setState(() {
              messages.add(audioMessage);
              scrollController
                  .jumpTo(scrollController.position.maxScrollExtent + 90);
            });
          }
        },
        handleImageSelect: (imageMessage) async {
          if (imageMessage != null) {
            setState(() {
              messages.add(
                imageMessage,
              );
              scrollController
                  .jumpTo(scrollController.position.maxScrollExtent + 300);
            });
          }
        },
      ),
    );
  }
}

Future<String> uploadFile(File file) async {
  print("rkjgbrwkjgojwrbgjowrgwrofjwrh");
  // String speech = await convertSpeechtoText(file.path);
  // print(speech);
  FirebaseStorage storage = FirebaseStorage.instance;
  Reference storageReference =
      storage.ref().child('voice_messages/${file.path}');

  TaskSnapshot snapshot = await storageReference.putFile(file);
  String downloadUrl = await snapshot.ref.getDownloadURL();
  // print(file.path);
  // print(speech);
  return downloadUrl;
}

Future<void> saveVoiceMessage(String downloadUrl, int duration) async {
  FirebaseFirestore firestore = FirebaseFirestore.instance;
  CollectionReference voiceMessagesCollection =
      firestore.collection('voice_messages');

  await voiceMessagesCollection.add({
    'downloadUrl': downloadUrl,
    'duration': duration,
    'timestamp': FieldValue.serverTimestamp(),
  });
}

Future<void> saveChatMessage(ChatMessage chatMessage) async {
  FirebaseFirestore firestore = FirebaseFirestore.instance;
  CollectionReference chatMessagesCollection = firestore.collection('chats');

  await chatMessagesCollection.add(chatMessage.toMap());
}
