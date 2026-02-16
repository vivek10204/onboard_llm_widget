//IMP: Diff from example (medium)

// CHANGES:
// 1. Updated onAddDocuments to accept picked files instead of Sample documents screen. Replaced SampleScreen navigation with FilePicker. Renamed button to 'Add Docs'.
// 2. Renamed 'Knowledge Base' to 'Upload Knowledge Base'

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class KnowledgeBaseSection extends StatelessWidget {
  final bool isLoading;
  final int addTimeMs;
  final ValueChanged<List<PlatformFile>> onAddDocuments;
  final VoidCallback onClearDocuments;

  const KnowledgeBaseSection({
    super.key,
    required this.isLoading,
    required this.addTimeMs,
    required this.onAddDocuments,
    required this.onClearDocuments,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '  Upload Knowledge Base',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),

        // Buttons
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: isLoading
                    ? null
                    : () async {
                  final result = await FilePicker.platform.pickFiles(
                    allowMultiple: true,
                  );
                  if (result != null) {
                    onAddDocuments(result.files);
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text('Add Docs'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: isLoading ? null : onClearDocuments,
                icon: const Icon(Icons.delete),
                label: const Text('Clear All'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade900,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
        if (addTimeMs > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Last add: ${addTimeMs}ms',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
      ],
    );
  }
}