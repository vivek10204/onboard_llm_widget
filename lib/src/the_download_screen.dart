//IMP: Diff from example (new). Merged.

import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:get_storage/get_storage.dart';

import 'package:flutter_gemma/flutter_gemma.dart';

import 'chat_screen.dart';

import 'services/model_download_service.dart';
import 'services/embedding_download_service.dart';
import 'services/last_selection_prefs.dart';
import 'services/auth_token_service.dart';

import 'models/base_model.dart';
import 'models/model.dart';
import 'models/embedding_model.dart' as em;

class TheDownloadScreen extends StatefulWidget {
  final BaseModel model;
  final PreferredBackend? selectedBackend;

  const TheDownloadScreen({
    super.key,
    required this.model,
    this.selectedBackend
  });

  @override
  State<TheDownloadScreen> createState() => _TheDownloadScreenState();
}

class _TheDownloadScreenState extends State<TheDownloadScreen> {
  // Service for Inference
  ModelDownloadService? _inferenceDownloadService;
  // Service for Embeddings
  EmbeddingModelDownloadService? _embeddingDownloadService;

  bool needToDownload = true;

  // IMP CHANGED: Added checking status to prevent "briefly seeing download button" on load
  bool _isCheckingStatus = true;
  // IMP CHANGED: Added explicit flag to prevent "briefly seeing button" between model/tokenizer downloads
  bool _isDownloadingEmbedding = false;

  // Progress tracking
  double _progress = 0.0; // Inference
  double _modelProgress = 0.0; // Embedding
  double _tokenizerProgress = 0.0; // Embedding

  String _token = '';
  final TextEditingController _tokenController = TextEditingController();

  // Sticky Progress Subscription
  StreamSubscription<double>? _progressSub;

  // Helper to check type
  bool get isEmbedding => widget.model.isEmbeddingModel;

  final storage = GetStorage();

  @override
  void initState() {
    super.initState();
    _initializeServices();

    // Attach "sticky" download logic
    _initialize().then((_) {
      if (!isEmbedding && _inferenceDownloadService != null) {
        setState(() {
          _progress = _inferenceDownloadService!.currentProgress;
        });

        _progressSub = _inferenceDownloadService!.progressStream.listen((p) async {
          if (!mounted) return;
          setState(() => _progress = p);

          if (p >= 1.0) {
            final hasFile = await _fileExistsLocally();
            if (!mounted) return;
            setState(() {
              needToDownload = !hasFile;
            });
          }
        });
      }
    });
  }

  void _initializeServices() {
    if (isEmbedding) {
      _embeddingDownloadService = EmbeddingModelDownloadService(
        model: widget.model as em.EmbeddingModel,
      );
    } else {
      _inferenceDownloadService = ModelDownloadService(
        modelUrl: widget.model.url,
        modelFilename: widget.model.filename,
        licenseUrl: widget.model.licenseUrl ?? '',
      );
    }
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _tokenController.dispose();
    super.dispose();
  }

  Future<bool> _fileExistsLocally() async {
    try {
      if (isEmbedding) {
        return await _embeddingDownloadService!.checkModelExistence(_token);
      } else {
        final path = await _inferenceDownloadService!.getFilePath();
        final f = File(path);
        return f.existsSync() && (await f.length()) > 0;
      }
    } catch (_) {
      return false;
    }
  }

  Future<void> _initialize() async {
    if (isEmbedding) {
      _token = await _embeddingDownloadService!.loadToken() ?? '';
      bool exists = await _embeddingDownloadService!.checkModelExistence(_token);
      needToDownload = !exists;
    } else {
      _token = await _inferenceDownloadService!.loadToken() ?? '';
      bool exists = await _inferenceDownloadService!.checkModelExistence(_token);
      needToDownload = !exists;
    }
    _tokenController.text = _token;

    // IMP CHANGED: Turn off checking status once done
    if (mounted) setState(() { _isCheckingStatus = false; });
  }

  Future<void> _saveToken(String token) async {
    // IMP CHANGED: Set checking status true while saving/reloading
    setState(() { _isCheckingStatus = true; });
    if (isEmbedding) {
      await _embeddingDownloadService!.saveToken(token);
    } else {
      await _inferenceDownloadService!.saveToken(token);
    }
    await _initialize();
  }

  Future<void> _selectRagModel() async {
    await _initializeEmbeddingModelIfNeeded();

    final embeddingModel = widget.model as em.EmbeddingModel;
    final embeddingBackend = widget.selectedBackend;

    final saved = await LastSelectionPrefs.load();
    Model? model;
    PreferredBackend? backend;
    if (saved != null) {
      model = saved.model;
      backend = saved.backend;
    }

    await LastSelectionPrefs.save(model, backend, embeddingModel, embeddingBackend);
    debugPrint("RAG Model Selected: ${embeddingModel.name}");

    if (mounted) Navigator.pop(context);
  }

