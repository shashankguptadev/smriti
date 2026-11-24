# Smriti — Offline Personal Knowledge Base (Android)

<p align="center">
  <b>100% Offline • Private • On-Device RAG • Material 3</b>
</p>

---

## Overview

**Smriti** (स्मृति — *memory / recollection*) is a private, completely offline personal knowledge base for Android. It lets you import your own documents (PDF, Markdown, plain text), indexes them into a local on-device vector database using HNSW indexing, and runs Retrieval-Augmented Generation (RAG) powered by on-device LiteRT language models.

No telemetry, no cloud APIs, and zero network calls. All your data stays strictly on your device.

---

## Key Features

- **100% Offline & Private:** Zero internet permissions required. Documents, vector embeddings, and LLM inference run strictly on your device hardware.
- **Fast Vector Search (ObjectBox HNSW):** Sub-millisecond vector similarity queries using 384-dimensional cosine distance indices.
- **Multi-Format Document Ingestion:** Parses `.pdf`, `.txt`, and `.md` files. Heavy parsing and sliding-window chunking are isolated off the main UI thread using `Isolate.run()`.
- **Streaming RAG Chat:** Conversational assistant that streams answers token-by-token with expandable source citations (file name, chunk index, similarity distance, and exact excerpts).
- **Model Manager:** First-launch onboarding allows importing local `.litertlm` (LiteRT-LM) model weights or running in mock mode for development and testing.
- **Battery & RAM Friendly:** Automatic lifecycle management via `WidgetsBindingObserver` frees heavy model weights when the app is backgrounded.

---

## Tech Stack

| Layer | Technology |
|---|---|
| **Platform** | Android only (`minSdk = 24`, targetSdk 35) |
| **Framework** | Flutter (Material 3 Theme with Light/Dark support) |
| **State Management** | `provider` (`ChangeNotifier` + `MultiProvider`) |
| **Vector Database** | `objectbox` + `objectbox_flutter_libs` (HNSW Cosine Index) |
| **On-Device AI Engine** | LiteRT (.litertlm) / `flutter_edge_ai` integration architecture |
| **Document Ingestion** | `file_picker`, `syncfusion_flutter_pdf`, `path_provider` |
| **Codegen & Build** | `build_runner`, `objectbox_generator` |

---

## Architecture

Smriti follows a clean, decoupled layered architecture:

```
lib/
├── main.dart                        # MultiProvider bootstrapping & conditional AI injection
├── app.dart                         # SmritiApp widget with lifecycle memory observer
├── core/
│   ├── models/                      # Domain entities & data classes
│   │   ├── chat_message.dart        # ChatMessage & CitationSource models
│   │   ├── document_chunk.dart      # ObjectBox @Entity with @HnswIndex
│   │   └── document_info.dart       # High-level indexed document metadata
│   └── services/                    # Abstract service contracts
│       ├── document_ingestor.dart   # Ingestor interface
│       ├── embedding_service.dart   # Vector embedding interface
│       ├── llm_service.dart         # Streaming LLM generator interface
│       └── vector_store_service.dart# Vector persistence & query interface
├── services/                        # Concrete implementations
│   ├── edge_embedding_service.dart  # On-device vector embeddings
│   ├── edge_llm_service.dart        # On-device LiteRT streaming inference with OOM guard
│   ├── in_memory_vector_store.dart  # Pure-Dart store for host unit tests
│   ├── local_document_ingestor.dart # PDF/TXT/MD chunking via Isolate.run()
│   ├── mock_embedding_service.dart  # Deterministic 384-dim mock embedder
│   ├── mock_llm_service.dart        # Streaming mock LLM generator
│   ├── objectbox_vector_store.dart  # Production ObjectBox HNSW vector database
│   └── rag_service.dart             # RAG pipeline coordinator
├── providers/                       # State management (ChangeNotifier)
│   ├── chat_provider.dart           # Chat history & token streaming
│   ├── knowledge_base_provider.dart # Document index & progress tracking
│   └── model_manager_provider.dart  # .litertlm weight discovery & import
└── ui/
    ├── screens/
    │   ├── chat_screen.dart         # Chat tab UI
    │   ├── documents_screen.dart    # Documents tab & file picker UI
    │   ├── home_screen.dart         # M3 NavigationBar shell
    │   └── model_manager_screen.dart# First-launch model onboarding UI
    └── widgets/
        ├── chat_bubble.dart         # User/Assistant message bubbles
        └── source_citation_card.dart# Expandable citation card
```

---

## Building and Running

### Prerequisites
- Flutter SDK (Channel stable)
- Android SDK (`minSdk = 24`)

### Run Tests
```bash
flutter pub get
flutter analyze
flutter test
```

### Build Release APK
```bash
flutter build apk --release
```
The optimized APK with R8 shrinking and ProGuard keep rules will be generated at:
`build/app/outputs/flutter-apk/app-release.apk`

---

## On-Device Model Setup

1. Launch the app on your Android device.
2. If no model is installed, the **AI Model Setup** onboarding screen will appear.
3. Tap **Import .litertlm Model** and select your preferred `.litertlm` model file (e.g. Gemma-2B quantized to 4-bit).
4. The model will be copied to local app storage (`app_flutter/models/`).
5. Alternatively, tap **Skip / Use Mock Engine** to test with mock generation without model weights.

---

## License

This project is licensed under the Apache 2.0 License.
