import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../config/ai_config.dart';
import '../utils/model_mode.dart';

/// Central AI service — routes between your Modal karmax-lora model and
/// Google Gemini FREE tier (gemini-3.1-flash-lite), based on ModelMode switch.
class AiService {
  static String get _apiKey => AiConfig.apiKey;
  static const String _model = 'gemini-3.1-flash-lite';
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent';

  /// Set by _route() on every call so the UI can show which backend
  /// actually produced the last result (Modal vs Gemini vs Gemini-fallback).
  static String lastSource = 'none';

  /// Set whenever Modal fails and Gemini is used as a fallback.
  /// Null means "no error" — the UI should only show a warning when this
  /// is non-null. Cleared at the start of every _route() call so stale
  /// errors from a previous request don't linger on screen.
  static String? lastError;

  // ── 1. Analyse free-text problem ──────────────────────────────────────
  Future<Map<String, dynamic>> analyseProblem(String rawProblem) async {
    final prompt = 'Analyse this student problem: "$rawProblem"\n\n'
        'Reply with ONLY a valid JSON object. No markdown, no code fences, no extra text. '
        'Start your reply with { and end with }.\n\n'
        'Required JSON shape:\n'
        '{"id":"snake_case_id","title":"Short Title","subtitle":"one line",'
        '"icon":"emoji","causes":["cause 1","cause 2","cause 3","cause 4","cause 5"],'
        '"summary":"Two empathetic sentences about their specific situation."}';

    return await _route(prompt, maxTokens: 800);
  }

  // ── 2. Generate quiz questions ────────────────────────────────────────
  Future<Map<String, dynamic>> generateQuizQuestions({
    required String problemTitle,
    required List<String> causes,
    String problemSummary = '',
  }) async {
    final causeList = causes.take(3).join(', ');
    final prompt = 'Student problem: $problemTitle. Root causes: $causeList\n\n'
        'Generate exactly 5 quiz questions to diagnose this student. '
        'Reply with ONLY a valid JSON object. No markdown, no code fences. '
        'Start with { and end with }.\n\n'
        'Required shape:\n'
        '{"questions":[{"question":"question text","options":["opt1","opt2","opt3","opt4"]}]}';

    return await _route(prompt, maxTokens: 1000);
  }

  // ── 3. Generate quests ────────────────────────────────────────────────
  Future<Map<String, dynamic>> generateQuests({
    required String playerName,
    required String schedule,
    required String problemTitle,
    required String problemSubtitle,
    required List<String> selectedCauses,
    required List<String> quizAnswers,
    required double sleepHours,
    required double studyHours,
    required double screenTimeHours,
    required int stressLevel,
    required double physicalActivityHours,
    required double socialHours,
    required double gpa,
    required String emotion,
  }) async {
    final causes = selectedCauses.take(3).join(', ');
    final answers = quizAnswers.take(3).join('; ');
    final prompt =
        'Student $playerName, schedule: $schedule, problem: $problemTitle. '
        'Causes: $causes. Quiz answers: $answers\n\n'
        'Current lifestyle state: sleeps ${sleepHours.toStringAsFixed(1)} hrs/night, '
        'studies ${studyHours.toStringAsFixed(1)} hrs/day, '
        'screen time ${screenTimeHours.toStringAsFixed(1)} hrs/day, '
        'self-rated stress $stressLevel/5, '
        'physical activity ${physicalActivityHours.toStringAsFixed(1)} hrs/day, '
        'social time ${socialHours.toStringAsFixed(1)} hrs/day, '
        'GPA ${gpa.toStringAsFixed(1)}/4.0, current mood: $emotion.\n\n'
        'First, reason about this student like a behavior coach would: '
        'identify the primary problem, the most likely root cause — taking the '
        'lifestyle state above into account, not just the stated problem — and '
        'explain in 2-3 sentences why the quests below are the right intervention. '
        'Then generate 5 daily quests and 3 weekly quests. '
        'Reply with ONLY a valid JSON object. No markdown, no code fences. '
        'Start with { and end with }.\n\n'
        'Required shape:\n'
        '{"primary_problem":"short label","root_cause":"short label",'
        '"reasoning":"2-3 sentence explanation of why this intervention was chosen",'
        '"daily":[{"title":"quest title","xp":15,"category":"discipline","why":"one reason"}],'
        '"weekly":[{"title":"quest title","xp":40,"category":"health","why":"one reason"}]}';

    return await _route(prompt, maxTokens: 1100);
  }

  // ── Router: Modal if switch is ON, Gemini otherwise ────────────────────
  Future<Map<String, dynamic>> _route(String prompt,
      {int maxTokens = 800}) async {
    // Clear any error from a previous call so the UI doesn't show a stale
    // warning for a request that actually succeeded this time.
    lastError = null;

    debugPrint(
        '[AiService] ModelMode.useModal = ${ModelMode.instance.useModal}');
    debugPrint('[AiService] AiConfig.modalUrl = "${AiConfig.modalUrl}"');

    if (ModelMode.instance.useModal) {
      try {
        final result = await _callModal(prompt, maxTokens: maxTokens);
        lastSource = 'modal';
        debugPrint('[AiService] ✓ Modal call succeeded');
        return result;
      } catch (e, st) {
        // Previously this failure was invisible — only a debugPrint that's
        // easy to miss. Now it's both logged loudly AND stored in
        // lastError so the UI can surface a visible warning to the user.
        debugPrint('══════════════════════════════════════════════');
        debugPrint('[AiService] ✗ MODAL CALL FAILED — falling back to Gemini');
        debugPrint('[AiService] Error: $e');
        debugPrint('[AiService] Stack: $st');
        debugPrint('══════════════════════════════════════════════');

        lastSource = 'gemini_fallback';
        lastError = 'Your model failed to respond, so Gemini answered '
            'instead. (${_shortError(e)})';

        try {
          return await _callWithRetry(prompt, maxTokens: maxTokens);
        } catch (geminiError) {
          // Both Modal and Gemini failed — this is a total failure, not
          // just a fallback. Overwrite lastError so the UI shows the
          // right message instead of the misleading "used Gemini instead."
          lastSource = 'none';
          lastError = 'Both your model and Gemini failed to respond. '
              '(${_shortError(geminiError)})';
          rethrow;
        }
      }
    }
    lastSource = 'gemini';
    return await _callWithRetry(prompt, maxTokens: maxTokens);
  }

