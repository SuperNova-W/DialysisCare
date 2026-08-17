import 'dart:convert';

import 'package:http/http.dart' as http;

/// Simple API client for the RAG FastAPI backend.
class BackendApi {
  /// Override at runtime with:
  /// flutter run --dart-define=BACKEND_BASE_URL=http://10.0.2.2:8001
  /// Defaults to the production backend; use --dart-define to override it.
  static const String _rawBase = String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue: 'https://dialysiscare-backend-798621865464.us-east1.run.app',
  );

  // Normalize base URL (trim whitespace/newlines and trailing slashes)
  static final String _baseUrl = _normalizeUrl(_rawBase);

  static String _normalizeUrl(String url) {
    var v = url.trim();
    // Remove any trailing slashes
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }

  Uri _uri(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$_baseUrl$normalizedPath');
  }

  Future<Map<String, dynamic>> health() async {
    final res = await http.get(_uri('/health'));
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('Health failed: ${res.statusCode} ${res.body}');
  }

  Future<String> initializeSession() async {
    // RAG system is pre-initialized with baked-in vectors, just generate a session ID
    // Session IDs are just used client-side for tracking conversations
    return 'session_${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<ChatReply> chat({
    required String sessionId,
    required String message,
    bool useStepback = false,
    bool useCoT = true,
  }) async {
    final res = await http.post(
      _uri('/chat'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'query': '$message for ADPKD',
        'session_id': sessionId,
        'use_stepback': useStepback,
        'use_cot': useCoT,
        'pre_check_topic': true,
      }),
    );

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;

      // Parse sources array from backend
      final sources = (data['sources'] as List<dynamic>? ?? []);
      final sourceTitles = <String>[];
      final sourceAuthors = <String>[];
      final sourceCitations = <String>[];

      for (var source in sources) {
        if (source is Map<String, dynamic>) {
          final author = source['author']?.toString() ?? 'Unknown';
          final year = source['year']?.toString() ?? '';
          final title = source['title']?.toString() ?? '';

          // Create consistent, clean formatting
          final authorYear = year.isNotEmpty ? '$author ($year)' : author;

          sourceTitles.add(title);
          sourceAuthors.add(authorYear);
          sourceCitations.add(authorYear);
        }
      }

      // Parse follow-up questions
      final followupQuestions = <String>[];
      if (data['followup_questions'] is List) {
        for (var q in data['followup_questions']) {
          followupQuestions.add(q.toString());
        }
      }

      // Parse validation info
      ValidationInfo? validationInfo;
      if (data['validation'] is Map<String, dynamic>) {
        final valData = data['validation'] as Map<String, dynamic>;
        final checksRaw = valData['checks'] as Map<String, dynamic>? ?? {};
        final checks = <String, ValidationCheckResult>{};
        checksRaw.forEach((key, value) {
          if (value is Map<String, dynamic>) {
            checks[key] = ValidationCheckResult(
              passed: value['passed'] as bool? ?? true,
              score: (value['score'] as num?)?.toDouble() ?? 0.0,
            );
          }
        });
        final warnings = <String>[];
        if (valData['warnings'] is List) {
          for (var w in valData['warnings']) {
            warnings.add(w.toString());
          }
        }
        validationInfo = ValidationInfo(
          passed: valData['passed'] as bool? ?? true,
          overallScore: (valData['overall_score'] as num?)?.toDouble() ?? 0.0,
          checks: checks,
          warnings: warnings,
          wasRegenerated: valData['was_regenerated'] as bool? ?? false,
        );
      }

      return ChatReply(
        response: (data['response'] ?? '').toString(),
        sourceTitles: sourceTitles,
        sourceAuthors: sourceAuthors,
        sourceCitations: sourceCitations,
        stepbackQuery: data['stepback_query']?.toString(),
        followupQuestions: followupQuestions,
        validation: validationInfo,
      );
    }
    throw Exception('Chat failed: ${res.statusCode} ${res.body}');
  }

  /// Streams newline-delimited events from the bounded backend pipeline.
  ///
  /// The browser receives small token chunks, while the UI decides how often
  /// to paint them. This keeps transport streaming independent from rendering.
  Stream<ChatStreamEvent> chatStream({
    required String sessionId,
    required String message,
    bool useStepback = false,
    bool useCoT = true,
  }) async* {
    final client = http.Client();
    try {
      final request = http.Request('POST', _uri('/chat-stream'))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({
          'query': message,
          'session_id': sessionId,
          'use_stepback': useStepback,
          'use_cot': useCoT,
          'pre_check_topic': true,
        });

      final response = await client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await response.stream.bytesToString();
        throw Exception('Chat stream failed: ${response.statusCode} $body');
      }

      yield* decodeChatStream(response.stream);
    } catch (error) {
      yield ChatStreamEvent(
        type: ChatStreamEventType.error,
        error: error.toString(),
      );
    } finally {
      client.close();
    }
  }
}

