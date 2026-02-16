//IMP: Diff from example (new). Merged.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter_gemma/pigeon.g.dart';

import 'the_download_screen.dart';
import 'chat_screen.dart';

import 'models/model.dart';
import 'models/embedding_model.dart';

import 'services/last_selection_prefs.dart';

enum SortType {
  defaultOrder('Default'),
  alphabetical('Alphabetical'),
  size('Size');

  const SortType(this.displayName);
  final String displayName;
}

class TheSelectionScreen extends StatefulWidget {
  final Model? lastSelectedModel;
  final EmbeddingModel? lastSelectedEmbeddingModel;
  final bool isEmbedding;

  const TheSelectionScreen({
    super.key,
    this.lastSelectedModel,
    this.lastSelectedEmbeddingModel,
    this.isEmbedding = false,
  });

  @override
  State<TheSelectionScreen> createState() => _TheSelectionScreenState();
}

class _TheSelectionScreenState extends State<TheSelectionScreen> {
  // --- Chat Model State ---
  SortType selectedSort = SortType.defaultOrder;
  bool filterMultimodal = false;
  bool filterFunctionCalls = false;
  bool filterThinking = false;
  Model? _currentChatSelection;

  // --- Embedding Model State ---
  EmbeddingModel? _currentEmbeddingSelection;

  final storage = GetStorage();

