import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../config/ai_config.dart';

/// Central AI service — Google Gemini FREE tier (gemini-2.5-flash).
/// GET YOUR FREE KEY → https://aistudio.google.com/app/apikey
/// Free limit: 10 req/min, 250 req/day. Quota is per PROJECT not per key.
class AiService {
  // Google is migrating Gemini API keys from the old "Standard" format
  // (AIza...) to a new "Auth key" format (AQ...). Auth keys are sent via
  // the X-goog-api-key HEADER rather than a ?key= query parameter — see
  // _callWithRetry below.
  //
  // The key itself is never hardcoded here — it's resolved at runtime from
  // a --dart-define or a gitignored .env file via AiConfig, exactly like
  // SupabaseConfig resolves the Supabase credentials. This keeps real
  // secrets out of source control (and out of GitHub's push protection).
  static String get _apiKey => AiConfig.apiKey;
  static const String _model = 'gemini-3.1-flash-lite';
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent';

  // ── 1. Analyse free-text problem ──────────────────────────────────────
  Future<Map<String, dynamic>> analyseProblem(String rawProblem) async {
    final prompt =
        'Analyse this student problem: "$rawProblem"\n\n'
        'Reply with ONLY a valid JSON object. No markdown, no code fences, no extra text. '
        'Start your reply with { and end with }.\n\n'
        'Required JSON shape:\n'
        '{"id":"snake_case_id","title":"Short Title","subtitle":"one line",'
        '"icon":"emoji","causes":["cause 1","cause 2","cause 3","cause 4","cause 5"],'
        '"summary":"Two empathetic sentences about their specific situation."}';

    return await _callWithRetry(prompt, maxTokens: 800);
  }

  // ── 2. Generate quiz questions ────────────────────────────────────────
  Future<Map<String, dynamic>> generateQuizQuestions({
    required String problemTitle,
    required List<String> causes,
    String problemSummary = '',
  }) async {
    final causeList = causes.take(3).join(', ');
    final prompt =
        'Student problem: $problemTitle. Root causes: $causeList\n\n'
        'Generate exactly 5 quiz questions to diagnose this student. '
        'Reply with ONLY a valid JSON object. No markdown, no code fences. '
        'Start with { and end with }.\n\n'
        'Required shape:\n'
        '{"questions":[{"question":"question text","options":["opt1","opt2","opt3","opt4"]}]}';

    return await _callWithRetry(prompt, maxTokens: 1000);
  }

  // ── 3. Generate quests ────────────────────────────────────────────────
  Future<Map<String, dynamic>> generateQuests({
    required String playerName,
    required String schedule,
    required String problemTitle,
    required String problemSubtitle,
    required List<String> selectedCauses,
    required List<String> quizAnswers,
  }) async {
    final causes = selectedCauses.take(3).join(', ');
    final answers = quizAnswers.take(3).join('; ');
    final prompt =
        'Student $playerName, schedule: $schedule, problem: $problemTitle. '
        'Causes: $causes. Quiz answers: $answers\n\n'
        'Generate 5 daily quests and 3 weekly quests. '
        'Reply with ONLY a valid JSON object. No markdown, no code fences. '
        'Start with { and end with }.\n\n'
        'Required shape:\n'
        '{"daily":[{"title":"quest title","xp":"15","category":"discipline","why":"one reason"}],'
        '"weekly":[{"title":"quest title","xp":"40","category":"health","why":"one reason"}]}';

    return await _callWithRetry(prompt, maxTokens: 900);
  }

  // ── Internal: call Gemini with auto-retry on 429 ──────────────────────
  Future<Map<String, dynamic>> _callWithRetry(String prompt,
      {int maxTokens = 800, int attempt = 1}) async {
    if (!AiConfig.isConfigured) {
      throw Exception(AiConfig.missingConfigMessage);
    }

    final url = Uri.parse(_baseUrl);

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'X-goog-api-key': _apiKey,
      },
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'generationConfig': {
          'maxOutputTokens': maxTokens,
          'temperature': 0.5,
          'responseMimeType': 'application/json', // force JSON output
        },
      }),
    );

    // Rate limited — wait and retry
    if (response.statusCode == 429 && attempt <= 3) {
      final waitSeconds = attempt * 10;
      debugPrint('[AiService] 429 — retrying in ${waitSeconds}s (attempt $attempt/3)');
      await Future.delayed(Duration(seconds: waitSeconds));
      return _callWithRetry(prompt, maxTokens: maxTokens, attempt: attempt + 1);
    }

    if (response.statusCode != 200) {
      throw Exception('Gemini API error ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = data['candidates'] as List<dynamic>;
    final parts = candidates[0]['content']['parts'] as List<dynamic>;
    final rawText = parts
        .whereType<Map<String, dynamic>>()
        .map((p) => p['text'] as String? ?? '')
        .join('');

    // Strip any markdown fences just in case
    final cleaned = rawText
        .replaceAll(RegExp(r'```json', caseSensitive: false), '')
        .replaceAll('```', '')
        .trim();

    debugPrint('[AiService] Response: $cleaned');
    return jsonDecode(cleaned) as Map<String, dynamic>;
  }
}