  /// Keeps error messages short and free of stack traces / raw response
  /// bodies before they ever reach the UI.
  String _shortError(Object e) {
    final s = e.toString().replaceFirst('Exception: ', '');
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }

  // ── Modal (vLLM, OpenAI-compatible) ────────────────────────────────────
  Future<Map<String, dynamic>> _callModal(String prompt,
      {int maxTokens = 800}) async {
    if (AiConfig.modalUrl.isEmpty) {
      throw Exception(
          'AiConfig.modalUrl is empty — Modal endpoint not configured');
    }

    debugPrint('[AiService] Calling Modal at ${AiConfig.modalUrl} ...');

    final response = await http
        .post(
          Uri.parse(AiConfig.modalUrl),
          headers: {
            'Content-Type': 'application/json',
            // NOTE: if your Modal deployment requires auth (most do when
            // deployed with `modal deploy` behind a token), add it here, e.g.:
            // 'Authorization': 'Bearer ${AiConfig.modalToken}',
          },
          body: jsonEncode({
            'model':
                'karmax', // must match --lora-modules name in your modal_app.py
            'messages': [
              {'role': 'user', 'content': prompt}
            ],
            'max_tokens': maxTokens,
            'temperature': 0.5,
          }),
        )
        // 5 minutes, not 60s: your Modal container cold-starts from zero on
        // the first request after it's been idle, and that alone can take
        // several minutes. A short timeout was firing before Modal ever
        // finished, forcing a Gemini fallback every time. Once the
        // container is warm, later calls return in seconds — this only
        // matters for that first (or first-after-idle) request.
        //
        // onTimeout gives a clear, debuggable message instead of the
        // default TimeoutException text, so lastError (shown in the UI)
        // actually tells you what happened instead of a vague stack trace.
        .timeout(
          const Duration(minutes: 5),
          onTimeout: () => throw Exception(
              'Modal connection timed out after 5 minutes — the endpoint '
              'at ${AiConfig.modalUrl} did not respond in time. Check '
              '`python -m modal app logs karmax-lora-vllm` to see if the '
              'container is stuck, crashed, or the URL/account is wrong.'),
        );

    debugPrint(
        '[AiService] Modal responded with status ${response.statusCode}');

    if (response.statusCode != 200) {
      throw Exception(
          'Modal API error ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final rawText = data['choices'][0]['message']['content'] as String;
    debugPrint('[AiService] Modal raw response: $rawText');
    return jsonDecode(_stripFences(rawText)) as Map<String, dynamic>;
  }

  /// Cleans a raw model response into a string that should be pure JSON.
  ///
  /// Handles three sources of noise seen in practice:
  ///  1. Markdown code fences (```json ... ```), which some models add
  ///     even when told not to.
  ///  2. <think>...</think> reasoning blocks emitted by reasoning-tuned
  ///     models (like the karmax LoRA) before their actual answer. Without
  ///     this, jsonDecode() throws on the leading '<', which _route()
  ///     misinterprets as "Modal failed" even though it actually answered.
  ///  3. Any other stray leading/trailing text — handled defensively by
  ///     extracting the substring between the first '{' and the last '}'.
  String _stripFences(String text) {
    var t = text.trim();

    // Strip <think>...</think> reasoning blocks some models emit before
    // their actual answer.
    t = t.replaceAll(
        RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '');

    t = t
        .replaceAll(RegExp(r'```json', caseSensitive: false), '')
        .replaceAll('```', '')
        .trim();

    // Defensive: if there's still leading/trailing junk (e.g. an unclosed
    // <think> tag because the response got cut off at max_tokens, or
    // stray commentary), extract the first {...} JSON object rather than
    // assuming the whole string is clean.
    final start = t.indexOf('{');
    final end = t.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      t = t.substring(start, end + 1);
    }

    return t;
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
          'responseMimeType': 'application/json',
        },
      }),
    );

    if (response.statusCode == 429 && attempt <= 3) {
      final waitSeconds = attempt * 10;
      debugPrint(
          '[AiService] 429 — retrying in ${waitSeconds}s (attempt $attempt/3)');
      await Future.delayed(Duration(seconds: waitSeconds));
      return _callWithRetry(prompt, maxTokens: maxTokens, attempt: attempt + 1);
    }

    if (response.statusCode != 200) {
      throw Exception(
          'Gemini API error ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = data['candidates'] as List<dynamic>;
    final parts = candidates[0]['content']['parts'] as List<dynamic>;
    final rawText = parts
        .whereType<Map<String, dynamic>>()
        .map((p) => p['text'] as String? ?? '')
        .join('');

    final cleaned = _stripFences(rawText);
    debugPrint('[AiService] Gemini response: $cleaned');
    return jsonDecode(cleaned) as Map<String, dynamic>;
  }
}
