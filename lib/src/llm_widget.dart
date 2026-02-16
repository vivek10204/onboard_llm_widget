//IMP: Diff from example (new)

// CHANGES:
// 1. Convert screen to widget (and embed within an outer screen)
// 2. Internal screen navigation within widget (ie. back swipe doesn't work for internal screens and only back arrow button works for internal screens)
// 3. maybeOpenChat if it was opened earlier (for saved model and preferred backend)
// 4. Save prompt bits like preamble etc so it can be used by chat_widget later, along with other details like background color and enableRag to be used by other widgets/screens down the line
// 5. Pass model ready status to PreloadScreen to skip redundant downloads
// 6. Verify Vector Store document count against preloadInputData line count
// 7. Added isPreloadSetupAccepted flag to auto-resume setup on restart without asking again
// ...

import 'dart:io' show File;
import 'package:get_storage/get_storage.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import 'package:flutter_gemma/flutter_gemma.dart'; // For EmbeddingModelSpec

import 'widgets/loading_widget.dart';

import 'models/model.dart';
import 'models/embedding_model.dart' as em;

import 'services/last_selection_prefs.dart';
import 'services/prompt_prefs.dart';
import 'services/auth_token_service.dart';

import 'the_selection_screen.dart';
import 'preload_screen.dart';
import 'chat_screen.dart';

PageRoute<T> noSwipeRoute<T>(Widget child) => PageRouteBuilder<T>(
  pageBuilder: (_, __, ___) => child,
  transitionsBuilder: (_, __, ___, child) => child,
);

class LlmWidget extends StatefulWidget {
  const LlmWidget({
    super.key,

    this.appName,
    this.chatAvatarImagePath,

    this.preamble,

    this.enableRag,
    this.enableRagButton1,
    this.enableRagButton2,

    ///////PRELOAD
    this.preloadModelsMandatory, //can be no, yes or ask

    this.preloadModelName,
    this.preloadModelBackend,

    this.preloadEmbeddingModelName,
    this.preloadEmbeddingModelBackend,
    ///////

    this.preloadInputData,
    this.preloadInputDataMandatory, // String (yes/no/ask)
    this.outputSchema,


    this.bypassSelectionScreen,

    this.backgroundColor,
  });

  final String? appName;
  final String? chatAvatarImagePath;

  final String? preamble;

  final bool? enableRag;
  final bool? enableRagButton1;
  final bool? enableRagButton2;

  final String? preloadModelsMandatory;

  final String? preloadModelName;
  final String? preloadModelBackend;

  final String? preloadEmbeddingModelName;
  final String? preloadEmbeddingModelBackend;

  final String? preloadInputData;
  final String? preloadInputDataMandatory;


  final String? outputSchema;

  final Color? backgroundColor;

  final bool? bypassSelectionScreen;

  @override
  State<LlmWidget> createState() => _LlmWidgetState();
}

class _LlmWidgetState extends State<LlmWidget> {
  final _navKey = GlobalKey<NavigatorState>();

  final storage = GetStorage();
  
  @override
  void initState() {
    super.initState();

    // 1. Run Validation before anything else
    _validateInput();

    storage.write('llmWidgetBackgroundColor', (widget.backgroundColor ?? Colors.blueGrey[200])?.value);
    storage.write('enableRag', widget.enableRag ?? false);
    storage.write('enableRagButton1', widget.enableRagButton1 ?? false);
    storage.write('enableRagButton2', widget.enableRagButton2 ?? false);
    storage.write('bypassSelectionScreen', widget.bypassSelectionScreen ?? false);
    storage.write('chatAvatarImagePath', widget.chatAvatarImagePath ?? '');

    _handlePreloadLogic().then((_) {
      _persistPromptBitsIfProvided().then((_) => _maybeAutoOpenChat());
    });
  }

