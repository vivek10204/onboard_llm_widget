//IMP: Diff from example (new)

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';
import 'package:get_storage/get_storage.dart';
import 'models/model.dart';
import 'models/base_model.dart';
import 'models/embedding_model.dart' as em;
import 'services/model_download_service.dart';
import 'services/auth_token_service.dart';

class PreloadScreen extends StatefulWidget {
  final Model? model;
  final PreferredBackend? backend;
  final em.EmbeddingModel? embeddingModel;
  final PreferredBackend? embeddingBackend;
  final String? preloadInputData;
  final bool preloadInputDataMandatory;

  final bool isChatModelAlreadyDone;
  final bool isEmbeddingModelAlreadyDone;

  const PreloadScreen({
    super.key,
    this.model,
    this.backend,
    this.embeddingModel,
    this.embeddingBackend,
    this.preloadInputData,
    this.preloadInputDataMandatory = false,
    this.isChatModelAlreadyDone = false,
    this.isEmbeddingModelAlreadyDone = false,
  });

  @override
  State<PreloadScreen> createState() => _PreloadScreenState();
}

class _PreloadScreenState extends State<PreloadScreen> {
  final TextEditingController _tokenController = TextEditingController();

  // --- Progress State ---
  double _modelProgress = 0.0;
  double _embeddingProgress = 0.0;

  // --- Completion Flags ---
  late bool _isChatModelDone;
  bool _isChatModelInitDone = false;
  late bool _isEmbeddingDone;
  bool _isEmbeddingInitDone = false;
  bool _isDataUploadDone = false;

  // --- Active Processing Flags ---
  bool _processingChatDownload = false;
  bool _processingChatInit = false;
  bool _processingEmbeddingDownload = false;
  bool _processingEmbeddingInit = false;
  bool _processingDataUpload = false;

  // --- Indeterminate Loading Flags ---
  bool _isChatInitIndeterminate = false;
  bool _isEmbeddingInitIndeterminate = false;
  bool _isDataUploadIndeterminate = false;

  // --- UI State ---
  String _status = "Initializing parallel setup...";
  bool _showRetry = false;
  bool _needsTokenInput = false;
  bool _forceTokenInput = false;

  final storage = GetStorage();

