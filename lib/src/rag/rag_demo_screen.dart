//IMP: Diff from example (large)

// CHANGES:
// 1. Added embedding model for showing its name on the screen
// 2. Added persistence of model's topK, threshold values to be used by other screens
// 3. Added auto-initialization of vector store if model present
// 4. addDocuments logic replaced with file picker instead of hardcoded sample docs
// 5. Cosmetic changes like bg color, title, text, sized boxes etc

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';
import 'package:get_storage/get_storage.dart';

import 'widgets/search_parameters_section.dart';
import 'widgets/status_card.dart';
import 'widgets/knowledge_base_section.dart';
import 'widgets/search_section.dart';
import 'widgets/result_card.dart';

import '../models/embedding_model.dart' as em;

/// Get database path - returns virtual path on web, real path on mobile
Future<String> _getDatabasePath(String filename) async {
  if (kIsWeb) {
    return filename;
  } else {
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/$filename';
  }
}

class RagDemoScreen extends StatefulWidget {
  final em.EmbeddingModel model; // IMP CHANGED: Added for showing model name

  const RagDemoScreen({super.key, required this.model}); // IMP CHANGED: Added model

  @override
  State<RagDemoScreen> createState() => _RagDemoScreenState();
}

class _RagDemoScreenState extends State<RagDemoScreen> {
  final TextEditingController _searchController = TextEditingController(
    text: '', // IMP CHANGED
  );

  bool _isInitialized = false;
  bool _isLoading = false;
  bool _hasEmbeddingModel = false;
  String _statusMessage = 'Checking embedding model...';
  List<RetrievalResult> _results = [];
  VectorStoreStats? _stats;

  double _threshold = 0.0;
  int _topK = 5;

  int _addTimeMs = 0;
  int _searchTimeMs = 0;

  final storage = GetStorage(); // IMP CHANGED: Added for setting topK, threshold

