//IMP: Diff from example (large)

// CHANGES:
// 1. Background color, title and stuff.
// 2. Top right menu.
// 3. Menu button and logic for "Delete All Messages" button.
// 4. Moved Sync toggle to menu as a checkbox.
// 5. Added support for RAG mode and menu buttons (along with RAG input in LLM).
// 6. Persist last opened Model/preferredBackend so that next time app starts, the chat screen is opened automatically using these values.
// 7. Also persist/load chat message history across restarts.
// 8. Added model initialization for last selected models in initState
// 9. Increased tokenBuffer to 512 to try and prevent the 'input too long' issue

import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';
import 'package:get_storage/get_storage.dart';

import 'chat_widget.dart';
import 'models/base_model.dart';
import 'the_selection_screen.dart'; // Unified selection screen

import 'widgets/loading_widget.dart';

import 'models/model.dart';
import 'models/embedding_model.dart' as em;

import 'services/chat_storage.dart';
import 'services/last_selection_prefs.dart';
import 'services/auth_token_service.dart';

import 'rag/rag_demo_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.model = Model.gemma3_1B, this.selectedBackend});

  final Model model;
  final PreferredBackend? selectedBackend;

  @override
  ChatScreenState createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {
  InferenceChat? chat;
  final _messages = <Message>[];
  bool _isModelInitialized = false;
  bool _isInitializing = false; // Protection against concurrent initialization
  bool _isStreaming = false; // Track streaming state
  String? _error;
  Color _backgroundColor = Colors.blueGrey.shade200; // IMP CHANGED
  String _appTitle = 'Ask Me Anything!'; // Track the current app title // IMP CHANGED

  ////////////
  // IMP CHANGED: Added for RAG mode
  bool _enableRag = false;
  bool _enableRagButton1 = false;
  bool _enableRagButton2 = false;
  bool _bypassSelectionScreen = false;

  // IMP CHANGED: Added for model initialization
  bool _isChatModelInitDone = false;
  bool _isEmbeddingInitDone = false;

  // IMP CHANGED: Added for persisting state and other stuff
  final storage = GetStorage();
  ////////////


  // Toggle for sync/async mode
  bool _useSyncMode = false;

  // Define the tools (order and descriptions must match Colab training!)
  final List<Tool> _tools = [
    const Tool(
      name: 'change_background_color',
      description: 'Changes the app background color',
      parameters: {
        'type': 'object',
        'properties': {
          'color': {
            'type': 'string',
            'description': 'The color name (red, green, blue, yellow, purple, orange)',
          },
        },
        'required': ['color'],
      },
    ),
    const Tool(
      name: 'change_app_title',
      description: 'Changes the application title text in the AppBar',
      parameters: {
        'type': 'object',
        'properties': {
          'title': {
            'type': 'string',
            'description': 'The new title text to display',
          },
        },
        'required': ['title'],
      },
    ),
    const Tool(
      name: 'show_alert',
      description: 'Shows an alert dialog with a custom message and title',
      parameters: {
        'type': 'object',
        'properties': {
          'title': {
            'type': 'string',
            'description': 'The title of the alert dialog',
          },
          'message': {
            'type': 'string',
            'description': 'The message content of the alert dialog',
          },
        },
        'required': ['title', 'message'],
      },
    ),
  ];

  ///////////////
  // IMP CHANGED: Added for model initialization (TBD Common code with download screen and preload screen)

  void _initializeModels() async {
    if (!_isChatModelInitDone) {
      // ----------------------------------------------------------------------
      while (storage.read('isChatInitLocked') ?? false) {
        await Future.delayed(const Duration(seconds: 2));
      }

      storage.write('isChatInitLocked', true);
      try {
        // No need to set _processingChatInit = true here anymore, we did it above.
        await _initializeModel();

        if (mounted) {
          setState(() {
            _isChatModelInitDone = true;
          });
        }
      } finally {
        storage.write('isChatInitLocked', false);
      }
    }

    if (!_isEmbeddingInitDone) {
      // ----------------------------------------------------------------------
      while (storage.read('isEmbeddingInitLocked') ?? false) {
        await Future.delayed(const Duration(seconds: 2));
      }

      storage.write('isEmbeddingInitLocked', true);
      try {
        // No need to set _processingChatInit = true here anymore, we did it above.
        await _initializeEmbeddingModel();

        if (mounted) {
          setState(() {
            _isEmbeddingInitDone = true;
          });
        }
      } finally {
        storage.write('isEmbeddingInitLocked', false);
      }
    }
  }

  /// Initialize embedding model if it's not already initialized (Modern API)
  Future<void> _initializeEmbeddingModelIfNeeded(em.EmbeddingModel embeddingModel) async {
    try {
      // Modern API: Install model (idempotent - handles already-installed check)

      // Load token from AuthTokenService if model requires authentication
      String? token;
      if (embeddingModel.needsAuth) {
        final authToken = await AuthTokenService.loadToken();
        token = authToken?.isNotEmpty == true ? authToken : null;
      }

      // Build installer based on sourceType
      var builder = FlutterGemma.installEmbedder();

      // Add model source
      switch (embeddingModel.sourceType) {
        case ModelSourceType.network:
          builder = builder.modelFromNetwork(embeddingModel.url, token: token);
        case ModelSourceType.asset:
          builder = builder.modelFromAsset(embeddingModel.url);
        case ModelSourceType.bundled:
          builder = builder.modelFromBundled(embeddingModel.url);
      }

      // Add tokenizer source
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

      setState(() {
        // Model initialized successfully
      });

    } catch (e) {
      // Don't set error state here - let user try to generate and see the error
    }
  }

  Future<void> _initializeEmbeddingModel() async {
    if ((storage.read('enableRagButton1') as bool?) ?? false) {
      final saved = await LastSelectionPrefs.load();
      em.EmbeddingModel? embeddingModel;
      if (saved != null) {
        embeddingModel = saved.embeddingModel;
      }
      if (embeddingModel!= null) {
        _initializeEmbeddingModelIfNeeded(embeddingModel);
      }
    }
  }

  ///////////////

  @override
  void initState() {

    /////////////
    // IMP CHANGED: Added for RAG
    _enableRag = (storage.read('enableRag') as bool?) ?? false;
    _enableRagButton1 = (storage.read('enableRagButton1') as bool?) ?? false;
    _enableRagButton2 = (storage.read('enableRagButton2') as bool?) ?? false;
    _bypassSelectionScreen = (storage.read('bypassSelectionScreen') as bool?) ?? false;
    /////////////

    super.initState();

    _initializeModels(); // IMP CHANGED: Added for model initialization
  }

  @override
  void dispose() {
    _isInitializing = false; // Reset initialization flag
    _isModelInitialized = false; // Reset model flag
    super.dispose();
    // No need to call deleteModel - model cleanup handled by model.close() callback
  }

  Future<void> _initializeModel() async {
    if (_isModelInitialized || _isInitializing) {
      debugPrint('[ChatScreen] Already initialized or initializing, skipping');
      return;
    }

    _isInitializing = true;
    debugPrint('[ChatScreen] Starting model initialization...');

    try {
      // Step 1: Install model (Modern API handles already-installed check)
      debugPrint('[ChatScreen] Step 1: Installing model...');

      final installer = FlutterGemma.installModel(
        modelType: widget.model.modelType,
        fileType: widget.model.fileType,
      );

      // Choose source based on localModel flag
      if (widget.model.localModel) {
        await installer.fromAsset(widget.model.url).install();
      } else {
        // Load token if model needs authentication
        String? token;
        if (widget.model.needsAuth) {
          token = await AuthTokenService.loadToken();
          debugPrint('[ChatScreen] Loaded auth token: ${token != null ? "✅" : "❌"}');
        }

        await installer.fromNetwork(widget.model.url, token: token).install();
      }

      debugPrint('[ChatScreen] Step 1: Model installed ✅');

      // Step 2: Create model with runtime config
      debugPrint('[ChatScreen] Step 2: Creating InferenceModel...');
      final model = await FlutterGemma.getActiveModel(
        maxTokens: widget.model.maxTokens*2, // IMP CHANGED: Added a little extra here for long term context!
        preferredBackend: widget.selectedBackend ?? widget.model.preferredBackend,
        supportImage: widget.model.supportImage,
        maxNumImages: widget.model.maxNumImages,
      );
      debugPrint('[ChatScreen] Step 2: InferenceModel created ✅');

      // Step 3: Create chat
      debugPrint('[ChatScreen] Step 3: Creating chat...');
      chat = await model.createChat(
        temperature: widget.model.temperature,
        randomSeed: 1,
        topK: widget.model.topK,
        topP: widget.model.topP,
        tokenBuffer: widget.model.maxTokens, // IMP CHANGED: To prevent 'Input too long' issue we pss maxTokens*2 in getActiveModel fn
        supportImage: widget.model.supportImage,
        supportsFunctionCalls: widget.model.supportsFunctionCalls,
        tools: _tools,
        isThinking: widget.model.isThinking,
        modelType: widget.model.modelType,
      );
      debugPrint('[ChatScreen] Step 3: Chat created ✅');

      setState(() {
        _isModelInitialized = true;
        _error = null;
      });

      ///////////////
      // IMP CHANGED: Added
      // Persist selection
      final backendToPersist = widget.selectedBackend ?? widget.model.preferredBackend;
      final saved = await LastSelectionPrefs.load();
      em.EmbeddingModel? embeddingModel;
      PreferredBackend? embeddingBackend;
      if (saved != null) {
        embeddingModel = saved.embeddingModel;
        embeddingBackend = saved.embeddingBackend;
      }

      if (kIsWeb) {
        await LastSelectionPrefs.save(widget.model, backendToPersist, embeddingModel, embeddingBackend);
        if (!mounted) return;
      } else {
        final dir = await getApplicationDocumentsDirectory();
        if (!mounted) return;
        final path = '${dir.path}/${widget.model.filename}';
        if (await File(path).exists()) {
          if (!mounted) return;
          await LastSelectionPrefs.save(widget.model, backendToPersist, embeddingModel, embeddingBackend);
          if (!mounted) return;
        }
      }

      // Load history
      final persisted = await ChatStorage.load();
      if (!mounted) return;

      setState(() {
        _messages.clear();
        _messages.addAll(persisted);
        _isModelInitialized = true;
      });
      ChatStorage.save(_messages); // IMP CHANGED: Added
      ///////////////

      debugPrint('[ChatScreen] Initialization complete ✅');
    } catch (e) {
      debugPrint('[ChatScreen] ❌ Initialization failed: $e');
      if (mounted) {
        setState(() {
          _error = 'Failed to initialize model: ${e.toString()}';
          _isModelInitialized = false;
        });
      }
      rethrow;
    } finally {
      _isInitializing = false; // Always reset the flag
    }
  }

  // Helper method to handle function calls with system messages (async version)
  Future<void> _handleFunctionCall(FunctionCallResponse functionCall) async {
    // Set streaming state and show "Calling function..." in one setState
    setState(() {
      _isStreaming = true;
      _messages.add(Message.systemInfo(
        text:
            "🔧 Calling: ${functionCall.name}(${functionCall.args.entries.map((e) => '${e.key}: "${e.value}"').join(', ')})",
      ));
    });
    ChatStorage.save(_messages); // IMP CHANGED: Added

    // Small delay to show the calling message
    await Future.delayed(const Duration(milliseconds: 300));

    // 2. Show "Executing function"
    setState(() {
      _messages.add(Message.systemInfo(
        text: "⚡ Executing function",
      ));
    });
    ChatStorage.save(_messages); // IMP CHANGED: Added

    final toolResponse = await _executeTool(functionCall);
    debugPrint('Tool response: $toolResponse'); // IMP CHANGED: Added

    // 3. Show "Function completed"
    setState(() {
      _messages.add(Message.systemInfo(
        text: "✅ Function completed: ${toolResponse['message'] ?? 'Success'}",
      ));
    });
    ChatStorage.save(_messages); // IMP CHANGED: Added

    // Small delay to show completion
    await Future.delayed(const Duration(milliseconds: 300));

    // Send tool response back to the model
    final toolMessage = Message.toolResponse(
      toolName: functionCall.name,
      response: toolResponse,
    );
    await chat?.addQuery(toolMessage);

    // TEMPORARILY use sync response for debugging

    final response = await chat!.generateChatResponse();

    if (response is TextResponse) {
      final accumulatedResponse = response.token;
      setState(() {
        _messages.add(Message.text(text: accumulatedResponse));
      });
    } else if (response is FunctionCallResponse) {}

    // Reset streaming state when done
    setState(() {
      _isStreaming = false;
    });
    ChatStorage.save(_messages); // IMP CHANGED: Added
  }

  // Main gemma response handler - processes responses from GemmaInputField
  Future<void> _handleGemmaResponse(ModelResponse response) async {
    if (response is FunctionCallResponse) {
      await _handleFunctionCall(response);
    } else if (response is TextResponse) {
      // DEBUG: Track what text we're receiving from GemmaInputField
      setState(() {
        _messages.add(Message.text(text: response.token));
        _isStreaming = false;
      });
      ChatStorage.save(_messages); // IMP CHANGED: Added
    } else {}
  }

  // Function to execute tools
  Future<Map<String, dynamic>> _executeTool(FunctionCallResponse functionCall) async {
    if (functionCall.name == 'change_app_title') {
      final newTitle = functionCall.args['title'] as String?;
      if (newTitle != null && newTitle.isNotEmpty) {
        setState(() {
          _appTitle = newTitle;
        });
        ChatStorage.save(_messages); // IMP CHANGED: Added
        return {'status': 'success', 'message': 'App title changed to "$newTitle"'};
      } else {
        return {'error': 'Title cannot be empty'};
      }
    }
    if (functionCall.name == 'change_background_color') {
      final colorName = functionCall.args['color']?.toLowerCase();
      final colorMap = {
        'red': Colors.red,
        'blue': Colors.blue,
        'green': Colors.green,
        'yellow': Colors.yellow,
        'purple': Colors.purple,
        'orange': Colors.orange,
      };
      if (colorMap.containsKey(colorName)) {
        setState(() {
          _backgroundColor = colorMap[colorName]!;
        });
        ChatStorage.save(_messages); // IMP CHANGED: Added
        return {'status': 'success', 'message': 'Background color changed to $colorName'};
      } else {
        return {'error': 'Color not supported', 'available_colors': colorMap.keys.toList()};
      }
    }
    if (functionCall.name == 'show_alert') {
      final title = functionCall.args['title'] as String? ?? 'Alert';
      final message = functionCall.args['message'] as String? ?? 'No message provided';
      final buttonText = functionCall.args['button_text'] as String? ?? 'OK'; // IMP CHANGED: Added

      // Show the alert dialog
      await showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(buttonText), // IMP CHANGED
              ),
            ],
          );
        },
      );

      return {'status': 'success', 'message': 'Alert dialog shown with title "$title"'};
    }
    return {'error': 'Tool not found'};
  }

  ////////////
  // IMP CHANGED: Added
  Future<void> _confirmAndDeleteAll() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all messages?'),
        content: const Text('This will permanently remove this chat history.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );

    if (shouldDelete != true) return;

    setState(() {
      _isStreaming = false;
      _error = null;
      _messages.clear();
    });

    await ChatStorage.clear();

    try {
      await chat?.clearHistory();
    } catch (_) {
      // ignore
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All messages deleted')),
      );
    }
  }
  ////////////

  @override
  Widget build(BuildContext context) {
    //////
    // IMP CHANGED: Added for bg color
    final int? v = storage.read('llmWidgetBackgroundColor');
    _backgroundColor = v != null ? Color(v) : Colors.blueGrey[200]!;
    //////

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _backgroundColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.blueGrey,), // IMP CHANGED
          ///////////////
          // IMP CHANGED: Replaced call to ModelSelectionScreen
          onPressed: () async {
            // IMP CHANGED: Simple POP to support bypass flow
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              // Fallback just in case, though LlmWidget ensures stack usually
              final saved = await LastSelectionPrefs.load();
              Model? lastSelectedModel;
              em.EmbeddingModel? lastSelectedEmbeddingModel;
              if (saved != null) {
                lastSelectedModel = saved.model;
                lastSelectedEmbeddingModel = saved.embeddingModel;
              }

              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute<void>(
                  builder: (context) => TheSelectionScreen(lastSelectedModel: lastSelectedModel, lastSelectedEmbeddingModel: lastSelectedEmbeddingModel, isEmbedding: false,),
                ),
                    (route) => false,
              );
            }
          },
          ///////////////
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _appTitle,
              style: const TextStyle(fontSize: 18, color: Colors.blueGrey), // IMP CHANGED
              softWrap: true,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            if (chat?.supportsImages == true)
              const Text(
                'Image support enabled',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.green,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        actions: [
          // IMP CHANGED: Removed Sync Toggle from here (moved to menu)

          // Image support indicator
          if (chat?.supportsImages == true)
            const Padding(
              padding: EdgeInsets.only(right: 16.0),
              child: Icon(
                Icons.image,
                color: Colors.green,
                size: 20,
              ),
            ),

          ///////////////////
          // IMP CHANGED: Added for refresh button
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.blueGrey),
            tooltip: 'Refresh Model',
            onPressed: () async {
              // [OPTIONAL] If your plugin throws an error when re-initializing an
              // already loaded model, uncomment your cleanup logic here:
              /*
              final saved = await LastSelectionPrefs.load();
              if (saved?.model?.filename != null) {
                 // Await this to ensure it's gone before the new screen loads
                 await FlutterGemma.uninstallModel(saved!.model!.filename);
              }
              */

              // Ensure the widget is still on screen before navigating
              if (!context.mounted) return;

              final saved = await LastSelectionPrefs.load();
              final model = saved?.model;
              final backend = saved?.backend ?? PreferredBackend.cpu;

              await chat?.clearHistory();

              // This kills the current widget and pushes a fresh one
              Navigator.pushReplacement(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, animation1, animation2) => ChatScreen(
                      model: model!, selectedBackend: backend
                  ),
                  transitionDuration: Duration.zero, // Removes the navigation animation
                  reverseTransitionDuration: Duration.zero,
                ),
              );




            },
          ),


          // IMP CHANGED: Added for top right menu
          // Menu Button
          PopupMenuButton<String>(
            itemBuilder: (context) {
              return [
                // 1. The "Mega-Item" containing RAG Options ONLY
                PopupMenuItem(
                  padding: EdgeInsets.zero,
                  enabled: false,
                  textStyle: const TextStyle(color: Colors.black),
                  child: StatefulBuilder(
                    builder: (BuildContext context, StateSetter setMenuState) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // --- RAG Toggle Row ---
                          if (_enableRagButton1 || _enableRagButton2)
                            InkWell(
                              onTap: () {
                                setMenuState(() {
                                  _enableRag = !_enableRag;
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      height: 24,
                                      width: 24,
                                      child: Checkbox(
                                        value: _enableRag,
                                        onChanged: (bool? value) {
                                          setMenuState(() {
                                            _enableRag = value ?? false;
                                          });
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Text(
                                      'RAG Filtered Input',
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          // --- RAG Expandable Options ---
                          if (_enableRag) ...[
                            if (_enableRagButton1 || _enableRagButton2) const Divider(height: 1),

                            if (_enableRagButton1)
                              InkWell(
                                onTap: () async {
                                  final saved = await LastSelectionPrefs.load();
                                  em.EmbeddingModel? lastSelectedEmbeddingModel;
                                  Model? lastSelectedModel;
                                  if (saved != null) {
                                    lastSelectedEmbeddingModel = saved.embeddingModel;
                                    lastSelectedModel = saved.model;
                                  }

                                  if (context.mounted) Navigator.pop(context);
                                  if (context.mounted) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute<void>(
                                        builder: (context) => TheSelectionScreen(
                                          lastSelectedEmbeddingModel: lastSelectedEmbeddingModel,
                                          lastSelectedModel: lastSelectedModel,
                                          isEmbedding: true,
                                        ),
                                      ),
                                    );
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                                  child: Text(
                                    _bypassSelectionScreen ? 'View RAG Model' : 'Select RAG Model',
                                    style: const TextStyle(color: Colors.white70),
                                  ),
                                ),
                              ),

                            if (_enableRagButton2)
                              InkWell(
                                onTap: () async {
                                  final saved = await LastSelectionPrefs.load();
                                  em.EmbeddingModel? embeddingModel;
                                  if (saved != null) {
                                    embeddingModel = saved.embeddingModel;
                                  }

                                  if (embeddingModel != null) {
                                    if (context.mounted) Navigator.pop(context);
                                    if (context.mounted) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (context) => RagDemoScreen(
                                            model: embeddingModel as em.EmbeddingModel,
                                          ),
                                        ),
                                      );
                                    }
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Select RAG Model first!'),
                                        duration: Duration(seconds: 1),
                                      ),
                                    );
                                  }
                                },
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                                  child: Text(
                                    'RAG Input & Settings',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                ),
                              ),

                            // Optional Divider at the bottom of RAG section
                            if (_enableRagButton1 || _enableRagButton2) const Divider(height: 1),
                          ],
                        ],
                      );
                    },
                  ),
                ),

                // 2. Sync Mode Item (Moved to its own PopupMenuItem)
                PopupMenuItem(
                  padding: EdgeInsets.zero,
                  enabled: false, // Disabled so InkWell handles tap without auto-closing immediately
                  child: StatefulBuilder(
                    builder: (BuildContext context, StateSetter setSyncState) {
                      return InkWell(
                        onTap: () {
                          // Update Outer Widget State
                          setState(() {
                            _useSyncMode = !_useSyncMode;
                          });
                          // Update Menu State (Visual Checkbox)
                          setSyncState(() {});
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                          child: Row(
                            children: [
                              SizedBox(
                                height: 24,
                                width: 24,
                                child: Checkbox(
                                  value: _useSyncMode,
                                  onChanged: (bool? value) {
                                    setState(() {
                                      _useSyncMode = value ?? false;
                                    });
                                    setSyncState(() {});
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Sync Mode',
                                style: TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // 3. Delete All Messages Item (Moved to its own PopupMenuItem)
                PopupMenuItem(
                  padding: EdgeInsets.zero,
                  child: StatefulBuilder(
                    builder: (BuildContext context, StateSetter setSyncState) {
                      return InkWell(
                        onTap: () async {
                          // Update Outer Widget State
                          await _confirmAndDeleteAll();
                          if (context.mounted) Navigator.pop(context);
                        },
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                          child: Text(
                            'Delete All Messages',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ];
            },
          ),
          ///////////////////
        ],
      ),
      body: Stack(children: [
        Center(
          child: SizedBox( // IMP CHANGED
            width: 200,
            height: 200,
          ),
        ),
        _isModelInitialized
            ? Column(children: [
                if (_error != null) _buildErrorBanner(_error!),
                if (chat?.supportsImages == true && _messages.isEmpty) _buildImageSupportInfo(),
                Expanded(
                  child: ChatListWidget(
                    chat: chat,
                    useSyncMode: _useSyncMode,
                    gemmaHandler: _handleGemmaResponse,
                    messageHandler: (message) {
                      // Handles all message additions to history
                      setState(() {
                        _error = null;
                        _messages.add(message);
                        // Set streaming to true when user sends message
                        _isStreaming = true;
                      });
                      ChatStorage.save(_messages); // IMP CHANGED: Added
                    },
                    errorHandler: (err) {
                      setState(() {
                        _error = err;
                        _isStreaming = false; // Reset streaming on error
                      });
                      ChatStorage.save(_messages); // IMP CHANGED: Added
                    },
                    messages: _messages,
                    isProcessing: _isStreaming,
                  ),
                )
              ])
            : const LoadingWidget(message: 'Initializing model'),
      ]),
    );
  }

  Widget _buildErrorBanner(String errorMessage) {
    return Container(
      width: double.infinity,
      color: Colors.red,
      padding: const EdgeInsets.all(8.0),
      child: Text(
        errorMessage,
        style: const TextStyle(color: Colors.white),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildImageSupportInfo() {
    return Container(
      margin: const EdgeInsets.all(16.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: const Color(0xFF1a3a5c),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline,
            color: Colors.blueGrey, // IMP CHANGED
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Model supports images',
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'Use the 📷 button to add images to your messages',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}