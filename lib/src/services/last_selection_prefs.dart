//IMP: Diff from example (new)

import 'package:collection/collection.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'package:flutter_gemma/pigeon.g.dart' show PreferredBackend;

import '../models/model.dart';
import '../models/embedding_model.dart';

class LastSelection {
  final Model? model;
  final EmbeddingModel? embeddingModel;
  final PreferredBackend? backend;
  final PreferredBackend? embeddingBackend;

  const LastSelection(this.model, this.embeddingModel, this.backend, this.embeddingBackend);
}

class LastSelectionPrefs {
  static const _kModel = 'last_model';
  static const _kBackend = 'last_backend';
  static const _kEmbeddingModel = 'last_embedding_model';
  static const _kEmbeddingBackend = 'last_embedding_backend';

  static Future<void> save(Model? model, PreferredBackend? backend, EmbeddingModel? embeddingModel, PreferredBackend? embeddingBackend) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kModel, model != null? model.name: "");
    await p.setString(_kEmbeddingModel, embeddingModel != null? embeddingModel.name: "");
    await p.setString(_kBackend, backend != null? backend.name: "");
    await p.setString(_kEmbeddingBackend, embeddingBackend != null? embeddingBackend.name: "");
  }

  static Future<LastSelection?> load() async {
    final p = await SharedPreferences.getInstance();
    final m = p.getString(_kModel);
    final em = p.getString(_kEmbeddingModel);
    final b = p.getString(_kBackend);
    final eb = p.getString(_kEmbeddingBackend);

    if (m == null && b == null && em == null) return null;

    try {
      debugPrint("[LastSelectionPrefs] Persisted data: Model: $m, Embedding Model: $em!");

      Model? model;
      if (m != null) {
        model = Model.values.firstWhereOrNull((e) => e.name == m);
      }

      EmbeddingModel? embeddingModel;
      if (em != null) {
        embeddingModel = EmbeddingModel.values.firstWhereOrNull((e) => e.name == em);
      }

      PreferredBackend? backend;
      if (b != null) {
        backend = PreferredBackend.values.firstWhereOrNull((e) => e.name == b);
      }

      PreferredBackend? embeddingBackend;
      if (eb != null) {
        embeddingBackend = PreferredBackend.values.firstWhereOrNull((e) => e.name == eb);
      }

      return LastSelection(model, embeddingModel, backend, embeddingBackend);
    } catch (e) {
      debugPrint("[LastSelectionPrefs] Failed to persist data: Model: $m, Embedding Model: $em!, Error: $e");
      return null;
    }
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kModel);
    await p.remove(_kEmbeddingModel);
    await p.remove(_kBackend);
    await p.remove(_kEmbeddingBackend);
  }
}