  void _validateInput() {
    final pmMandatory = widget.preloadModelsMandatory?.toLowerCase() ?? 'no';
    final pidMandatory = widget.preloadInputDataMandatory?.toLowerCase() ?? 'no';
    final pmName = widget.preloadModelName;
    final pemName = widget.preloadEmbeddingModelName;

    // Helper: Validate enum-like string inputs
    void validateEnum(String val, List<String> allowed, String fieldName) {
      if (!allowed.contains(val)) {
        throw ArgumentError('$fieldName must be one of $allowed. Found: "$val"');
      }
    }

    // Validate mandatory flags values
    validateEnum(pmMandatory, ['yes', 'no', 'ask'], 'preloadModelsMandatory');
    validateEnum(pidMandatory, ['yes', 'no', 'ask'], 'preloadInputDataMandatory');

    // 1. bypassSelectionScreen: Can only be true when preloadModelsMandatory is yes
    if (widget.bypassSelectionScreen == true) {
      if (pmMandatory != 'yes') {
        throw ArgumentError(
            'bypassSelectionScreen can only be true when preloadModelsMandatory is "yes".');
      }
    }

    // 2. preloadModelsMandatory: Can be yes or ask only if preloadModelName is non-null
    if (pmMandatory == 'yes' || pmMandatory == 'ask') {
      if (pmName == null || pmName.isEmpty) {
        throw ArgumentError(
            'preloadModelsMandatory is "$pmMandatory" but preloadModelName is null or empty.');
      }
    }

    // 3. preloadModelName: Must be a valid model name
    if (pmName != null && pmName.isNotEmpty) {
      try {
        Model.values.firstWhere((m) => m.name == pmName);
      } catch (_) {
        throw ArgumentError(
            'Invalid preloadModelName: "$pmName". Must be one of: ${Model.values.map((e) => e.name).join(", ")}');
      }
    }

    // 4. preloadEmbeddingModelName validation
    if (pemName != null && pemName.isNotEmpty) {
      // Dependence: RAG relies on LLM
      if (pmName == null || pmName.isEmpty) {
        throw ArgumentError(
            'preloadEmbeddingModelName provided but preloadModelName is missing. RAG relies on LLM.');
      }

      // Dependence: enableRag must be true
      if (widget.enableRag != true) {
        throw ArgumentError(
            'preloadEmbeddingModelName provided but enableRag is false or null.');
      }

      // Validity check
      try {
        em.EmbeddingModel.values.firstWhere((m) => m.name == pemName);
      } catch (_) {
        throw ArgumentError(
            'Invalid preloadEmbeddingModelName: "$pemName". Must be one of: ${em.EmbeddingModel.values.map((e) => e.name).join(", ")}');
      }
    }

    // 5. preloadInputDataMandatory dependency
    if (pidMandatory == 'yes' || pidMandatory == 'ask') {
      if (pmMandatory != 'yes' && pmMandatory != 'ask') {
        throw ArgumentError(
            'preloadInputDataMandatory is "$pidMandatory", which requires preloadModelsMandatory to be "yes" or "ask".');
      }
    }

    // 6. Backends validation
    void validateBackend(String? backend, String paramName) {
      if (backend != null && backend.isNotEmpty) {
        final b = backend.toLowerCase();
        if (b != 'cpu' && b != 'gpu') {
          throw ArgumentError('$paramName must be "cpu" or "gpu" (or null). Found: "$backend"');
        }
      }
    }

    validateBackend(widget.preloadModelBackend, 'preloadModelBackend');
    validateBackend(widget.preloadEmbeddingModelBackend, 'preloadEmbeddingModelBackend');
  }

