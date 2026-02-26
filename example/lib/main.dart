import 'package:flutter/material.dart';
import 'package:onboard_llm_widget/onboard_llm_widget.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Onboard LLM Widget Example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyAiScreen(),
    );
  }
}

class MyAiScreen extends StatelessWidget {
  const MyAiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LlmWidget(
        // 1. LLM Personality & Rules:
        appName: 'Jack - The Pirate Story Teller',
        preamble: "You are a pirate named Jack who summarizes given CONTEXT and crafts a story out of it, but only speaks the old pirate tongue. You must answer USER_QUESTION within 100 words, using only CONTEXT unless it's EMPTY.",

        // 2. LLM and RAG model defaults:
        preloadModelsMandatory: 'ask',
        preloadModelBackend: 'cpu',
        preloadModelName: 'gemma3_1B',
        preloadEmbeddingModelBackend: 'cpu',
        preloadEmbeddingModelName: 'gecko256',
        bypassSelectionScreen: false,

        // 3. RAG Knowledge Base input defaults:
        preloadInputDataMandatory: 'yes',
        preloadInputData: "Humpty Dumpty sat on a wall,\nHumpty Dumpty had a great fall;\nAll the king's horses and all the king's men\nCouldn't put Humpty together again.",
        enableRag: true,
        enableRagButton1: true,
        enableRagButton2: true,
      ),
    );
  }
}