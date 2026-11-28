<h1 align="center">Smriti — Offline Personal Knowledge Base</h1>

<p align="center">
  <b>Private • On-Device • RAG</b>
</p>

---

**Smriti** (स्मृति — *memory / recollection*) is a private personal knowledge base. You import your own documents (PDF, Markdown, text, or images), Smriti indexes them into a local on-device vector database, and a local LiteRT language model answers your questions using the most relevant passages (RAG).

Documents, embeddings, and inference all stay on your device. The app code makes no network requests; the only external links (model download pages on Hugging Face) open in your browser.

---

## Demo
Uploading soon

---

## Screenshots

| Chat (RAG answer) | Knowledge Base | Chunk Viewer | AI Model Setup |
|:---:|:---:|:---:|:---:|
| <img width="200" alt="Responses image" src="https://github.com/user-attachments/assets/fe53b0d7-f78b-4c65-99b7-cb0ed7971d3a" /> | <img width="200" alt="Indexed documents" src="https://github.com/user-attachments/assets/3433da4a-d680-4aa7-af82-6bec81977851" /> | <img width="200" alt="Chunk viewer" src="https://github.com/user-attachments/assets/3e20a381-f39e-4d52-ba58-43730cf4725f" /> | <img width="200" alt="Model Setup" src="https://github.com/user-attachments/assets/cc5538f6-780a-42e6-b388-2b3355439bbc" /> |
| Ask questions about your documents; answers stream token by token. | Indexed documents with chunk counts. | Tap a document to inspect exactly how it was split into chunks. | Import or activate a `.litertlm` model and tune the context budget. |

---

## Key Features

- **Private, on-device pipeline:** parsing, chunking, embedding, vector search, and LLM inference all run locally. No telemetry and no cloud APIs.
- **Multi-format ingestion:** `.pdf`, `.txt`, `.md`, `.png`, `.jpg`, `.jpeg`.
- **Structure-aware chunking:** Splits prefer headings, then paragraphs, lines, sentences, and words.
- **Streaming chat:** token-by-token answers grounded in retrieved excerpts.
- **Model Manager:** import a `.litertlm` model or activate one already on the device. GPU-first loading with CPU fallback.
- **Context-overflow recovery:** on `RESOURCE_EXHAUSTED`, the prompt is retried with halved context, then question-only, before the raw error is shown in a dismissible banner.
- **Mock mode:** a deterministic mock LLM and embedder for development and testing without model weights.
- **Chunk viewer:** inspect how any indexed document was split.
- **RAM friendly:** model weights are released when the app is backgrounded.

---

## How It Works

<img width="2172" height="724" alt="Document Ingestion and Query Flowchart" src="https://github.com/user-attachments/assets/708b8528-c821-48cf-85e4-508d2e0866ee" />


**Embeddings:** `EdgeEmbeddingService` produces 384-dimensional vectors from hashed word, bigram, and character-trigram features (TF-IDF-style weighting). It is lightweight and fully offline, but it is **not a neural embedding model**, so semantic matching is limited and the keyword side of retrieval does most of the work.

---

## Tech Stack

| Layer | Technology |
|---|---|
| **Platform** | Currently Android only (`minSdk 24`) |
| **Framework** | Flutter |
| **State management** | `provider` (`ChangeNotifier` + `MultiProvider`) |
| **Vector database** | `objectbox` + `objectbox_flutter_libs` |
| **LLM runtime** | `flutter_edge_ai` + `flutter_edge_ai_litertlm` |
| **PDF parsing** | `syncfusion_flutter_pdf`, `pdfx` |
| **OCR** | `google_mlkit_text_recognition` |
| **File access / links** | `file_picker`, `path_provider`, `path`, `url_launcher` |
| **Codegen & build** | `build_runner`, `objectbox_generator` |

---

## Getting Started

### Prerequisites
- Flutter SDK (stable channel; the project was last verified with Flutter 3.50 / Dart 3.14)
- Android SDK with an Android 7.0+ (API 24+) device or emulator. A physical arm64 device is recommended for on-device models.

### Run
```bash
flutter pub get
flutter run
```

### Test and analyze
```bash
flutter analyze
flutter test        # 100+ unit, provider, and widget tests
```

### Regenerate ObjectBox code (after editing `DocumentChunk`)
```bash
dart run build_runner build --delete-conflicting-outputs
```

### Build a release APK
```bash
flutter build apk --release
```
Output: `build/app/outputs/flutter-apk/app-release.apk`. Release builds use R8 shrinking and ProGuard keep rules for ObjectBox and LiteRT. The release build is signed with the debug key by default; configure your own keystore before distributing.

---

## On-Device Model Setup

1. Download a `.litertlm` model using the links in **AI Model Setup** (tap the tune icon in the app bar at any time):
   - **Gemma 4 E2B** (recommended, ~2.4 GB): use the pinned revision linked in the app; newer revisions may not be supported by the bundled runtime.
   - **Qwen3 0.6B** (~350 MB): for lower-RAM devices.
2. In the app, choose **Activate Downloaded Model** to use a file already on the device.
3. The model loads in the background; the chat shows "Model is loading…" and then greets you when it is ready.
4. If answers get cut off or you see context errors, lower the **context budget** slider. If you have RAM to spare, raise it.
5. **Skip / Use Mock Engine** lets you try the UI without model weights.

> After installing a model for the first time, restart the app and re-add any documents you indexed earlier in mock mode. The embedder is selected at startup, and mock-mode vectors are not meaningful for retrieval.

---

## Usage

1. Open the **Documents** tab and tap **Add Document** to import a PDF, text/Markdown file, or image.
2. Wait for indexing to finish. The chunk count appears under the file name. Tap a document to inspect its chunks.
3. Switch to **Chat** and ask a question about your documents.
4. Delete a document from the Documents tab to remove its chunks and vectors.

---

## Known Limitations

- **No conversation memory:** each question is answered independently, so follow-ups like "and for ECE?" lack context.
- **Source citations** are computed but not currently displayed in chat bubbles.
- **Android only**, Latin-script OCR only, and a single `.litertlm` model active at a time.

---

## License

Apache 2.0. Add a `LICENSE` file to the repository root with the full license text.
