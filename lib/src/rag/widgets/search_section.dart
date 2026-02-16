//IMP: Diff from example (medium)

// CHANGES:
// 1. Removed threshold and topK parameters from here (including sliders) and moved to SearchParametersSection.
// 2. Renamed 'Search' string to 'Test Search'

import 'package:flutter/material.dart';

class SearchSection extends StatelessWidget {
  final TextEditingController controller;
  final bool isLoading;
  final int searchTimeMs;
  final VoidCallback onSearch;

  const SearchSection({
    super.key,
    required this.controller,
    required this.isLoading,
    required this.searchTimeMs,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '  Test Search',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Search Query',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: const Icon(Icons.search),
              onPressed: isLoading ? null : onSearch,
            ),
          ),
          onSubmitted: (_) => onSearch(),
        ),
        const SizedBox(height: 16),

        ElevatedButton.icon(
          onPressed: isLoading ? null : onSearch,
          icon: isLoading
              ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : const Icon(Icons.search),
          label: const Text('Search'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
        if (searchTimeMs > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Search time: ${searchTimeMs}ms',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
      ],
    );
  }
}