// Runs inside the app the compat workflow generates, not in this package:
// flutter_test and integration_test resolve there. tool/ci/prepare_app.dart
// copies it and test/fixtures/bert-base-uncased.json to the app.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hf_tokenizers/hf_tokenizers.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('encodes and decodes with a bundled tokenizer.json', () async {
    final data = await rootBundle.load('assets/bert-base-uncased.json');
    final tokenizer = Tokenizer.fromBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    addTearDown(tokenizer.close);

    expect(tokenizer.vocabSize, 30522);
    final ids = tokenizer.encode('hello world');
    // [CLS] hello world [SEP], the ids HuggingFace gives.
    expect(ids, [101, 7592, 2088, 102]);
    expect(tokenizer.decode(ids), 'hello world');
  });

  test('rejects malformed JSON with FormatException', () {
    final truncated = utf8.encode('{"version": "1.0", "model": {');

    expect(() => Tokenizer.fromBytes(truncated), throwsFormatException);
  });
}
