// Measures `count` against `encode(text).length` and `encodeWithOffsets`.
//
// The HuggingFace crate has `encode_fast`, which skips offset conversion, but
// still runs the tokenize pipeline that determines the count. This package's
// `count` is `encode().length`; this tool exists to show whether a skip would
// have been visible from Dart, so the CHANGELOG can quote a measurement rather
// than a hope.
//
//   dart run tool/measure_count.dart
//
// Exit code is 1 if `count` and `encode().length` ever disagree.
import 'dart:io';

import 'package:hf_tokenizers/hf_tokenizers.dart';

const _fixture = 'test/fixtures/bert-base-uncased.json';

const _short = 'hello world';

const _prompt = '''
Summarise the following support thread for an engineer on call. Keep the
customer's account id, the error codes, and the timestamps. Drop the
pleasantries. If the thread contains a stack trace, keep only the top frame:
NoSuchMethodError: 'call' on null at package:acme/sync.dart:412:9.''';

final _long = 'The naïve café in São Paulo. ' * 200;

void main() {
  final tk = Tokenizer.fromFile(_fixture);
  var failed = false;

  for (final entry in {
    'short (11 chars)': _short,
    'prompt (${_prompt.length} chars)': _prompt,
    'long (${_long.length} chars)': _long,
  }.entries) {
    final name = entry.key;
    final text = entry.value;
    final encoded = tk.encode(text).length;
    final counted = tk.count(text);
    final offsetted = tk.encodeWithOffsets(text).length;
    if (counted != encoded || offsetted != encoded) {
      stderr.writeln(
        'MISMATCH $name: encode=$encoded count=$counted '
        'encodeWithOffsets=$offsetted',
      );
      failed = true;
      continue;
    }

    // Warm the three paths so the timed loops are not paying first-call costs.
    for (var i = 0; i < 50; i++) {
      tk.encode(text);
      tk.count(text);
      tk.encodeWithOffsets(text);
    }

    const rounds = 400;
    final encodeUs = _time(rounds, () => tk.encode(text).length);
    final countUs = _time(rounds, () => tk.count(text));
    final offsetsUs = _time(rounds, () => tk.encodeWithOffsets(text).length);

    final vsEncode = encodeUs / countUs;
    final vsOffsets = offsetsUs / countUs;
    stdout.writeln(
      '$name -> $encoded tokens, $rounds rounds\n'
      '  encode().length            ${_fmt(encodeUs)} µs/call\n'
      '  encodeWithOffsets().length ${_fmt(offsetsUs)} µs/call\n'
      '  count()                    ${_fmt(countUs)} µs/call\n'
      '  count vs encode:           ${vsEncode.toStringAsFixed(2)}x\n'
      '  count vs offsets:          ${vsOffsets.toStringAsFixed(2)}x',
    );
  }

  tk.close();
  exit(failed ? 1 : 0);
}

int _time(int rounds, int Function() run) {
  final sw = Stopwatch()..start();
  for (var i = 0; i < rounds; i++) {
    run();
  }
  sw.stop();
  return sw.elapsedMicroseconds ~/ rounds;
}

String _fmt(int us) => us.toString().padLeft(6);
