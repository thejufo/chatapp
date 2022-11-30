import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ConversationScreen extends StatefulWidget  {
  const ConversationScreen({Key? key, required this.user}) : super(key: key);

  final Map user;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> with WidgetsBindingObserver {
  final messages = [].obs;
  final typing = false.obs;
  final online = false.obs;

  final controller = TextEditingController();

  Future<void> deleteForMe(message) async {
    final messageId = message['id'];

    final senderUid = FirebaseAuth.instance.currentUser!.uid;
    final receiverUid = widget.user['id'];

    final db = FirebaseFirestore.instance;
    final usersCol = db.collection('users');

    final senderChatsCol = usersCol.doc(senderUid).collection('chats');
    final senderMessageDoc = senderChatsCol.doc(receiverUid);

    final messagesCol = senderMessageDoc.collection('messages');
    await messagesCol
        .doc(messageId)
        .update({'message': 'This message was deleted'});
  }

  void deleteForAll(message) async {
    await deleteForMe(message);

    final messageId = message['id'];

    final senderUid = FirebaseAuth.instance.currentUser!.uid;
    final receiverUid = widget.user['id'];

    final db = FirebaseFirestore.instance;
    final usersCol = db.collection('users');

    final receiverChatsCol = usersCol.doc(receiverUid).collection('chats');
    final receiverMessageDoc = receiverChatsCol.doc(senderUid);

    final messagesCol = receiverMessageDoc.collection('messages');
    await messagesCol
        .doc(messageId)
        .update({'message': 'This message was deleted'});
  }

  void sendMessage() async {
    final senderUid = FirebaseAuth.instance.currentUser!.uid;
    final receiverUid = widget.user['id'];

    final db = FirebaseFirestore.instance;
    final usersCol = db.collection('users');

    final messageId = usersCol.doc().id;
    final message = {
      'message': controller.text,
      'sender': senderUid,
      'date': FieldValue.serverTimestamp(),
    };

    // Sender chat
    final senderChatsCol = usersCol.doc(senderUid).collection('chats');
    final senderMessageDoc = senderChatsCol.doc(receiverUid);
    await senderMessageDoc.set({'lastMessage': message});
    await senderMessageDoc.collection('messages').doc(messageId).set(message);

    // Receiver chat
    final receiverChatsCol = usersCol.doc(receiverUid).collection('chats');
    final receiverMessageDoc = receiverChatsCol.doc(senderUid);
    await receiverMessageDoc.set({'lastMessage': message});
    await receiverMessageDoc.collection('messages').doc(messageId).set(message);
  }

  void updateTyping() async {

    final sender = FirebaseAuth.instance.currentUser!.uid;
    final String receiver = widget.user['id'];

    final db = FirebaseFirestore.instance;
    final usersCol = db.collection('users');

    usersCol
        .doc(receiver)
        .collection('chats')
        .doc(sender)
    .set({'typing': true}, SetOptions(merge: true));

    Timer(const Duration(seconds: 2), () {
      usersCol
          .doc(receiver)
          .collection('chats')
          .doc(sender)
          .set({'typing': false}, SetOptions(merge: true));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    final sender = FirebaseAuth.instance.currentUser!.uid;
    final String receiver = widget.user['id'];

    final db = FirebaseFirestore.instance;
    final usersCol = db.collection('users');

    if (state == AppLifecycleState.resumed) {
      usersCol.doc(sender)
          .set({'online': true}, SetOptions(merge: true));

    } else {
      usersCol.doc(sender)
          .set({'online': false}, SetOptions(merge: true));
    }
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    final sender = FirebaseAuth.instance.currentUser!.uid;
    final String receiver = widget.user['id'];

    final db = FirebaseFirestore.instance;
    final usersCol = db.collection('users');

    usersCol
        .doc(sender)
        .collection('chats')
        .doc(receiver)
        .collection('messages')
        .orderBy('date')
        .snapshots()
        .listen((event) {
      messages.clear();
      for (final doc in event.docs) {
        final message = {'id': doc.id, ...doc.data()};
        messages.insert(0, message);
      }
    });

    usersCol
        .doc(sender)
        .collection('chats')
        .doc(receiver)
        .snapshots()
        .listen((event) {
      typing.value = event.data()?['typing'] == true;
    });

    usersCol
        .doc(receiver)
        .snapshots()
        .listen((event) {
      online.value = event.data()?['online'] == true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
          title: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundImage: NetworkImage(widget.user['picture']),
          ),
          SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.user['name']),
              Obx(() {
                if (typing.isTrue) {
                  return Text(
                    'Typing...',
                    style:
                        TextStyle(fontWeight: FontWeight.normal, fontSize: 12),
                  );
                } else {
                  return Obx(() {
                    return Text(
                      online.value ? 'Online' : 'Offline',
                      style:
                      TextStyle(fontWeight: FontWeight.normal, fontSize: 12),
                    );
                  });
                }
              })
            ],
          )
        ],
      )),
      body: Column(
        children: [
          Expanded(
            child: Obx(() {
              return ListView.builder(
                reverse: true,
                itemCount: messages.length,
                itemBuilder: (ctx, index) {
                  final message = messages[index];
                  return Column(
                    crossAxisAlignment: message['sender'] ==
                            FirebaseAuth.instance.currentUser!.uid
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      PopupMenuButton(
                        onSelected: (val) {
                          if (val == 0) {
                            deleteForMe(message);
                          } else {
                            deleteForAll(message);
                          }
                        },
                        itemBuilder: (ctx) {
                          return [
                            const PopupMenuItem(
                                child: Text('Delete for me'), value: 0),
                            if (message['sender'] ==
                                FirebaseAuth.instance.currentUser!.uid)
                              const PopupMenuItem(
                                  child: Text('Delete for everyone'), value: 1),
                          ];
                        },
                        child: Container(
                          margin: EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: message['sender'] ==
                                      FirebaseAuth.instance.currentUser!.uid
                                  ? Colors.blue
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(8)),
                          child: Text(
                            message['message'],
                            style: TextStyle(
                                fontSize: 16,
                                color: message['sender'] ==
                                        FirebaseAuth.instance.currentUser!.uid
                                    ? Colors.white
                                    : Colors.black),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            }),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: (val) {
                      updateTyping();
                    },
                    decoration: InputDecoration(hintText: 'Enter messages'),
                  ),
                ),
                SizedBox(width: 20),
                FloatingActionButton(
                  onPressed: sendMessage,
                  mini: true,
                  elevation: 0,
                  child: Icon(Icons.send),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