  @override
  void initState() {
    super.initState();

    // IMP CHANGED: Load persisted values (or use defaults)
    _threshold = (storage.read('ragThreshold') as double?) ?? 0.80;
    _topK = (storage.read('ragTopK') as int?) ?? 5;

    _checkEmbeddingModel();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _checkEmbeddingModel() async {

    // Check if embedding model is already initialized
    final hasModel = FlutterGemmaPlugin.instance.initializedEmbeddingModel != null;

    setState(() {
      _hasEmbeddingModel = hasModel;
      _statusMessage = hasModel
          ? 'Embedding model ${widget.model.name} ready. Initialize VectorStore to begin.' // IMP CHANGED: Added model name
          : 'WARNING: No embedding model!\n'
              'Please create an embedding model first from the Embedding Models screen.';
      if (hasModel) { // IMP CHANGED: Added auto-initialization of vector store if model present
        _initializeVectorStore();
      }
    });
  }

  Future<void> _initializeVectorStore() async {
    if (!_hasEmbeddingModel) {
      _showError('Please install an embedding model first!');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Initializing VectorStore...';
    });

    try {
      final dbPath = await _getDatabasePath('rag_demo.db');
      await FlutterGemmaPlugin.instance.initializeVectorStore(dbPath);

      final stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();

      setState(() {
        _isInitialized = true;
        _stats = stats;
        _statusMessage = 'Embedding model ${widget.model.name} ready.\nVectorStore initialized! ${stats.documentCount} lines stored.'; // IMP CHANGED: Added model name
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[RagDemo] Error initializing VectorStore: $e');
      setState(() {
        _isLoading = false;
        _statusMessage = 'Error initializing VectorStore: $e';
      });
    }
  }



  /////////////////////////
  // IMP CHANGED: Replaced with file picker instead of hardcoded sample docs
  /*
  Future<void> _addDocuments() async {
    if (!_isInitialized) {
      _showError('Please initialize VectorStore first!');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Adding documents...';
    });

    final stopwatch = Stopwatch()..start();

    try {
      // Collect all content texts
      final contents = sampleDocuments.map((d) => d['content']!).toList();

      // Batch embedding - one call instead of multiple
      final embeddingModel = FlutterGemmaPlugin.instance.initializedEmbeddingModel!;
      final embeddings = await embeddingModel.generateEmbeddings(contents);

      // Add documents with pre-computed embeddings
      for (int i = 0; i < sampleDocuments.length; i++) {
        await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
          id: sampleDocuments[i]['id']!,
          content: sampleDocuments[i]['content']!,
          embedding: embeddings[i],
          metadata: '{"source": "sample"}',
        );
      }

      stopwatch.stop();

      final stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();

      setState(() {
        _stats = stats;
        _addTimeMs = stopwatch.elapsedMilliseconds;
        _statusMessage = 'Added ${sampleDocuments.length} documents in ${_addTimeMs}ms';
        _isLoading = false;
      });
    } catch (e) {
      stopwatch.stop();
      debugPrint('[RagDemo] Error adding documents: $e');
      setState(() {
        _isLoading = false;
        _statusMessage = 'Error adding documents: $e';
      });
    }
  }

   */
  Future<void> _addDocuments(List<PlatformFile> files) async {
    if (!_isInitialized) {
      _showError('Please initialize VectorStore first!');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Preparing documents...';
    });

    final stopwatch = Stopwatch()..start();

    try {
      final supportedExtensions = {'txt', 'md', 'csv', 'json'};
      final validFiles = files.where((f) {
        final ext = f.extension?.toLowerCase();
        return f.path != null && ext != null && supportedExtensions.contains(ext);
      }).toList();

      if (validFiles.isEmpty) throw Exception('No supported text files found.');

      // 1. Read full content
      final contents = await Future.wait(
          validFiles.map((f) => File(f.path!).readAsString())
      );

      // 2. Pre-process ALL files to get total line count and prepared data
      List<List<String>> processedFilesLines = [];
      int totalLines = 0;

      for (var content in contents) {
        final lines = content
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .map((l) => l.length >  widget.model.maxSeqLen ? l.substring(0,  widget.model.maxSeqLen) : l)
            .toList();

        processedFilesLines.add(lines);
        totalLines += lines.length;
      }

      if (totalLines == 0) throw Exception('No valid text lines found in files.');

      final embeddingModel = FlutterGemmaPlugin.instance.initializedEmbeddingModel!;
      int currentProgress = 0;

      // 3. Process each file using the pre-calculated list
      String finalString = "";
      for (int i = 0; i < validFiles.length; i++) {
        final lines = processedFilesLines[i];
        if (lines.isEmpty) continue;


        // Update progress
        setState(() {
          _statusMessage = 'Generating embeddings and adding documents (line-by-line)...';
        });


        // Generate embeddings for all lines in this file (batch)
        final lineEmbeddings = await embeddingModel.generateEmbeddings(lines);

        // Add each line as a document
        for (int j = 0; j < lines.length; j++) {
          await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
            id: '${validFiles[i].name}_line$j', // Unique ID for every line
            content: lines[j],
            embedding: lineEmbeddings[j],
            metadata: '{"source": "${validFiles[i].name}"}',
          );

          // Update progress
          currentProgress++;
          setState(() {
            _statusMessage = 'Adding documents (line-by-line)...\n$currentProgress/$totalLines';
          });
          finalString += lines[j];
        }
      }

      storage.write('isRagInitialized', true);
      storage.write('lastUploadedRagData', finalString);

      stopwatch.stop();
      final stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();

      setState(() {
        _stats = stats;
        _addTimeMs = stopwatch.elapsedMilliseconds;
        _statusMessage = 'Added $totalLines lines from ${validFiles.length} files in ${_addTimeMs}ms';
        _isLoading = false;
      });
    } catch (e) {
      stopwatch.stop();
      debugPrint('[RagDemo] Error adding documents: $e');
      setState(() {
        _isLoading = false;
        _statusMessage = 'Error: $e';
      });
    }
  }
  /////////////////////////

