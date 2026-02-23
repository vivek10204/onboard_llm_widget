# onboard_llm_widget

A powerful, plug-and-play Flutter widget designed to seamlessly onboard users into local Large Language Model (LLM) and Retrieval-Augmented Generation (RAG) experiences. 

Handling local AI models can be complex. This package provides a complete UI and logic wrapper to handle model downloading, integrity checking, hardware backend selection (CPU/GPU), and data preloading—all before smoothly routing the user to your chat interface.

## Features

* **One-Click AI Setup:** Guides users through downloading and initializing local chat and embedding models.
* **Smart Caching & Integrity Checks:** Automatically verifies if models are already downloaded (checking file size and existence) to prevent redundant network requests.
* **RAG Ready:** Built-in support for initializing embedding models and preloading CSV/document data for Retrieval-Augmented Generation.
* **Hardware Acceleration Selection:** Allows users (or developers) to define `CPU` or `GPU` preferred backends.
* **Auto-Routing:** Seamlessly bypasses the setup screen if the models are already present and ready to use.
* **Highly Customizable:** Configure mandatory downloads, background colors, app names, and avatar images to match your branding.

## Getting started

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  onboard_llm_widget: ^0.0.1
