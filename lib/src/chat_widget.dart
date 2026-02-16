//IMP: Diff from example (large)

// CHANGES:
// 1. RAG
// 2. Long press menu for chat messages, with copy message button
// 3. Pin the input text field at the bottom below message list.
// 4. Extra: Reformat code for rendering list of historical messages from oldest to newest, thinking widget, model response msg etc along with input text field pinned at bottom.
// 5. Scroll to bottom feature on initState or new message

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_storage/get_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter_gemma/flutter_gemma.dart';

import 'widgets/chat_input_field.dart';
import 'widgets/chat_message.dart';
import 'widgets/gemma_input_field.dart';
import 'widgets/thinking_widget.dart';

import 'services/prompt_prefs.dart';

class ChatListWidget extends StatefulWidget {
  const ChatListWidget({
    required this.messages,
    required this.gemmaHandler,
    required this.messageHandler,
    required this.errorHandler,
    this.chat,
    this.isProcessing = false,
    this.useSyncMode = false,
    super.key,
  });

  final InferenceChat? chat;
  final List<Message> messages;
  final ValueChanged<ModelResponse>
      gemmaHandler; // Accepts ModelResponse (TextToken | FunctionCall)
  final ValueChanged<Message> messageHandler; // Handles all message additions to history
  final ValueChanged<String> errorHandler;
  final bool
      isProcessing; // Indicates if the model is currently processing (including function calls)
  final bool useSyncMode; // Toggle for sync/async mode

  @override
  State<ChatListWidget> createState() => _ChatListWidgetState();
}

class _ChatListWidgetState extends State<ChatListWidget> {

  ///////////////////////////////
  // IMP CHANGED: Added for??
  final _scrollCtrl = ScrollController();
  final storage = GetStorage();

  // holds the wrapped prompt we want the model to see for the *last* turn
  String? _lastPromptOverride;
  final bool _enableRag = (GetStorage().read('enableRag') as bool?) ?? false;

  // IMP CHANGED: Added for copy message button
  // Returns plain text from a Message (tweak if your Message API differs)
  String _plainText(Message m) {
    try {
      return m.text;
    } catch (_) {
      return m.toString();
    }
  }

  // IMP CHANGED: Added Timer for scroll sync
  DateTime? _lastScrollTime;