  Future<void> _selectModel() async {

    final model = widget.model as Model;
    final backend = widget.selectedBackend;

    final saved = await LastSelectionPrefs.load();
    em.EmbeddingModel? embeddingModel;
    PreferredBackend? embeddingBackend;
    if (saved != null) {
      embeddingModel = saved.embeddingModel;
      embeddingBackend = saved.embeddingBackend;
    }

    await LastSelectionPrefs.save(model, backend, embeddingModel, embeddingBackend);
    debugPrint("Chat Model Selected: ${model.name}");
  }

  Future<void> _initializeEmbeddingModelIfNeeded() async {
    try {
      final embeddingModel = widget.model as em.EmbeddingModel;

      String? token;
      if (embeddingModel.needsAuth) {
        final authToken = await AuthTokenService.loadToken();
        token = authToken?.isNotEmpty == true ? authToken : null;
      }

      var builder = FlutterGemma.installEmbedder();

      switch (embeddingModel.sourceType) {
        case ModelSourceType.network:
          builder = builder.modelFromNetwork(embeddingModel.url, token: token);
        case ModelSourceType.asset:
          builder = builder.modelFromAsset(embeddingModel.url);
        case ModelSourceType.bundled:
          builder = builder.modelFromBundled(embeddingModel.url);
      }

      switch (embeddingModel.sourceType) {
        case ModelSourceType.network:
          builder = builder.tokenizerFromNetwork(embeddingModel.tokenizerUrl, token: token);
        case ModelSourceType.asset:
          builder = builder.tokenizerFromAsset(embeddingModel.tokenizerUrl);
        case ModelSourceType.bundled:
          builder = builder.tokenizerFromBundled(embeddingModel.tokenizerUrl);
      }

      await builder.install();

      await FlutterGemma.getActiveEmbedder(preferredBackend: PreferredBackend.gpu);

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Embedding Init Error: $e");
    }
  }