  Future<void> _clearDocuments() async {
    if (!_isInitialized) {
      _showError('Please initialize VectorStore first!');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Clearing documents...';
    });

    try {
      await FlutterGemmaPlugin.instance.clearVectorStore();

      final stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();

      setState(() {
        _stats = stats;
        _results = [];
        _statusMessage = 'All documents cleared';
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[RagDemo] Error clearing documents: $e');
      setState(() {
        _isLoading = false;
        _statusMessage = 'Error clearing documents: $e';
      });
    }
  }

  Future<void> _search() async {
    if (!_isInitialized) {
      _showError('Please initialize VectorStore first!');
      return;
    }

    final query = _searchController.text.trim();
    if (query.isEmpty) {
      _showError('Please enter a search query');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Searching...';
    });

    final stopwatch = Stopwatch()..start();

    try {
      final results = await FlutterGemmaPlugin.instance.searchSimilar(
        query: query,
        topK: _topK,
        threshold: _threshold,
      );

      stopwatch.stop();

      setState(() {
        _results = results;
        _searchTimeMs = stopwatch.elapsedMilliseconds;
        _statusMessage = 'Found ${results.length} results in ${_searchTimeMs}ms';
        _isLoading = false;
      });
    } catch (e) {
      stopwatch.stop();
      debugPrint('[RagDemo] Search error: $e');
      setState(() {
        _isLoading = false;
        _statusMessage = 'Search error: $e';
      });
    }
  }

  void _showError(String message) {
    debugPrint('[RagDemo] ERROR: $message');
  }


  @override
  Widget build(BuildContext context) {

    // IMP CHANGED: Added for bg color
    final int? v = storage.read('llmWidgetBackgroundColor');
    final bg = v != null ? Color(v) : Colors.blueGrey[200]!;

    return Scaffold(
      backgroundColor: bg, // IMP CHANGED: Added
      appBar: AppBar(
        backgroundColor: bg, // IMP CHANGED: Added
        /////////
        // IMP CHANGED: Replaced
        /*
        title: const Text('RAG Demo'),
         */
        title:
          Text(
            'RAG Input & Settings',
            style: const TextStyle(fontSize: 21, color: Colors.blueGrey),
            softWrap: true,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        /////////
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.blueGrey,),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StatusCard(
              hasEmbeddingModel: _hasEmbeddingModel,
              statusMessage: _statusMessage,
              stats: _stats,
            ),
            const SizedBox(height: 16),

            // Initialize Button
            if (!_isInitialized)
              ElevatedButton.icon(
                onPressed: _isLoading || !_hasEmbeddingModel ? null : _initializeVectorStore,
                icon: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.storage),
                label: const Text('Initialize VectorStore'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),

            if (_isInitialized) ...[
              const SizedBox(height: 48), // IMP CHANGED: Added

              KnowledgeBaseSection(
                isLoading: _isLoading,
                addTimeMs: _addTimeMs,
                onAddDocuments: _addDocuments,
                onClearDocuments: _clearDocuments,
              ),
              const SizedBox(height: 48), // IMP CHANGED: Added

              ///////////////
              // IMP CHANGED: TopK and Threshold setter added in a separate section
              // Search Parameters Section (Persists changes)
              SearchParametersSection(
                threshold: _threshold,
                topK: _topK,
                onThresholdChanged: (value) {
                  setState(() => _threshold = value);
                  storage.write('ragThreshold', value); // IMP CHANGED: Save to storage
                },
                onTopKChanged: (value) {
                  setState(() => _topK = value);
                  storage.write('ragTopK', value); // IMP CHANGED: Save to storage
                },
              ),
              ///////////////


              const SizedBox(height: 24),

              SearchSection(
                controller: _searchController,
                isLoading: _isLoading,
                searchTimeMs: _searchTimeMs,
                onSearch: _search,
              ),
              const SizedBox(height: 24),


              // Results Section
              if (_results.isNotEmpty) ...[
                const Text(
                  'Results',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ..._results.map((result) => ResultCard(result: result)),
              ],
            ],
          ],
        ),
      ),
    );
  }
}