  Future<void> _showMessageActions(BuildContext ctx, Message m) async {
    final text = _plainText(m);
    if (text.isEmpty) return;

    await showModalBottomSheet<void>(
      context: ctx,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy Message'),
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (mounted) {
                    Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() async {
    await widget.chat?.stopGeneration();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // IMP CHANGED: Fixed scroll issue by adding slight delay to ensure list is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _scrollToBottom(jump: true);
      });
    });
  }

  @override
  void didUpdateWidget(covariant ChatListWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messages.length != oldWidget.messages.length || widget.isProcessing != oldWidget.isProcessing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _scrollToBottom({bool jump = false}) {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position.maxScrollExtent;
    if (jump) {
      _scrollCtrl.jumpTo(pos);
    } else {
      _scrollCtrl.animateTo(
        pos,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }


  ///////

  /// Get database path - returns virtual path on web, real path on mobile
  Future<String> _getDatabasePath(String filename) async {
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/$filename';
  }

  Future<String> _ragSearch(String query) async {
    final stopwatch = Stopwatch()..start();

    try {

      //Initialize Vector store
      final dbPath = await _getDatabasePath('rag_demo.db');
      await FlutterGemmaPlugin.instance.initializeVectorStore(dbPath);

      final results = await FlutterGemmaPlugin.instance.searchSimilar(
        query: query,
        topK: (storage.read('ragTopK') as int?) ?? 5,
        threshold: (storage.read('ragThreshold') as double?) ?? 0.80,
      );

      stopwatch.stop();

      debugPrint("RAG results:");
      for (var e in results) {
        debugPrint(e.content);
      }

      String contextCsv = results.map((e) => e.content).join('\n');

      // FALLBACK: If RAG returns nothing, use top 10 lines of the full dataset
      if (contextCsv.trim().isEmpty) {
        debugPrint("No similar results found. Using fallback (Top 10 lines of persisted data).");

        final fullData = (storage.read('lastUploadedRagData') as String?) ?? '';

        contextCsv = fullData
            .split('\n')
            .where((line) => line.trim().isNotEmpty) // Ensure we get actual data lines
            .take(10)
            .join('\n');
      }

      return contextCsv;
    } catch (e) {
      stopwatch.stop();
      debugPrint('[RagDemo] Search error: $e');
      return "";
    }
  }

  Future<String> _buildWrappedPrompt(Message userMessage) async {
    final prefs      = await PromptPrefs.loadAll();
    final preamble   = prefs.preamble ?? '';
    final question   = userMessage.text;

    String contextCsv = "";
    if (_enableRag) {
      // Pure-AI retrieval: semantic embeddings → cosine Top-K (no rules)
      contextCsv = await _ragSearch(question);
      debugPrint("contextCsv:");
      debugPrint(contextCsv);
    }

    return '''
${preamble.isNotEmpty ? 'SYSTEM:\n$preamble\n' : ''}

${contextCsv.isNotEmpty ? 'CONTEXT:\n$contextCsv\n' : 'CONTEXT:\nEMPTY\n'}

USER QUESTION:
$question

ANSWER:
''';

  }

  ///////


  ///////////////////////////////

  // Current streaming thinking state
  String _currentThinkingContent = '';
  bool _isCurrentThinkingExpanded = false;
  // Expanded state for each thinking widget in history (by message index)
  final Map<int, bool> _thinkingExpandedStates = {};

  void _handleGemmaResponse(ModelResponse response) {
    // Capture thinking content before passing to parent
    if (response is ThinkingResponse) {
      setState(() {
        _currentThinkingContent += response.content;
      });
    }

    widget.gemmaHandler(response);

    // IMP CHANGED: Added periodic scroll logic WITH PostFrameCallback
    // This ensures we calculate the scroll position AFTER the new text has rendered/expanded
    final now = DateTime.now();
    if (_lastScrollTime == null || now.difference(_lastScrollTime!).inMilliseconds >= 2000) {
      _lastScrollTime = now;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToBottom();
      });
    }
  }


  void _handleNewMessage(Message message) async { // IMP CHANGED. TBDO CHECK _buildWrappedPrompt for async. TBDO What is this?
    // Reset current thinking for new conversation
    setState(() {
      _currentThinkingContent = '';
      _isCurrentThinkingExpanded = false;
      _lastScrollTime = null; // Reset scroll timer
    });

    //////////////////////
    // IMP CHANGED: Added for RAG
    // 1) Build the wrapped prompt for the model (NOT shown to user)
    final wrapped = await _buildWrappedPrompt(message);
    setState(() {
      _lastPromptOverride = wrapped;
    });

    // 2) Add the *original* user message to history (so UI shows exactly what user typed)
    //////////////////////
    widget.messageHandler(message);
  }

  @override
  Widget build(BuildContext context) {
    //////////////////////////////////////////
    // IMP CHANGED: Reformatted code for message history, thinking widget and assistant reply message
    // We will render:
    //  - all history messages (oldest -> newest)
    //  - optional current streaming thinking
    //  - optional current streaming assistant bubble
    final historyCount = widget.messages.length;
    final showThinkingStream = _currentThinkingContent.isNotEmpty;
    final showAssistantStream = widget.isProcessing;

    final totalItems = historyCount +
        (showThinkingStream ? 1 : 0) +
        (showAssistantStream ? 1 : 0);
    //////////////////////////////////////////


    ////////////////////////////////////
    // IMP CHANGED: Edited from just ListView to Column containing list view and chat input field pinned at bottom
    return Column(
      children: [
        // Scrollable messages area
        Expanded(
          child: ListView.builder(
            controller: _scrollCtrl,
            ////////////////////////////////////


            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            reverse: false, // IMP CHANGED: oldest at top, newest at bottom
            itemCount: totalItems, // IMP CHANGED
            itemBuilder: (context, index) {

              // 1) History messages in natural order
              if (index < historyCount) {
                final message = widget.messages[index]; // no reverse()
                if (message.type == MessageType.thinking) {
                  final isExpanded = _thinkingExpandedStates[index] ?? false;
                  return ThinkingWidget(
                    thinking: ThinkingResponse(message.text),
                    isExpanded: isExpanded,
                    onToggle: () {
                      setState(() {
                        _thinkingExpandedStates[index] = !isExpanded;
                      });
                    },
                  );
                }
                return InkWell(
                  onLongPress: () => _showMessageActions(context, message),
                  child: ChatMessageWidget(message: message),
                );
              }

              // 2) Streaming thinking block (current turn)
              int i = index - historyCount;
              if (showThinkingStream && i == 0) {
                return ThinkingWidget(
                  thinking: ThinkingResponse(_currentThinkingContent),
                  isExpanded: _isCurrentThinkingExpanded,
                  onToggle: () {
                    setState(() {
                      _isCurrentThinkingExpanded = !_isCurrentThinkingExpanded;
                    });
                  },
                );
              }

              // 3) Streaming assistant bubble (GemmaInputField)
              if (showAssistantStream) {
                // If we have a prompt override, clone the history and replace only the last message’s text
                final messagesForModel = (_lastPromptOverride != null && widget.messages.isNotEmpty)
                    ? () {
                  final clone = List<Message>.from(widget.messages);
                  final last = clone.last;
                  clone[clone.length - 1] = last.copyWith(text: _lastPromptOverride!);
                  return clone;
                }()
                    : widget.messages;

                /*
                //TBDO: If normal messages need to be tested instead of wrapped prompt (with RAG, personality etc)
                final messagesForModel = widget.messages;
                 */

                return GemmaInputField(
                  chat: widget.chat,
                  messages: messagesForModel,
                  streamHandler: _handleGemmaResponse,
                  errorHandler: widget.errorHandler,
                  isProcessing: widget.isProcessing,
                  useSyncMode: widget.useSyncMode,
                  onThinkingCompleted: (s) {
                    if (s.isNotEmpty) {
                      final thinkingMessage = Message.thinking(text: s);
                      widget.messageHandler(thinkingMessage);
                      setState(() => _currentThinkingContent = '');
                    }
                  },
                );
              }
              return const SizedBox.shrink(); // IMP CHANGED: From null
              ////////////////////////////////////////////
            },
          ),
        ),

        /////////////////////////////////
        // IMP CHANGED: Added
        // Chat input field pinned at bottom (ALWAYS visible)
        Opacity(
          opacity: widget.isProcessing ? 0.8 : 1.0,
          child: ChatInputField(
            key: const ValueKey('chat_input'),
            isGenerating: widget.isProcessing,
            handleStopped: () async {
              if (!widget.isProcessing) return;
              try {
                await widget.chat?.stopGeneration();

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Generation stopped'),
                    duration: Duration(seconds: 2),
                  ),
                );
              } catch (e) {
                final message =
                e.toString().contains('stop_not_supported') ? 'Stop generation not yet supported on this platform' : 'Failed to stop generation: $e';

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(message),
                    duration: const Duration(seconds: 3),
                    backgroundColor: Colors.orange,
                  ),
                );
              }

            },
            handleSubmitted: (m) {
              _handleNewMessage(m);
              // nudge scroll to bottom after the send
              WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
            },
            supportsImages: widget.chat?.supportsImages ?? false,
          ),
        ),
        /////////////////////////////////
      ],
    );
  }
}