  Future<void> _downloadModel() async {
    // IMP CHANGED: Idempotency check
    if (_isDownloadingEmbedding || (_inferenceDownloadService?.isDownloading ?? false)) {
      return;
    }

    final scaffoldMessenger = ScaffoldMessenger.of(context);

    if (widget.model.needsAuth) {
      final token = _tokenController.text.trim();
      if (token.isNotEmpty && token != _token) {
        await _saveToken(token);
      }
      if (_token.isEmpty) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Please set your token first.')),
        );
        return;
      }
    }

    setState(() {
      if (isEmbedding) _isDownloadingEmbedding = true; // Set flag
      _progress = 0.0;
      _modelProgress = 0.0;
      _tokenizerProgress = 0.0;
    });

    try {
      if (isEmbedding) {
        try {
          await _embeddingDownloadService!.deleteModel();
        } catch (e) {
          debugPrint("Pre-download cleanup error (ignorable): $e");
        }

        await _embeddingDownloadService!.downloadModel(
            widget.model.needsAuth ? _token : '',
                (modelProgress, tokenizerProgress) {
              if (mounted) {
                setState(() {
                  _modelProgress = modelProgress;
                  _tokenizerProgress = tokenizerProgress;
                });
              }
            }
        );

        final exists = await _embeddingDownloadService!.checkModelExistence(_token);
        if (mounted) {
          setState(() {
            needToDownload = !exists;
          });
        }
      } else {
        await _inferenceDownloadService!.startDownload(
          token: widget.model.needsAuth ? _token : '',
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
        );

        final localOk = await _fileExistsLocally();
        bool finalOk = localOk;

        if (!localOk) {
          final remoteOk = await _inferenceDownloadService!.checkModelExistence(_token);
          finalOk = remoteOk;
        }

        if (mounted) {
          setState(() {
            needToDownload = !finalOk;
          });
        }
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Failed to download: $e')),
      );
    } finally {
      // IMP CHANGED: Reset embedding download flag in finally block
      if (mounted && isEmbedding) {
        setState(() {
          _isDownloadingEmbedding = false;
        });
      }
    }
  }

  Future<void> _deleteModel() async {
    try {
      // IMP CHANGED: Set checking status to true while deleting to avoid flickering
      setState(() { _isCheckingStatus = true; });

      if (isEmbedding) {
        await _embeddingDownloadService!.deleteModel();
        if (mounted) {
          setState(() {
            needToDownload = true;
            _modelProgress = 0.0;
            _tokenizerProgress = 0.0;
          });
        }
      } else {
        await _inferenceDownloadService!.deleteModel();
        if (mounted) {
          setState(() {
            needToDownload = true;
            _progress = 0.0;
          });
        }
      }
    } catch (e) {
      debugPrint("Delete Error: $e");
    } finally {
      // IMP CHANGED: Reset checking status
      if (mounted) setState(() { _isCheckingStatus = false; });
    }
  }

  Future<void> _confirmAndDeleteModel() async {
    if (_inferenceDownloadService != null && _inferenceDownloadService!.isDownloading) return;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete model?'),
        content: const Text('This will remove the downloaded model from storage.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      await _deleteModel();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Model deleted')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final int? v = storage.read('llmWidgetBackgroundColor');
    final bg = v != null ? Color(v) : Colors.blueGrey[200]!;

    // IMP CHANGED: Updated Logic to use explicit flag for embeddings
    bool isDownloading = false;
    if (isEmbedding) {
      isDownloading = _isDownloadingEmbedding;
    } else {
      isDownloading = (_inferenceDownloadService?.isDownloading ?? false) && _progress < 1.0;
    }

    return Scaffold(
      backgroundColor: bg,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: bg,
        title: const Text('Model Download', style: TextStyle(fontSize: 21, color: Colors.blueGrey)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.blueGrey,),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text(
                'Download ${widget.model.displayName} Model\n',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.cyan),
                textAlign: TextAlign.center,
              ),
            ),

            if (widget.model.needsAuth) ...[
              TextField(
                controller: _tokenController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Enter HuggingFace AccessToken',
                  labelStyle: TextStyle(color: Colors.blueGrey),
                  hintText: 'Paste your Hugging Face access token here',
                  hintStyle: TextStyle(color: Colors.grey),
                ),
                onSubmitted: (val) async {
                  if (val.trim().isNotEmpty) {
                    await _saveToken(val.trim());
                  }
                },
              ),
              RichText(
                text: TextSpan(
                  style: const TextStyle(color: Colors.teal,),
                  text: '\n\nTo create an access token, visit ',
                  children: [
                    TextSpan(
                      text: 'https://huggingface.co/settings/tokens',
                      style: const TextStyle(
                        color: Colors.blue,
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () {
                          launchUrl(Uri.parse('https://huggingface.co/settings/tokens'));
                        },
                    ),
                    const TextSpan(
                      text: '. Make sure to give read-repo access to the token.',
                    ),
                  ],
                ),
              ),
            ],

            if (widget.model.licenseUrl != null && widget.model.licenseUrl!.isNotEmpty)
              RichText(
                text: TextSpan(
                  text: '\n\nLicense Agreement: ',
                  style: const TextStyle(color: Colors.teal,),
                  children: [
                    TextSpan(
                      text: "${widget.model.licenseUrl}\n\n",
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.blue,
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () {
                          launchUrl(Uri.parse(widget.model.licenseUrl!));
                        },
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 20),
            Center(
              // IMP CHANGED: Show spinner while checking status
              child: _isCheckingStatus
                  ? const CircularProgressIndicator()
                  : isDownloading
                  ? _buildProgressIndicator()
                  : ElevatedButton(
                onPressed: !needToDownload ? _confirmAndDeleteModel : _downloadModel,
                child: Text(!needToDownload ? 'Delete' : 'Download'),
              ),
            ),
          ],
        ),
      ),

      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(12.0),
        child: KeyboardVisibilityBuilder(
            builder: (context, isKeyboardVisible) {
              if (isKeyboardVisible) return const SizedBox.shrink();

              final label = isEmbedding ? 'Use RAG Model' : 'Use Chat Model';

              return SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: needToDownload
                      ? null
                      : () {
                    if (isEmbedding) {
                      _selectRagModel();
                    } else {
                      _selectModel();
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute<void>(
                          builder: (context) => ChatScreen(
                            model: widget.model as Model,
                            selectedBackend: widget.selectedBackend,
                          ),
                        ),
                      );
                    }
                  },
                  child: Text(
                    label,
                    style: const TextStyle(fontSize: 20, color: Colors.black45),
                  ),
                ),
              );
            }
        ),
      ),
    );
  }

  Widget _buildProgressIndicator() {
    if (isEmbedding) {
      return Column(
        children: [
          Text(
            'Model: ${_modelProgress.toStringAsFixed(1)}%',
            style: const TextStyle(color: Colors.blueGrey),
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: _modelProgress / 100),

          const SizedBox(height: 12),

          Text(
            'Tokenizer: ${_tokenizerProgress.toStringAsFixed(1)}%',
            style: const TextStyle(color: Colors.blueGrey),
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: _tokenizerProgress / 100),
        ],
      );
    } else {
      return Column(
        children: [
          Text(
            'Download Progress: ${(_progress * 100).toStringAsFixed(1)}%',
            style: const TextStyle(color: Colors.blueGrey),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: _progress == 0 ? null : _progress),
        ],
      );
    }
  }
}