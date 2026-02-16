//IMP: Diff from example (new)

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

class ChatStorage {
  static const _kKey = 'chat_messages_v1';

  static Map<String, dynamic> _toMap(Message m) => {
    'text': m.text,
    'isUser': m.isUser,
    'type': m.type.name,      // text | thinking | toolCall | systemInfo | ...
    // If you need image persistence later, base64 it here.
  };

  static Message _fromMap(Map<String, dynamic> map) {
    final typeStr = (map['type'] as String?) ?? 'text';
    final type = MessageType.values.firstWhere(
          (t) => t.name == typeStr,
      orElse: () => MessageType.text,
    );

    switch (type) {
      case MessageType.thinking:
        return Message.thinking(text: map['text'] ?? '');
      case MessageType.systemInfo:
        return Message.systemInfo(text: map['text'] ?? '');
      default:
        return Message(text: map['text'] ?? '', isUser: map['isUser'] == true);
    }
  }

  static Future<void> save(List<Message> messages) async {
    final prefs = await SharedPreferences.getInstance();
    final data = messages.map(_toMap).toList(growable: false);
    await prefs.setString(_kKey, jsonEncode(data));
  }

  static Future<List<Message>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw == null) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(_fromMap).toList(growable: true); // already oldest→newest
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKey);
  }
}
