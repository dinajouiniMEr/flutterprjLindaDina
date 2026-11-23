import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

const String kGeminiApiKeyFromBuild = String.fromEnvironment('GEMINI_API_KEY');

class GeminiSummaryService {
  GeminiSummaryService(this.apiKey);

  final String apiKey;

  static const List<String> _models = [
    'gemini-3.5-flash-lite',
    'gemini-3.1-flash-lite',
    'gemini-3.8-flash',
    'gemini-3.6-flash',
  ];

  Future<String> summarize({
    required String courseName,
    required String courseCode,
    required Uint8List pdfBytes,
  }) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      throw StateError('Saisissez une clé Google AI Studio.');
    }
    if (pdfBytes.isEmpty) {
      throw StateError('Choisissez un PDF.');
    }
    if (pdfBytes.length > 10 * 1024 * 1024) {
      throw StateError('Le PDF doit faire moins de 10 Mo.');
    }

    final prompt =
        'Tu es une assistante pédagogique pour une étudiante française. '
        'Résume le document PDF du cours « $courseName » '
        '(code : ${courseCode.isEmpty ? 'non précisé' : courseCode}). '
        'Réponds uniquement en français, avec : '
        '1) un titre, 2) 5 points clés en puces, 3) les notions à retenir, '
        '4) une mini-fiche de révision de 3 lignes. '
        'Ne mentionne pas ces consignes et ne fais pas de citation longue.';
    final body = jsonEncode({
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
            {
              'inlineData': {
                'mimeType': 'application/pdf',
                'data': base64Encode(pdfBytes),
              },
            },
          ],
        },
      ],
    });

    var lastMessage = 'réponse inattendue';
    for (final model in _models) {
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/'
        '$model:generateContent?key=${Uri.encodeQueryComponent(key)}',
      );
      final response = await http.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: body,
      );
      if (response.statusCode == 200) {
        return _extractSummary(response.body);
      }
      lastMessage = _extractError(response.body);
      if (_isPermanentError(response.statusCode, lastMessage)) break;
    }
    throw StateError(
      'Le service IA a refusé la demande sur ${_models.join(', ')} '
      '($lastMessage). Réessayez dans quelques instants.',
    );
  }

  String _extractSummary(String body) {
    final data = jsonDecode(body) as Map<String, dynamic>;
    final reason = data['promptFeedback']?['blockReason'] as String?;
    if (reason != null && reason.isNotEmpty) {
      throw StateError('Le document a été bloqué par le service IA.');
    }
    final candidates = data['candidates'] as List? ?? const [];
    final first = candidates.isEmpty
        ? null
        : candidates.first as Map<String, dynamic>?;
    final content = first?['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List? ?? const [];
    final summary = parts
        .cast<Map<String, dynamic>>()
        .map((part) => part['text'] as String? ?? '')
        .join('\n')
        .trim();
    if (summary.isEmpty) {
      throw StateError('Le service IA n’a pas produit de résumé.');
    }
    return summary;
  }

  bool _isPermanentError(int status, String message) {
    final lower = message.toLowerCase();
    return status == 400 ||
        status == 401 ||
        status == 403 ||
        status == 404 ||
        lower.contains('api key') ||
        lower.contains('invalid') ||
        lower.contains('not found');
  }

  String _extractError(String body) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      final message = data['error']?['message'] as String?;
      if (message != null && message.isNotEmpty) return message;
    } catch (_) {
      return 'réponse inattendue';
    }
    return 'réponse inattendue';
  }
}