  @override
  void initState() {
    super.initState();
    _currentChatSelection = widget.lastSelectedModel;
    _currentEmbeddingSelection = widget.lastSelectedEmbeddingModel;

    // IMP CHANGED: Handle Bypass Logic
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleBypassLogic());
  }

  Future<void> _handleBypassLogic() async {
    final bypass = storage.read('bypassSelectionScreen') ?? false;
    if (!bypass) return;

    // IMP CHANGED: Extended logic to handle Embedding models too
    if (widget.isEmbedding) {
      if (_currentEmbeddingSelection != null) {
        // For embedding, the "next screen" is TheDownloadScreen (based on card tap logic)
        // There is no "ChatScreen" equivalent for embeddings in this specific flow,
        // so we skip Scenario 1 (Chat) and go straight to Scenario 2 (Download).

        final saved = await LastSelectionPrefs.load();
        final embeddingBackend = saved?.embeddingBackend ?? PreferredBackend.cpu;

        if (mounted) {
          // Push DownloadScreen directly
          await Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (context) => TheDownloadScreen(
                  model: _currentEmbeddingSelection!,
                  // Embeddings usually default to CPU in your code, keeping consistency
                  selectedBackend: embeddingBackend,
              ),
            ),
          );

          // Scenario 3: User came back from DownloadScreen.
          if (mounted) {
            widget.isEmbedding?
            Navigator.of(context).pop():
            Navigator.of(context, rootNavigator: true).pop();
          }
        }
      }
      return;
    }

    // --- Chat Model Logic (Existing) ---
    if (_currentChatSelection != null) {
      // Scenario 1: Auto-forward to ChatScreen
      final saved = await LastSelectionPrefs.load();
      final backend = saved?.backend ?? PreferredBackend.cpu;

      // Push ChatScreen. We await it to handle Scenario 2 (Back from Chat)
      if (mounted) {
        // IMP CHANGED: Must be PUSH (not replacement) to stay alive and handle return
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (context) => ChatScreen(model: _currentChatSelection!, selectedBackend: backend),
          ),
        );

        // Scenario 2: User came back from ChatScreen. Open DownloadScreen immediately.
        if (mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (context) => TheDownloadScreen(model: _currentChatSelection!, selectedBackend: backend),
            ),
          );

          // Scenario 3: User came back from DownloadScreen.
          // IMP CHANGED: Use rootNavigator: true to pop the entire LlmWidget
          if (mounted) {
            Navigator.of(context, rootNavigator: true).pop();
          }

        }
      }
    }
  }

  Future<void> _refreshSelection() async {
    final saved = await LastSelectionPrefs.load();
    if (mounted) {
      setState(() {
        if (saved != null) {
          if (saved.model != null) _currentChatSelection = saved.model;
          if (saved.embeddingModel != null) _currentEmbeddingSelection = saved.embeddingModel;
        }
      });
    }
  }

  // --- Helpers ---
  double _sizeToMB(String size) {
    final numStr = size.replaceAll(RegExp(r'[^0-9.]'), '');
    final num = double.tryParse(numStr) ?? 0;
    if (size.toUpperCase().contains('GB')) return num * 1024;
    if (size.toUpperCase().contains('TB')) return num * 1024 * 1024;
    return num;
  }

  List<Model> _getFilteredChatModels() {
    var models = Model.values.where((model) {
      if (model.localModel) return kIsWeb;
      if (!kIsWeb) return true;
      return model.preferredBackend == PreferredBackend.gpu && !model.needsAuth;
    }).toList();

    // Filter
    models = models.where((model) {
      if (filterMultimodal && !model.supportImage) return false;
      if (filterFunctionCalls && !model.supportsFunctionCalls) return false;
      if (filterThinking && !model.isThinking) return false;
      return true;
    }).toList();

    // Sort
    _applySort(models);
    return models;
  }

  List<EmbeddingModel> _getFilteredEmbeddingModels() {
    var models = EmbeddingModel.values.toList();
    // Sort
    _applySort(models);
    return models;
  }

  void _applySort(List<dynamic> models) {
    switch (selectedSort) {
      case SortType.alphabetical:
        models.sort((a, b) => a.displayName.compareTo(b.displayName));
        break;
      case SortType.size:
        models.sort((a, b) => _sizeToMB(a.size).compareTo(_sizeToMB(b.size)));
        break;
      case SortType.defaultOrder:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final int? v = storage.read('llmWidgetBackgroundColor');
    final bg = v != null ? Color(v) : Colors.blueGrey[200]!;

    // IMP CHANGED: If bypassing, show a loader while we redirect, to avoid flicker
    final bypass = storage.read('bypassSelectionScreen') ?? false;
    // Check both chat AND embedding selection existence
    bool hasSelection = widget.isEmbedding
        ? _currentEmbeddingSelection != null
        : _currentChatSelection != null;

    if (bypass && hasSelection) {
      return Scaffold(backgroundColor: bg, body: const Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          color: Colors.blueGrey,
          onPressed: () async {
            final popped = await Navigator.of(context).maybePop();
            if (!popped) {
              await Navigator.of(context, rootNavigator: true).maybePop(); //TBD
            }
          },
        ),
        title: Text(
          widget.isEmbedding ? 'Select RAG Model' : 'Select Chat Model',
          style: const TextStyle(fontSize: 21, color: Colors.blueGrey),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            color: Colors.blueGrey,
            tooltip: 'Filter & Sort',
            onPressed: _openFilterSortSheet,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          children: [
            Text(
              widget.isEmbedding
                  ? 'Download and manage embedding models for Retrieval-Augmented Generation'
                  : 'Download and manage chat models for text generation and reasoning',
              style: const TextStyle(fontSize: 16, color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            Expanded(
              child: widget.isEmbedding
                  ? _buildEmbeddingList()
                  : _buildChatModelList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatModelList() {
    final models = _getFilteredChatModels();
    return ListView.builder(
      itemCount: models.length,
      itemBuilder: (context, index) {
        final model = models[index];
        return ModelCard(
          model: model,
          isSelected: (_currentChatSelection != null && model.name == _currentChatSelection!.name),
          onRefresh: _refreshSelection,
        );
      },
    );
  }

  Widget _buildEmbeddingList() {
    final models = _getFilteredEmbeddingModels();
    return ListView.builder(
      itemCount: models.length,
      itemBuilder: (context, index) {
        final model = models[index];
        return EmbeddingModelCard(
          model: model,
          isSelected: (_currentEmbeddingSelection != null && model.name == _currentEmbeddingSelection!.name),
          onRefresh: _refreshSelection,
        );
      },
    );
  }

  void _openFilterSortSheet() async {
    bool tempFilterMultimodal = filterMultimodal;
    bool tempFilterFunctionCalls = filterFunctionCalls;
    bool tempFilterThinking = filterThinking;
    SortType tempSelectedSort = selectedSort;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          child: DraggableScrollableSheet(
            initialChildSize: 0.55,
            minChildSize: 0.35,
            maxChildSize: 0.9,
            expand: false,
            builder: (context, scrollController) {
              return StatefulBuilder(
                builder: (context, setModalState) {
                  return Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1a2951),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                          child: Row(
                            children: [
                              const Text('Filter & Sort', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.white70),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: Colors.white12),
                        Expanded(
                          child: SingleChildScrollView(
                            controller: scrollController,
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!widget.isEmbedding) ...[
                                  const Text('Features', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      FilterChip(
                                        label: const Text('Multimodal'),
                                        selected: tempFilterMultimodal,
                                        onSelected: (v) => setModalState(() => tempFilterMultimodal = v),
                                        selectedColor: Colors.orange[700],
                                        labelStyle: TextStyle(color: tempFilterMultimodal ? Colors.white : null),
                                      ),
                                      FilterChip(
                                        label: const Text('Function Calls'),
                                        selected: tempFilterFunctionCalls,
                                        onSelected: (v) => setModalState(() => tempFilterFunctionCalls = v),
                                        selectedColor: Colors.purple[600],
                                        labelStyle: TextStyle(color: tempFilterFunctionCalls ? Colors.white : null),
                                      ),
                                      FilterChip(
                                        label: const Text('Thinking'),
                                        selected: tempFilterThinking,
                                        onSelected: (v) => setModalState(() => tempFilterThinking = v),
                                        selectedColor: Colors.indigo[600],
                                        labelStyle: TextStyle(color: tempFilterThinking ? Colors.white : null),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  const Divider(height: 1, color: Colors.white12),
                                  const SizedBox(height: 20),
                                ],

                                const Text('Sort', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  children: SortType.values.map((type) {
                                    final selected = tempSelectedSort == type;
                                    return ChoiceChip(
                                      label: Text(type.displayName, style: TextStyle(color: selected ? Colors.white : null)),
                                      selected: selected,
                                      selectedColor: Colors.indigo[600],
                                      onSelected: (_) => setModalState(() => tempSelectedSort = type),
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(foregroundColor: Colors.orange, side: const BorderSide(color: Colors.orange)),
                                  onPressed: () {
                                    setModalState(() {
                                      tempFilterMultimodal = false;
                                      tempFilterFunctionCalls = false;
                                      tempFilterThinking = false;
                                      tempSelectedSort = SortType.defaultOrder;
                                    });
                                  },
                                  child: const Text('Clear'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      filterMultimodal = tempFilterMultimodal;
                                      filterFunctionCalls = tempFilterFunctionCalls;
                                      filterThinking = tempFilterThinking;
                                      selectedSort = tempSelectedSort;
                                    });
                                    Navigator.pop(context);
                                  },
                                  child: const Text('Apply'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

// ==========================================
// CARD WIDGETS
// ==========================================

class ModelCard extends StatefulWidget {
  final Model model;
  final bool isSelected;
  final VoidCallback? onRefresh;

  const ModelCard({super.key, required this.model, required this.isSelected, this.onRefresh});

  @override
  State<ModelCard> createState() => _ModelCardState();
}

class _ModelCardState extends State<ModelCard> {
  PreferredBackend? selectedBackend;

  Future<bool> _isDownloaded() async {
    if (kIsWeb) return false;
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/${widget.model.filename}';
    return File(path).exists();
  }

  void _setSelectedBackend() async {
    // Only fetch/check saved prefs if this model is the one currently selected by the user.
    // Otherwise, we stick to the model's preferred backend (set in initState).
    if (widget.isSelected) {
      final saved = await LastSelectionPrefs.load();
      final savedBackend = saved?.backend;

      // If we have a saved backend for this selected model, update the state.
      if (savedBackend != null && mounted) {
        setState(() {
          selectedBackend = savedBackend;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    // Default to the model's own preference initially
    selectedBackend = widget.model.preferredBackend;
    // Attempt to override with saved user preference
    _setSelectedBackend();
  }

  bool get supportsBothBackends => !widget.model.localModel;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      color: (widget.isSelected) ? Colors.blueGrey.shade900 : Colors.black87,
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.all(16.0),
            title: Row(
              children: [
                SizedBox(
                  width: 250,
                  child: Text(
                    widget.model.displayName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4.0),
                if (supportsBothBackends) ...[
                  Row(
                    children: [
                      const Text('Backend: ', style: TextStyle(fontWeight: FontWeight.w500)),
                      const SizedBox(width: 8),
                      SegmentedButton<PreferredBackend>(
                        segments: const [
                          ButtonSegment(value: PreferredBackend.cpu, label: Text('CPU', style: TextStyle(fontSize: 12))),
                          ButtonSegment(value: PreferredBackend.gpu, label: Text('GPU', style: TextStyle(fontSize: 12))),
                        ],
                        selected: {selectedBackend ?? PreferredBackend.cpu},
                        onSelectionChanged: (Set<PreferredBackend> selection) {
                          setState(() {
                            selectedBackend = selection.first;
                          });
                        },
                        style: ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 8, vertical: 0)),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Text(
                    'Backend: ${widget.model.preferredBackend.name.toUpperCase()}',
                    style: TextStyle(
                      color: widget.model.preferredBackend == PreferredBackend.gpu ? Colors.green[600] : Colors.blue[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 2.0),
                Row(
                  children: [
                    Text('Size: ${widget.model.size}', style: TextStyle(color: Colors.grey[600])),
                    FutureBuilder<bool>(
                      future: _isDownloaded(),
                      builder: (context, snapshot) {
                        if (snapshot.data != true) return const SizedBox.shrink();
                        return const Padding(
                          padding: EdgeInsets.only(left: 150.0),
                          child: Icon(Icons.save, size: 18, color: Colors.grey, semanticLabel: 'Downloaded'),
                        );
                      },
                    ),
                  ],
                ),
                if (widget.model.supportsFunctionCalls || widget.model.supportImage || widget.model.isThinking) ...[
                  const SizedBox(height: 4.0),
                  Wrap(
                    spacing: 4.0,
                    children: [
                      if (widget.model.supportsFunctionCalls)
                        Chip(
                          label: const Text('Function Calls', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w500)),
                          backgroundColor: Colors.purple[600],
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      if (widget.model.supportImage)
                        Chip(
                          label: const Text('Multimodal', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w500)),
                          backgroundColor: Colors.orange[700],
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      if (widget.model.isThinking)
                        Chip(
                          label: const Text('Thinking', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w500)),
                          backgroundColor: Colors.indigo[600],
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                    ],
                  ),
                ],
              ],
            ),
            trailing: Icon(Icons.arrow_forward_ios, color: Colors.grey[400]),
            onTap: () async {
              if (!kIsWeb) {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (context) => TheDownloadScreen(model: widget.model, selectedBackend: selectedBackend),
                  ),
                );
              } else {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (context) => ChatScreen(model: widget.model, selectedBackend: selectedBackend),
                  ),
                );
              }
              widget.onRefresh?.call();
            },
          ),
        ],
      ),
    );
  }
}

class EmbeddingModelCard extends StatefulWidget {
  final EmbeddingModel model;
  final bool isSelected;
  final VoidCallback? onRefresh;

  const EmbeddingModelCard({super.key, required this.model, this.isSelected = false, this.onRefresh});

  @override
  State<EmbeddingModelCard> createState() => _EmbeddingModelCardState();
}

class _EmbeddingModelCardState extends State<EmbeddingModelCard> {
  // 1. Mutable state
  PreferredBackend selectedBackend = PreferredBackend.cpu;

  Future<bool> _isDownloaded() async {
    if (kIsWeb) return false;
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/${widget.model.filename}';
    return File(path).exists();
  }

  // 2. Added Persistence Logic
  void _setSelectedBackend() async {
    if (widget.isSelected) {
      final saved = await LastSelectionPrefs.load();
      // Fetch embeddingBackend specifically
      final savedBackend = saved?.embeddingBackend;

      if (savedBackend != null && mounted) {
        setState(() {
          selectedBackend = savedBackend;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    // 3. Call it
    _setSelectedBackend();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      color: (widget.isSelected) ? Colors.blueGrey.shade900 : Colors.black87,
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.all(16.0),
            title: Row(
              children: [
                SizedBox(
                  width: 250,
                  child: Text(
                    widget.model.displayName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4.0),
                // 4. Enabled Selection UI
                Row(
                  children: [
                    const Text('Backend: ', style: TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(width: 8),
                    SegmentedButton<PreferredBackend>(
                      segments: const [
                        ButtonSegment(
                            value: PreferredBackend.cpu,
                            label: Text('CPU', style: TextStyle(fontSize: 12))
                        ),
                        ButtonSegment(
                          value: PreferredBackend.gpu,
                          label: Text('GPU', style: TextStyle(fontSize: 12)),
                          // Enabled now
                        ),
                      ],
                      selected: {selectedBackend},
                      onSelectionChanged: (Set<PreferredBackend> selection) {
                        setState(() {
                          selectedBackend = selection.first;
                        });
                      },
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 8, vertical: 0)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2.0),
                Row(
                  children: [
                    Text('Size: ${widget.model.size}', style: TextStyle(color: Colors.grey[600])),
                    FutureBuilder<bool>(
                      future: _isDownloaded(),
                      builder: (context, snapshot) {
                        if (snapshot.data != true) return const SizedBox.shrink();
                        return const Padding(
                          padding: EdgeInsets.only(left: 150.0),
                          child: Icon(Icons.save, size: 18, color: Colors.grey, semanticLabel: 'Downloaded'),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4.0),
                Wrap(
                  spacing: 4.0,
                  children: [
                    Chip(
                      label: Text('Dim: ${widget.model.dimension}', style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500)),
                      backgroundColor: Colors.purple[600],
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),
              ],
            ),
            trailing: Icon(Icons.arrow_forward_ios, color: Colors.grey[400]),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (context) => TheDownloadScreen(model: widget.model, selectedBackend: selectedBackend),
                ),
              );
              widget.onRefresh?.call();
            },
          ),
        ],
      ),
    );
  }
}