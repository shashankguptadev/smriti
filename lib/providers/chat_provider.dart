import 'package:flutter/foundation.dart';
import '../core/models/chat_message.dart';
import '../services/rag_service.dart';
import 'model_manager_provider.dart';

/// Status of the active chat conversation.
enum ChatStatus {
  idle,
  streaming,
  error,
}

/// [ChangeNotifier] managing chat history and streaming LLM responses.
class ChatProvider extends ChangeNotifier {
  static const String modelLoadingLabel = 'Model is loading...';
  static const String modelLoadedGreeting =
      'Hello, I am Smriti. Your offline personal knowledge assistant';

  final RagService ragService;
  final ModelManagerProvider? modelManager;

  final List<ChatMessage> _messages = [];
  ChatStatus _status = ChatStatus.idle;
  String? _errorMessage;
  ChatMessage? _modelLoadingMessage;
  bool _wasModelLoading = false;

  ChatProvider({
    required this.ragService,
    this.modelManager,
  }) {
    if (modelManager != null) {
      modelManager!.addListener(_onModelManagerChanged);
      _syncModelLoadingState();
    }
  }

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  ChatStatus get status => _status;
  String? get errorMessage => _errorMessage;
  bool get isStreaming => _status == ChatStatus.streaming;

  void _onModelManagerChanged() {
    if (_syncModelLoadingState()) {
      notifyListeners();
    }
  }

  /// Synchronizes the chat's "Model is loading..." placeholder bubble with
  /// [ModelManagerProvider.isModelLoadingInBackground], replacing it with
  /// [modelLoadedGreeting] once the real model finishes loading.
  bool _syncModelLoadingState() {
    final manager = modelManager;
    if (manager == null) return false;

    final isLoading = manager.isModelLoadingInBackground;
    if (isLoading && !_wasModelLoading) {
      _wasModelLoading = true;
      final loadingMsg = ChatMessage(
        role: MessageRole.assistant,
        text: '',
        isStreaming: true,
        loadingText: modelLoadingLabel,
      );
      _modelLoadingMessage = loadingMsg;
      _messages.add(loadingMsg);
      return true;
    }

    if (!isLoading && _wasModelLoading) {
      _wasModelLoading = false;
      final loadingMsg = _modelLoadingMessage;
      _modelLoadingMessage = null;

      if (manager.hasRealModel) {
        if (loadingMsg != null && _messages.contains(loadingMsg)) {
          loadingMsg.text = modelLoadedGreeting;
          loadingMsg.isStreaming = false;
        } else {
          _messages.add(ChatMessage(
            role: MessageRole.assistant,
            text: modelLoadedGreeting,
          ));
        }
      } else {
        if (loadingMsg != null) {
          _messages.remove(loadingMsg);
        }
        if (manager.status == ModelStatus.error &&
            manager.errorMessage != null) {
          _errorMessage = manager.errorMessage;
        }
      }
      return true;
    }

    return false;
  }

  @override
  void dispose() {
    modelManager?.removeListener(_onModelManagerChanged);
    super.dispose();
  }

  /// Sends [text] to the RAG pipeline and streams the generated answer.
  Future<void> sendMessage(String text) async {
    final query = text.trim();
    if (query.isEmpty) return;

    _status = ChatStatus.streaming;
    _errorMessage = null;

    // 1. Add user message
    _messages.add(ChatMessage(
      role: MessageRole.user,
      text: query,
    ));
    notifyListeners();

    // 2. Query source citations and create an active assistant message placeholder
    ChatMessage? assistantMessage;
    try {
      final rawSources = await ragService.getSourceChunks(query);
      final sources = rawSources.map(CitationSource.fromMap).toList();

      assistantMessage = ChatMessage(
        role: MessageRole.assistant,
        text: '',
        sources: sources,
        isStreaming: true,
      );
      _messages.add(assistantMessage);
      notifyListeners();

      // 3. Stream tokens into the assistant message
      await for (final token in ragService.ask(query, contextChunks: rawSources)) {
        assistantMessage.text += token;
        notifyListeners();
      }

      assistantMessage.isStreaming = false;
      _status = ChatStatus.idle;
      notifyListeners();
    } catch (e) {
      _status = ChatStatus.error;
      _errorMessage = e.toString();
      if (assistantMessage != null) {
        assistantMessage.isStreaming = false;
        if (assistantMessage.text.isEmpty) {
          assistantMessage.text = 'Error generating answer: $e';
        }
      }
      notifyListeners();
    }
  }

  /// Clears all messages in the conversation history.
  void clearChat() {
    _messages.clear();
    _modelLoadingMessage = null;
    _status = ChatStatus.idle;
    _errorMessage = null;
    notifyListeners();
  }

  /// Clears the active error message and resets error status to idle.
  void clearError() {
    _errorMessage = null;
    if (_status == ChatStatus.error) {
      _status = ChatStatus.idle;
    }
    notifyListeners();
  }
}
