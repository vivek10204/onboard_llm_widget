//IMP: Diff from example (new)

// CHANGES:
// 1. Added Stop button stuff (isGenerating, handleStopped etc)
// 2. Changed Send button to be Send or Stop button based on isGenerating

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flutter_gemma/flutter_gemma.dart';

class ChatInputField extends StatefulWidget {
  final ValueChanged<Message> handleSubmitted;
  final bool supportsImages;

  ///////////
  // IMP CHANGED: Added
  final bool isGenerating;              // tells the input to show Stop instead of Send
  final VoidCallback? handleStopped;    // called when user taps Stop
  ///////////

  const ChatInputField({
    super.key,
    required this.handleSubmitted,
    this.supportsImages = false,

    ///////////
    // IMP CHANGED: Added
    this.isGenerating = false,
    this.handleStopped,
    ///////////

  });

  @override
  ChatInputFieldState createState() => ChatInputFieldState();
}

class ChatInputFieldState extends State<ChatInputField> {
  final TextEditingController _textController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  Uint8List? _selectedImageBytes;
  String? _selectedImageName;

  ///////////
  // IMP CHANGED: Added
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleStopped(String text) {
    widget.handleStopped!();
    _focusNode.unfocus(); // hide keyboard
  }
  ///////////

  void _handleSubmitted(String text) {
    if (text.trim().isEmpty && _selectedImageBytes == null) return;

    final message = _selectedImageBytes != null
        ? Message.withImage(
            text: text.trim(),
            imageBytes: _selectedImageBytes!,
            isUser: true,
          )
        : Message.text(
            text: text.trim(),
            isUser: true,
          );

    widget.handleSubmitted(message);
    _textController.clear();
    _clearImage();

    // IMP CHANGED: Added
    _focusNode.unfocus(); // hide keyboard
  }

  void _clearImage() {
    setState(() {
      _selectedImageBytes = null;
      _selectedImageName = null;
    });
  }

  Future<void> _pickImage() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      final pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _selectedImageBytes = bytes;
          _selectedImageName = pickedFile.name;
        });
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Image selection error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Selected image preview
        if (_selectedImageBytes != null) _buildImagePreview(),

        // Input field
        IconTheme(
          data: IconThemeData(color: Theme.of(context).hoverColor),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0), // IMP CHANGED: Added vertical
            decoration: BoxDecoration(
              color: const Color(0xFF1a3a5c),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: <Widget>[
                // Add image button
                if (widget.supportsImages)
                  IconButton(
                    icon: Icon(
                      Icons.image,
                      color: _selectedImageBytes != null ? Colors.blue : Colors.white70,
                    ),
                    onPressed: _pickImage,
                    tooltip: 'Add image',
                  ),

                Flexible(
                  child: TextField(
                    controller: _textController,
                    focusNode: _focusNode, // IMP CHANGED: Added
                    textInputAction: TextInputAction.send,            // nicer IME button // IMP CHANGED: Added. Why?
                    onSubmitted: widget.isGenerating ? _handleStopped : _handleSubmitted, // IMP CHANGED
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: _selectedImageBytes != null
                          ? 'Add description to image...'
                          : 'Send message',
                      hintStyle: const TextStyle(color: Colors.white54),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 12.0,
                      ),
                    ),
                    maxLines: null,
                  ),
                ),

                ////////////////////////
                // IMP CHANGED: Replaced Trailing button (Send ↔ Stop)
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                  child: widget.isGenerating
                      ? IconButton(
                    key: const ValueKey('stop_btn'),
                    icon: const Icon(Icons.stop, color: Colors.redAccent),
                    onPressed: () {
                      _handleStopped("");
                    },
                    tooltip: 'Stop',
                  )
                      : IconButton(
                    key: const ValueKey('send_btn'),
                    icon: const Icon(Icons.send, color: Colors.white70),
                    onPressed: () {
                      _handleSubmitted(_textController.text);
                      // ensure keyboard hides even if onSubmitted wasn't triggered
                      _focusNode.unfocus();
                    },
                    tooltip: 'Send',
                  ),
                ),
                ////////////////////////

              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImagePreview() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: const Color(0xFF2a4a6c),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Image preview
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              _selectedImageBytes!,
              width: 60,
              height: 60,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),

          // Image information
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedImageName ?? 'Image',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${(_selectedImageBytes!.length / 1024).toStringAsFixed(1)} KB',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          // Delete button
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70),
            onPressed: _clearImage,
            tooltip: 'Remove image',
          ),
        ],
      ),
    );
  }
}