/// Decodes the backend's NDJSON stream even when JSON lines are fragmented
/// across network packets. Kept public so the transport contract can be tested
/// without making live API requests.
Stream<ChatStreamEvent> decodeChatStream(Stream<List<int>> byteStream) async* {
  final lines = byteStream
      .transform(utf8.decoder)
      .transform(const LineSplitter());

  await for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;

    final Map<String, dynamic> payload;
    try {
      payload = jsonDecode(line) as Map<String, dynamic>;
    } on FormatException {
      continue;
    }

    final type = ChatStreamEventType.fromWireName(payload['type']?.toString());
    if (type == null) continue;
    final data = payload['data'];

    switch (type) {
      case ChatStreamEventType.status:
        yield ChatStreamEvent(type: type, status: data?.toString());
        break;
      case ChatStreamEventType.sources:
        final sourceTitles = <String>[];
        final sourceAuthors = <String>[];
        final sourceCitations = <String>[];
        for (final source in data is List ? data : const <dynamic>[]) {
          if (source is! Map<String, dynamic>) continue;
          final author = source['author']?.toString() ?? 'Unknown';
          final year = source['year']?.toString() ?? '';
          final authorYear = year.isEmpty ? author : '$author ($year)';
          sourceTitles.add(source['title']?.toString() ?? '');
          sourceAuthors.add(authorYear);
          sourceCitations.add(authorYear);
        }
        yield ChatStreamEvent(
          type: type,
          sourceTitles: sourceTitles,
          sourceAuthors: sourceAuthors,
          sourceCitations: sourceCitations,
        );
        break;
      case ChatStreamEventType.chunk:
        yield ChatStreamEvent(type: type, chunk: data?.toString());
        break;
      case ChatStreamEventType.followup:
        yield ChatStreamEvent(
          type: type,
          followupQuestions: data is List
              ? data.map((question) => question.toString()).toList()
              : const [],
        );
        break;
      case ChatStreamEventType.validation:
        yield ChatStreamEvent(
          type: type,
          validation: _parseValidation(data),
          validationText: payload['validation_text']?.toString(),
        );
        break;
      case ChatStreamEventType.error:
        yield ChatStreamEvent(
          type: type,
          error: data?.toString() ?? 'Unknown streaming error',
        );
        break;
      case ChatStreamEventType.done:
        yield ChatStreamEvent(type: type);
        return;
    }
  }
}

ValidationInfo? _parseValidation(dynamic data) {
  if (data is! Map<String, dynamic>) return null;
  final checks = <String, ValidationCheckResult>{};
  final rawChecks = data['checks'];
  if (rawChecks is Map<String, dynamic>) {
    rawChecks.forEach((name, value) {
      if (value is Map<String, dynamic>) {
        checks[name] = ValidationCheckResult(
          passed: value['passed'] as bool? ?? true,
          score: (value['score'] as num?)?.toDouble() ?? 0,
        );
      }
    });
  }
  return ValidationInfo(
    passed: data['passed'] as bool? ?? true,
    overallScore: (data['overall_score'] as num?)?.toDouble() ?? 0,
    checks: checks,
    warnings: data['warnings'] is List
        ? (data['warnings'] as List)
              .map((warning) => warning.toString())
              .toList()
        : const [],
    wasRegenerated: data['was_regenerated'] as bool? ?? false,
  );
}

enum ChatStreamEventType {
  status('status'),
  sources('sources'),
  chunk('chunk'),
  followup('followup'),
  validation('validation'),
  error('error'),
  done('done');

  const ChatStreamEventType(this.wireName);

  final String wireName;

  static ChatStreamEventType? fromWireName(String? value) {
    for (final type in values) {
      if (type.wireName == value) return type;
    }
    return null;
  }
}

class ChatStreamEvent {
  const ChatStreamEvent({
    required this.type,
    this.status,
    this.sourceTitles,
    this.sourceAuthors,
    this.sourceCitations,
    this.chunk,
    this.followupQuestions,
    this.validation,
    this.validationText,
    this.error,
  });

  final ChatStreamEventType type;
  final String? status;
  final List<String>? sourceTitles;
  final List<String>? sourceAuthors;
  final List<String>? sourceCitations;
  final String? chunk;
  final List<String>? followupQuestions;
  final ValidationInfo? validation;
  final String? validationText;
  final String? error;
}

class ChatReply {
  final String response;
  final List<String> sourceTitles;
  final List<String> sourceAuthors;
  final List<String> sourceCitations;
  final String? stepbackQuery;
  final List<String> followupQuestions;
  final ValidationInfo? validation;

  ChatReply({
    required this.response,
    required this.sourceTitles,
    required this.sourceAuthors,
    required this.sourceCitations,
    this.stepbackQuery,
    this.followupQuestions = const [],
    this.validation,
  });
}

class ValidationCheckResult {
  final bool passed;
  final double score;

  ValidationCheckResult({required this.passed, required this.score});
}

class ValidationInfo {
  final bool passed;
  final double overallScore;
  final Map<String, ValidationCheckResult> checks;
  final List<String> warnings;
  final bool wasRegenerated;

  ValidationInfo({
    required this.passed,
    required this.overallScore,
    required this.checks,
    this.warnings = const [],
    this.wasRegenerated = false,
  });
}