  Future<void> _handlePreloadLogic() async {
    final mode = widget.preloadModelsMandatory?.toLowerCase() ?? 'no';

    // If models are 'no', we don't perform any preload checks (including data).
    if (mode == 'no') return;

    final dataMode = widget.preloadInputDataMandatory?.toLowerCase() ?? 'no';

    // --- 1. Resolve Chat Model ---
    Model? targetModel;
    if (widget.preloadModelName != null) {
      try {
        targetModel = Model.values.firstWhere((m) => m.name == widget.preloadModelName);
      } catch (_) {
        debugPrint("Preload Error: Chat Model '${widget.preloadModelName}' not found.");
      }
    }

    final backendStr = widget.preloadModelBackend?.toLowerCase();
    final backend = ((backendStr == 'gpu') ? PreferredBackend.gpu : PreferredBackend.cpu);

    // --- 2. Resolve Embedding Model ---
    em.EmbeddingModel? targetEmbeddingModel;
    if (widget.preloadEmbeddingModelName != null) {
      try {
        targetEmbeddingModel = em.EmbeddingModel.values.firstWhere((m) => m.name == widget.preloadEmbeddingModelName);
      } catch (_) {
        debugPrint("Preload Error: Embedding Model '${widget.preloadEmbeddingModelName}' not found.");
      }
    }

    final embeddingBackendStr = widget.preloadEmbeddingModelBackend?.toLowerCase();
    final embeddingBackend = (embeddingBackendStr == 'gpu') ? PreferredBackend.gpu : PreferredBackend.cpu;


    // --- 4. Check Integrity (Remote vs Local) ---
    bool isChatModelReady = true;
    bool isEmbeddingReady = true;
    bool isDataUploaded = true;

    if (!kIsWeb) {
      final token = await AuthTokenService.loadToken() ?? '';

      if (targetModel != null) {
        isChatModelReady = await _checkModelIntegrity(targetModel, token);
      }

      if (targetEmbeddingModel != null) {
        isEmbeddingReady = await _checkEmbeddingModelIntegrity(targetEmbeddingModel, token);
      }
    } else {
      isChatModelReady = true;
      isEmbeddingReady = true;
    }

    // --- 5. Verify Data Upload (Check Flag AND Content Match) ---
    if (dataMode != 'no' && widget.preloadInputData != null) {
      final ragInitialized = (storage.read('isRagInitialized') as bool?) ?? false;
      final lastUploaded = storage.read('lastUploadedRagData') as String?;

      // If the process never finished OR the content has changed, we treat it as "Not Uploaded"
      if (!ragInitialized || lastUploaded != widget.preloadInputData) {
        isDataUploaded = false;
        debugPrint("Preload: Data mismatch or uninitialized.");
      } else {
        isDataUploaded = true;
      }
    }

    debugPrint("Preload Status: Chat=$isChatModelReady, Embed=$isEmbeddingReady, Data=$isDataUploaded");

    // --- 6. Decide Action ---
    // Proceed only if ALL required items are ready
    if (isChatModelReady && isEmbeddingReady && isDataUploaded) {
      // If we are fully ready, we can clear the accepted flag to be clean
      storage.write('isPreloadSetupAccepted', false);
      return;
    }

    // --- 7. Determine if we need to ASK ---
    // IMP CHANGED: Check if user previously accepted setup
    final isPreloadSetupAccepted = storage.read('isPreloadSetupAccepted') ?? false;

    bool shouldAsk = false;

    if (isPreloadSetupAccepted) {
      // User already said yes previously, skip ask and go straight to setup
      shouldAsk = false;
    } else {
      // Standard ask logic
      if (mode == 'ask' && (!isChatModelReady || !isEmbeddingReady)) {
        shouldAsk = true;
      }
      if (dataMode == 'ask' && !isDataUploaded) {
        shouldAsk = true;
      }
    }

    // --- 8. Prepare Preload Action ---
    Future<void> startPreload() async {
      if (!mounted) return;

      while (_navKey.currentState == null) {
        await Future.delayed(const Duration(milliseconds: 50));
      }

      // IMP CHANGED: Mark as accepted once we start
      storage.write('isPreloadSetupAccepted', true);

      // We wait for the result.
      final result = await _navKey.currentState!.push(
        noSwipeRoute(PreloadScreen(
          model: targetModel,
          backend: backend,
          embeddingModel: targetEmbeddingModel,
          embeddingBackend: embeddingBackend,
          preloadInputData: widget.preloadInputData,
          preloadInputDataMandatory: (dataMode != 'no'),
          isChatModelAlreadyDone: isChatModelReady,
          isEmbeddingModelAlreadyDone: isEmbeddingReady,
        )),
      );

      // IMP CHANGED: If result is NOT true, it means user cancelled/backed out.
      // Reset flag so they get asked again next time.
      if (result != true) {
        storage.write('isPreloadSetupAccepted', false);
      }
    }

    if (shouldAsk) {
      while (_navKey.currentContext == null) {
        await Future.delayed(const Duration(milliseconds: 100));
      }

      if (!mounted) return;

      final List<String> missingItems = [];
      if (!isChatModelReady && targetModel != null) missingItems.add("LLM:  ${targetModel.displayName}");
      if (!isEmbeddingReady && targetEmbeddingModel != null) missingItems.add("RAG:  ${targetEmbeddingModel.displayName}");

      final msg = 'Setup your AI models and data in one click!\n'
          '${missingItems.map((item) => "   • $item").join("\n")}\n\n'
          'You can change the models later. Skip if you want to choose models and upload data manually!';

      final shouldPreload = await showDialog<bool>(
        context: _navKey.currentContext!,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Setup AI Chat Models?'),
          content: Text(msg),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Skip'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Start Setup'),
            ),
          ],
        ),
      );

      if (shouldPreload == true) {

        // 3. Persist Preferences ---
        final saved = await LastSelectionPrefs.load();
        final modelToSave = targetModel ?? saved?.model;
        final embeddingToSave = targetEmbeddingModel ?? saved?.embeddingModel;
        final backendToSave = (targetModel != null) ? backend : (saved?.backend ?? backend);
        final embeddingBackendToSave = (targetEmbeddingModel != null) ? embeddingBackend : (saved?.embeddingBackend ?? embeddingBackend);
        await LastSelectionPrefs.save(modelToSave, backendToSave, embeddingToSave, embeddingBackendToSave);


        await startPreload();
      }
    } else {

      // 3. Persist Preferences ---
      final saved = await LastSelectionPrefs.load();
      final modelToSave = targetModel ?? saved?.model;
      final embeddingToSave = targetEmbeddingModel ?? saved?.embeddingModel;
      final backendToSave = (targetModel != null) ? backend : (saved?.backend ?? backend);
      final embeddingBackendToSave = (targetEmbeddingModel != null) ? embeddingBackend : (saved?.embeddingBackend ?? embeddingBackend);
      await LastSelectionPrefs.save(modelToSave, backendToSave, embeddingToSave, embeddingBackendToSave);

      // Automatic 'yes' mode OR previously accepted mode
      await startPreload();
    }
  }

  Future<bool> _checkModelIntegrity(Model model, String token) async {
    try {
      // 1. Check if initialization is locked (in progress). If so, model is not ready.
      final isLocked = storage.read('isChatInitLocked') ?? false;
      if (isLocked) return false;

      // 2. Check File Existence & Size
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${model.filename}');
      if (!file.existsSync()) return false;

      final Map<String, String> headers = token.isNotEmpty ? {'Authorization': 'Bearer $token'} : {};
      final headResponse = await http.head(Uri.parse(model.url), headers: headers);

      if (headResponse.statusCode == 200) {
        final len = headResponse.headers['content-length'];
        if (len != null && await file.length() == int.parse(len)) return true;
      }
    } catch (e) {
      debugPrint('Error checking chat model integrity: $e');
    }
    return false;
  }

  Future<bool> _checkEmbeddingModelIntegrity(em.EmbeddingModel model, String token) async {
    try {
      // 1. Check if initialization is locked (in progress). If so, model is not ready.
      final isLocked = storage.read('isEmbeddingInitLocked') ?? false;
      if (isLocked) return false;

      // 2. Check File Existence & Size
      final dir = await getApplicationDocumentsDirectory();
      final Map<String, String> headers = token.isNotEmpty ? {'Authorization': 'Bearer $token'} : {};

      // --- 1. Check Model File ---
      final modelFile = File('${dir.path}/${model.filename}');
      if (!modelFile.existsSync()) return false;

      final modelHead = await http.head(Uri.parse(model.url), headers: headers);
      if (modelHead.statusCode != 200) return false;

      final modelLen = modelHead.headers['content-length'];
      if (modelLen != null && await modelFile.length() != int.parse(modelLen)) return false;

      // --- 2. Check Tokenizer File ---
      // Assumes your EmbeddingModel has a 'tokenizerFilename' property.
      final tokenizerFile = File('${dir.path}/${model.tokenizerFilename}');
      if (!tokenizerFile.existsSync()) return false;

      final tokenizerHead = await http.head(Uri.parse(model.tokenizerUrl), headers: headers);
      if (tokenizerHead.statusCode != 200) return false;

      final tokenizerLen = tokenizerHead.headers['content-length'];
      if (tokenizerLen != null && await tokenizerFile.length() == int.parse(tokenizerLen)) {
        return true; // Both files are valid
      }

    } catch (e) {
      debugPrint('Error checking embedding model integrity: $e');
    }
    return false;
  }

  Future<void> _persistPromptBitsIfProvided() async {
    await PromptPrefs.save(
      preamble: widget.preamble,
      inputCsv: widget.preloadInputData,
      outputSchema: widget.outputSchema,
    );
  }

  Future<void> _maybeAutoOpenChat() async {
    final saved = await LastSelectionPrefs.load();
    bool canOpenChat = false;
    if (saved?.model != null) {
      if (kIsWeb) {
        canOpenChat = true;
      } else {

        final token = await AuthTokenService.loadToken() ?? '';

        if (await _checkModelIntegrity(saved!.model!, token)) {
          canOpenChat = true;
        }
      }
    }

    if (!mounted) return;

    final bypass = storage.read('bypassSelectionScreen') ?? false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (canOpenChat && !bypass) {
        // Normal behavior: Open Chat directly
        _navKey.currentState?.pushReplacement(
          noSwipeRoute(ChatScreen(
              model: saved!.model!,
              selectedBackend: saved.backend
          )),
        );
      } else {
        // Fallback or Bypass behavior:
        // If bypass is on, we actually WANT to go here.
        // We push SelectionScreen. It will detect bypass=true and auto-push ChatScreen.
        // This ensures the stack is [Selection -> Chat].
        _navKey.currentState?.pushReplacement(
          noSwipeRoute(TheSelectionScreen(
            lastSelectedModel: saved?.model,
            lastSelectedEmbeddingModel: saved?.embeddingModel,
            isEmbedding: false,
          )),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 420,
        height: 800,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Material(
            child: WillPopScope(
              onWillPop: () async => true,
              child: Navigator(
                key: _navKey,
                onGenerateRoute: (settings) {
                  switch (settings.name) {
                    case '/':
                      return noSwipeRoute(
                        Scaffold(
                          backgroundColor: Colors.white.withValues(alpha: 0.1),
                          body: const Center(
                            child: LoadingWidget(message: 'Initializing...'),
                          ),
                        ),
                      );
                    default:
                      return noSwipeRoute(const SizedBox.shrink());
                  }
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}