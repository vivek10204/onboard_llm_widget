//IMP: Diff from example (new)

import 'package:shared_preferences/shared_preferences.dart';

class PromptPrefs {
  static const _kPreamble = 'prompt_preamble';
  static const _kInputCsv = 'prompt_input_csv';
  static const _kOutputSchema = 'prompt_output_schema';

  // SAVE
  static Future<void> save({
    String? preamble,
    String? inputCsv,
    String? outputSchema,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (preamble != null) await prefs.setString(_kPreamble, preamble);
    if (inputCsv != null) await prefs.setString(_kInputCsv, inputCsv);
    if (outputSchema != null) await prefs.setString(_kOutputSchema, outputSchema);
  }

  // LOAD (single)
  static Future<String?> loadPreamble() async =>
      (await SharedPreferences.getInstance()).getString(_kPreamble);

  static Future<String?> loadInputCsv() async =>
      (await SharedPreferences.getInstance()).getString(_kInputCsv);

  static Future<String?> loadOutputSchema() async =>
      (await SharedPreferences.getInstance()).getString(_kOutputSchema);

  // LOAD (all at once)
  static Future<({String? preamble, String? inputCsv, String? outputSchema})> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    return (
    preamble: prefs.getString(_kPreamble),
    inputCsv: prefs.getString(_kInputCsv),
    outputSchema: prefs.getString(_kOutputSchema),
    );
  }
}