  @override
  void initState() {
    super.initState();
    _isChatModelDone = widget.isChatModelAlreadyDone;
    _isEmbeddingDone = widget.isEmbeddingModelAlreadyDone;

    if (_isChatModelDone) _modelProgress = 1.0;
    if (_isEmbeddingDone) _embeddingProgress = 1.0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startParallelExecution();
    });
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  // ==========================================
  // CHANGE 1: NATIVE CACHE CLEANER
  // ==========================================
  Future<void> _clearNativeCache() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      if (cacheDir.existsSync()) {
        final files = cacheDir.listSync();
        for (var file in files) {
          // Deleting XNNPACK caches prevents the "Cannot reserve space" SIGABRT crash
          if (file.path.contains('.xnnpack_cache') || file.path.contains('tflite')) {
            await file.delete();
            debugPrint("Deleted problematic native cache: ${file.path}");
          }
        }
      }
    } catch (e) {
      debugPrint("Cache cleaning failed: $e");
    }
  }

  // ==========================================
  // CHANGE 2: STAGGERED MASTER CONTROLLER
  // ==========================================
  void _startParallelExecution({bool forceToken = false}) async {
    if (mounted) {
      setState(() {
        _showRetry = false;
        _needsTokenInput = false;
        _status = "Starting setup...";
        _forceTokenInput = forceToken;
      });
    }

    // Launch Chat track immediately
    final chatTrack = _runChatTrack();

    // Delay the RAG track slightly. This prevents the "Access Denied" ro.mediatek property
    // errors caused by multiple JNI initializations firing at the exact same millisecond.
    await Future.delayed(const Duration(milliseconds: 800));
    final ragTrack = _runRagTrack();

    final results = await Future.wait([chatTrack, ragTrack]);

    if (results[0] && results[1]) {
      _finishAll();
    }
  }

  void _onRetry() {
    bool failedDownload = (_processingChatDownload && !_isChatModelDone) ||
        (_processingEmbeddingDownload && !_isEmbeddingDone);

    _startParallelExecution(forceToken: failedDownload);
  }

  // ==========================================
  // CHANGE 3: ROBUST CANCEL LOGIC
  // ==========================================
  void _onCancel() async {
    if (mounted) {
      setState(() {
        _status = "Cleaning native resources...";
        _showRetry = true; // Signals all tracks to stop immediately
      });
    }

    // Clear the TFLite cache to ensure a clean slate for the next attempt
    await _clearNativeCache();

    // Force unlock all storage variables
    storage.write('isChatInitLocked', false);
    storage.write('isEmbeddingInitLocked', false);
    storage.write('isRagUploadLocked', false);

    if (mounted) {
      setState(() {
        _processingChatDownload = false;
        _processingChatInit = false;
        _processingEmbeddingDownload = false;
        _processingEmbeddingInit = false;
        _processingDataUpload = false;
        _status = "Operation cancelled.";
      });
    }
  }

  Future<void> _finishAll() async {
    if (_showRetry) return;

    if (mounted) {
      setState(() => _status = "All Setup Complete!");
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) Navigator.pop(context, true);
    }
  }

  // ==========================================
  // TRACK A: CHAT MODEL (Download -> Init)
  // ==========================================

  Future<bool> _runChatTrack() async {
    if (widget.model == null) return true;
    if (_showRetry) return false;

    try {
      // Step 1: Download
      if (!_isChatModelDone) {
        if (mounted) setState(() => _processingChatDownload = true);
        await _downloadGeneric(
          url: widget.model!.url,
          filename: widget.model!.filename,
          licenseUrl: widget.model!.licenseUrl,
          needsAuth: widget.model!.needsAuth,
          displayName: widget.model!.displayName,
          onProgress: (p) {
            if (!_showRetry) setState(() => _modelProgress = p);
          },
        );
        if (_showRetry) return false;

        if (mounted) {
          setState(() {
            _isChatModelDone = true;
            _processingChatDownload = false;
            _modelProgress = 1.0;
          });
        }
      }

      // Step 2: Initialize
      if (!_isChatModelInitDone) {
        if (mounted) {
          setState(() {
            _processingChatInit = true;
            _isChatInitIndeterminate = true;
          });
        }

        while (storage.read('isChatInitLocked') ?? false) {
          if (_showRetry) return false;
          if (mounted) setState(() => _status = "Chat Init locked (waiting)...");
          await Future.delayed(const Duration(seconds: 2));
        }

        if (_showRetry) return false;
        storage.write('isChatInitLocked', true);

        try {
          await _initializeChatModel();
          if (mounted) {
            setState(() {
              _isChatModelInitDone = true;
              _processingChatInit = false;
              _isChatInitIndeterminate = false;
            });
          }
        } finally {
          storage.write('isChatInitLocked', false);
        }
      }

      return true;
    } catch (e) {
      debugPrint("Chat Track Error: $e");
      storage.write('isChatInitLocked', false);

      if (e.toString().contains('416')) {
        try {
          final dir = await getApplicationDocumentsDirectory();
          final file = File('${dir.path}/${widget.model!.filename}');
          if (file.existsSync()) await file.delete();
        } catch (_) {}
      }

      if (e is _AuthRequiredException) {
        if (mounted) setState(() => _needsTokenInput = true);
      } else {
        if (mounted && !_showRetry) {
          setState(() {
            _status = "Chat Model Error: $e";
            _showRetry = true;
            _processingChatDownload = false;
            _processingChatInit = false;
          });
        }
      }
      return false;
    }
  }

  Future<void> _initializeChatModel() async {
    final installer = FlutterGemma.installModel(
      modelType: widget.model!.modelType,
      fileType: widget.model!.fileType,
    );

    if (widget.model!.localModel) {
      await installer.fromAsset(widget.model!.url).install();
    } else {
      String? token = widget.model!.needsAuth ? await AuthTokenService.loadToken() : null;
      await installer.fromNetwork(widget.model!.url, token: token).install();
    }

    await FlutterGemma.getActiveModel(
      maxTokens: widget.model!.maxTokens * 2,
      preferredBackend: widget.backend ?? widget.model!.preferredBackend,
      supportImage: widget.model!.supportImage,
      maxNumImages: widget.model!.maxNumImages,
    );
  }

  // ==========================================
  // TRACK B: RAG MODEL (Download -> Init -> Upload)
  // ==========================================

  Future<bool> _runRagTrack() async {
    if (widget.embeddingModel == null && !widget.preloadInputDataMandatory) return true;
    if (_showRetry) return false;

    try {
      // Step 1: Download Embedding Model
      if (widget.embeddingModel != null && !_isEmbeddingDone) {
        if (mounted) setState(() => _processingEmbeddingDownload = true);

        await _downloadGeneric(
          url: widget.embeddingModel!.url,
          filename: widget.embeddingModel!.filename,
          licenseUrl: null,
          needsAuth: widget.embeddingModel!.needsAuth,
          displayName: widget.embeddingModel!.displayName,
          onProgress: (p) { if(!_showRetry) setState(() => _embeddingProgress = p * 0.5); },
        );

        if (_showRetry) return false;

        await _downloadGeneric(
          url: widget.embeddingModel!.tokenizerUrl,
          filename: 'tokenizer.json',
          licenseUrl: null,
          needsAuth: widget.embeddingModel!.needsAuth,
          displayName: "${widget.embeddingModel!.displayName} Tokenizer",
          onProgress: (p) { if(!_showRetry) setState(() => _embeddingProgress = 0.5 + (p * 0.5)); },
        );

        if (_showRetry) return false;

        if (mounted) {
          setState(() {
            _isEmbeddingDone = true;
            _processingEmbeddingDownload = false;
            _embeddingProgress = 1.0;
          });
        }
      }

      // Step 2: Initialize Embedding Model
      if (widget.embeddingModel != null && !_isEmbeddingInitDone) {
        if (mounted) setState(() { _processingEmbeddingInit = true; _isEmbeddingInitIndeterminate = true; });
        await _initializeEmbeddingModelWithLock();
        if (mounted) setState(() { _isEmbeddingInitDone = true; _processingEmbeddingInit = false; _isEmbeddingInitIndeterminate = false; });
      }

      // Step 3: Upload Data
      if (widget.preloadInputDataMandatory && widget.preloadInputData != null && !_isDataUploadDone) {
        if (mounted) setState(() { _processingDataUpload = true; _isDataUploadIndeterminate = true; });
        await _uploadDataWithLock();
        if (mounted) setState(() { _isDataUploadDone = true; _processingDataUpload = false; _isDataUploadIndeterminate = false; });
      }

      return true;
    } catch (e) {
      debugPrint("RAG Track Error: $e");
      if (e.toString().contains('416')) {
        try {
          final dir = await getApplicationDocumentsDirectory();
          final modelFile = File('${dir.path}/${widget.embeddingModel!.filename}');
          if (modelFile.existsSync()) await modelFile.delete();
          final tokenizerFile = File('${dir.path}/tokenizer.json');
          if (tokenizerFile.existsSync()) await tokenizerFile.delete();
        } catch (_) {}
      }

      if (e is _AuthRequiredException) {
        if (mounted) setState(() => _needsTokenInput = true);
      } else {
        if (mounted && !_showRetry) {
          setState(() {
            _status = "RAG Setup Error: $e";
            _showRetry = true;
            _processingEmbeddingDownload = false;
            _processingEmbeddingInit = false;
            _processingDataUpload = false;
          });
        }
      }
      return false;
    }
  }

  Future<void> _initializeEmbeddingModelWithLock() async {
    while (storage.read('isEmbeddingInitLocked') ?? false) {
      if (_showRetry) return;
      if (mounted) setState(() => _status = "RAG Init locked (waiting)...");
      await Future.delayed(const Duration(seconds: 2));
      if (FlutterGemmaPlugin.instance.initializedEmbeddingModel != null) return;
    }

    if (FlutterGemmaPlugin.instance.initializedEmbeddingModel != null) return;
    if (_showRetry) return;

    storage.write('isEmbeddingInitLocked', true);
    try {
      await _actualEmbeddingInit();
    } finally {
      storage.write('isEmbeddingInitLocked', false);
    }
  }

  Future<void> _actualEmbeddingInit() async {
    String? token = widget.embeddingModel!.needsAuth ? await AuthTokenService.loadToken() : null;
    var builder = FlutterGemma.installEmbedder();
    if (widget.embeddingModel!.sourceType == ModelSourceType.network) {
      builder = builder.modelFromNetwork(widget.embeddingModel!.url, token: token)
          .tokenizerFromNetwork(widget.embeddingModel!.tokenizerUrl, token: token);
    } else {
      builder = builder.modelFromAsset(widget.embeddingModel!.url)
          .tokenizerFromAsset(widget.embeddingModel!.tokenizerUrl);
    }

    await builder.install();
    await FlutterGemma.getActiveEmbedder(preferredBackend: widget.embeddingBackend ?? PreferredBackend.cpu);
  }

  Future<void> _uploadDataWithLock() async {
    while (storage.read('isRagUploadLocked') ?? false) {
      if (_showRetry) return;
      if (mounted) setState(() => _status = "Data Upload locked (waiting)...");
      await Future.delayed(const Duration(seconds: 5));
      if (await _verifyDataUpload()) return;
    }

    if (await _verifyDataUpload()) return;
    if (_showRetry) return;

    storage.write('isRagUploadLocked', true);
    try {
      await _actualDataUpload();
    } finally {
      storage.write('isRagUploadLocked', false);
    }
  }

  Future<bool> _verifyDataUpload() async {
    final ragInitialized = (storage.read('isRagInitialized') as bool?) ?? false;
    final lastUploaded = storage.read('lastUploadedRagData') as String?;
    return ragInitialized && (lastUploaded == widget.preloadInputData);
  }

  Future<void> _actualDataUpload() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dbPath = kIsWeb ? 'rag_demo.db' : '${appDir.path}/rag_demo.db';

    await FlutterGemmaPlugin.instance.initializeVectorStore(dbPath);
    if (!kIsWeb) {
      final dbFile = File(dbPath);
      if (await dbFile.exists()) await dbFile.delete();
    }
    await FlutterGemmaPlugin.instance.clearVectorStore();

    final lines = widget.preloadInputData!
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      storage.write('isRagInitialized', true);
      storage.write('lastUploadedRagData', widget.preloadInputData);
      return;
    }

    final embeddingModel = FlutterGemmaPlugin.instance.initializedEmbeddingModel!;
    int threadCount = 10;
    int chunkSize = (lines.length / (lines.length < threadCount ? lines.length : threadCount)).ceil();

    List<Future<void>> tasks = [];
    for (int i = 0; i < lines.length; i += chunkSize) {
      final end = (i + chunkSize < lines.length) ? i + chunkSize : lines.length;
      final batchLines = lines.sublist(i, end);
      final batchStartIndex = i;

      tasks.add(() async {
        try {
          final batchEmbeddings = await embeddingModel.generateEmbeddings(batchLines);
          for (int j = 0; j < batchLines.length; j++) {
            await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
              id: 'preload_doc_${batchStartIndex + j}',
              content: batchLines[j],
              embedding: batchEmbeddings[j],
            );
          }
        } catch (e) { debugPrint("Batch Error: $e"); }
      }());
    }
    await Future.wait(tasks);
    storage.write('isRagInitialized', true);
    storage.write('lastUploadedRagData', widget.preloadInputData);
  }

  Future<void> _downloadGeneric({
    required String url,
    required String filename,
    required String? licenseUrl,
    required bool needsAuth,
    required String displayName,
    required Function(double) onProgress,
  }) async {
    final downloadService = ModelDownloadService(modelUrl: url, modelFilename: filename, licenseUrl: licenseUrl ?? '');
    String token = '';
    if (needsAuth) {
      final savedToken = await downloadService.loadToken();
      if (!_forceTokenInput && savedToken != null && savedToken.isNotEmpty) {
        token = savedToken;
      } else {
        throw _AuthRequiredException();
      }
    }
    await downloadService.startDownload(token: token, onProgress: onProgress);
  }

  Future<void> _saveAndStartDownload() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid token')));
      return;
    }
    await ModelDownloadService(modelUrl: '', modelFilename: '', licenseUrl: '').saveToken(token);
    _startParallelExecution(forceToken: false);
  }

  Future<bool> _onWillPop() async {
    if (!_processingChatDownload && !_processingEmbeddingDownload &&
        !_processingChatInit && !_processingEmbeddingInit && !_processingDataUpload) {
      return true;
    }
    final shouldStop = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop Preload?'),
        content: const Text('Going back will stop the setup process.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Stop & Go Back')),
        ],
      ),
    );
    return shouldStop ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final int? v = storage.read('llmWidgetBackgroundColor');
    final bg = v != null ? Color(v) : Colors.blueGrey[200]!;

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: bg,
        body: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: _needsTokenInput ? _buildTokenInput() : _buildProgressView(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTokenInput() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.lock_outline, size: 60, color: Colors.white70),
        const SizedBox(height: 24),
        const Text("Authentication Required", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        const Text("A Hugging Face token is required to download these models.", style: TextStyle(color: Colors.white70), textAlign: TextAlign.center),
        const SizedBox(height: 24),
        TextField(
          controller: _tokenController,
          obscureText: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'HuggingFace Access Token',
            labelStyle: TextStyle(color: Colors.white60),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.blue)),
            prefixIcon: Icon(Icons.key, color: Colors.white60),
          ),
          onSubmitted: (_) => _saveAndStartDownload(),
        ),
        const SizedBox(height: 16),
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: const TextStyle(color: Colors.white60, fontSize: 12),
            children: [
              const TextSpan(text: 'Get your token at '),
              TextSpan(
                text: 'huggingface.co/settings/tokens',
                style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline),
                recognizer: TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse('https://huggingface.co/settings/tokens')),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saveAndStartDownload,
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: Colors.blue),
            child: const Text("Save & Resume", style: TextStyle(color: Colors.white)),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressView() {
    bool isProcessing = _processingChatDownload || _processingChatInit ||
        _processingEmbeddingDownload || _processingEmbeddingInit ||
        _processingDataUpload;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text("Setting up your AI Experience", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        const SizedBox(height: 40),

        if (widget.model != null) ...[
          _buildStep(
            "Downloading Chat Model (${widget.model!.displayName})",
            _modelProgress,
            isActive: _processingChatDownload,
            isDone: _isChatModelDone,
          ),
          const SizedBox(height: 20),
          _buildStep(
            "Initializing Chat Model",
            _isChatInitIndeterminate ? null : 1.0,
            isActive: _processingChatInit,
            isDone: _isChatModelInitDone,
            isWaiting: !_isChatModelDone,
            isIndeterminate: _isChatInitIndeterminate,
          ),
          const SizedBox(height: 20),
        ],

        if (widget.embeddingModel != null) ...[
          _buildStep(
            "Downloading RAG Model (${widget.embeddingModel!.displayName})",
            _embeddingProgress,
            isActive: _processingEmbeddingDownload,
            isDone: _isEmbeddingDone,
          ),
          const SizedBox(height: 20),
          _buildStep(
            "Initializing RAG Model",
            _isEmbeddingInitIndeterminate ? null : 1.0,
            isActive: _processingEmbeddingInit,
            isDone: _isEmbeddingInitDone,
            isWaiting: !_isEmbeddingDone,
            isIndeterminate: _isEmbeddingInitIndeterminate,
          ),
          const SizedBox(height: 20),
        ],

        if (widget.preloadInputDataMandatory)
          _buildStep(
            "Uploading Knowledge Base",
            _isDataUploadIndeterminate ? null : 1.0,
            isActive: _processingDataUpload,
            isDone: _isDataUploadDone,
            isWaiting: !_isEmbeddingInitDone,
            isIndeterminate: _isDataUploadIndeterminate,
          ),

        const SizedBox(height: 40),
        Text(_status, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),

        SizedBox(
          height: 80,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 20.0),
              child: _showRetry
                  ? ElevatedButton.icon(
                onPressed: _onRetry,
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const Text("Retry", style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12)),
              )
                  : isProcessing
                  ? ElevatedButton.icon(
                onPressed: _onCancel,
                icon: const Icon(Icons.cancel, color: Colors.white),
                label: const Text("Cancel", style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade700, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12)),
              )
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep(String title, double? progress, {required bool isActive, bool isDone = false, bool isWaiting = false, bool isIndeterminate = false}) {
    IconData icon;
    Color color;

    if (isDone) {
      icon = Icons.check_circle;
      color = Colors.green;
    } else if (isActive) {
      icon = Icons.downloading;
      color = Colors.blue;
    } else if (isWaiting) {
      icon = Icons.access_time;
      color = Colors.grey.shade700;
    } else {
      icon = Icons.radio_button_unchecked;
      color = Colors.grey;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: TextStyle(color: (isActive || isDone) ? Colors.white : Colors.grey))),
          ],
        ),
        if (isActive) ...[
          const SizedBox(height: 8),
          if (isIndeterminate)
            const LinearProgressIndicator()
          else
            LinearProgressIndicator(value: progress ?? 0.0),
          if (!isIndeterminate && progress != null)
            Align(alignment: Alignment.centerRight, child: Text("${(progress * 100).toStringAsFixed(0)}%", style: const TextStyle(color: Colors.white54, fontSize: 12))),
        ]
      ],
    );
  }
}

class _AuthRequiredException implements Exception {}