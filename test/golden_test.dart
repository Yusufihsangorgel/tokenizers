import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:hf_tokenizers/hf_tokenizers.dart';
import 'package:test/test.dart';

const _fixture = 'test/fixtures/bert-base-uncased.json';
const _corpus = 'test/golden/corpus.json';
const _golden = 'test/golden/bert-base-uncased.jsonl';
const _libraryLock = 'native/tokenizers_ffi/Cargo.lock';
const _generatorLock = 'tool/golden/Cargo.lock';

/// Compares the Dart API with what the Rust `tokenizers` crate returns for the
/// same corpus.
///
/// The generator in `tool/golden` wrote the expected file from the crate
/// directly. This test writes the same document from the Dart API and compares
/// the bytes. CONTRIBUTING.md says how to regenerate the expected file.
void main() {
  test('the Dart API matches the crate output byte for byte', () {
    final tk = Tokenizer.fromFile(_fixture);
    addTearDown(tk.close);

    final actual = utf8.encode(_render(tk));
    // Git can check the file out with CRLF line endings on Windows. Both
    // writers escape a CR inside a string, and a raw CR byte can only come
    // from that conversion.
    final expected = [
      for (final b in File(_golden).readAsBytesSync())
        if (b != 0x0d) b,
    ];
    final at = _firstDifference(expected, actual);
    if (at != null) fail(_describe(expected, actual, at));
  });

  test('the generator builds against the versions the library locks', () {
    final library = _lockedVersions(_libraryLock)..remove('tokenizers_ffi');
    final generator = _lockedVersions(_generatorLock)..remove('golden');
    expect(library['tokenizers'], hasLength(1));
    expect(
      generator.keys.toSet(),
      library.keys.toSet(),
      reason: 'Both lock files have to hold the same packages.',
    );
    expect(
      _requirement('tool/golden/Cargo.toml'),
      _requirement('native/tokenizers_ffi/Cargo.toml'),
      reason:
          'The generator has to ask for the tokenizers version and '
          'features the library asks for.',
    );

    final drift = [
      for (final MapEntry(key: name, value: versions) in library.entries)
        if (generator[name] case final other?
            when !_sameVersions(versions, other))
          '$name ${versions.join(', ')} in $_libraryLock, '
              '${other.join(', ')} in $_generatorLock',
    ];
    expect(
      drift,
      isEmpty,
      reason:
          'The golden file has to come from the crate the library is built '
          'from. Copy $_libraryLock over $_generatorLock and regenerate as '
          'CONTRIBUTING.md describes.',
    );
  });
}

/// Writes the document the generator writes, from the Dart API.
String _render(Tokenizer tk) {
  final lines = [
    jsonEncode({
      'tokenizers': _lockedVersions(_libraryLock)['tokenizers']!.single,
      'vocab_size': tk.vocabSize,
    }),
  ];
  for (final entry
      in jsonDecode(File(_corpus).readAsStringSync()) as List<Object?>) {
    final c = entry as Map<String, Object?>;
    final name = c['name']! as String;
    final text = (c['text']! as String) * ((c['repeat'] as int?) ?? 1);

    for (final special in [true, false]) {
      final ids = tk.encode(text, addSpecialTokens: special);
      final spans = tk.encodeWithOffsets(text, addSpecialTokens: special);
      expect(
        [for (final t in spans) t.id],
        ids,
        reason: '$name gets different ids from encode and encodeWithOffsets',
      );
      lines.add(
        jsonEncode({
          'case': name,
          'add_special_tokens': special,
          'ids': ids,
          'tokens': [for (final id in ids) tk.idToToken(id)],
          'offsets': [
            for (final t in spans) [t.start, t.end],
          ],
          // The Dart API returns no masks. These are the two rules the
          // package relies on, checked against the masks the crate reports.
          // Nothing is padded, and a special token owns an empty span.
          'attention_mask': [for (final _ in ids) 1],
          'special_tokens_mask': [
            for (final t in spans) t.start == t.end ? 1 : 0,
          ],
          'decode': tk.decode(ids),
          'decode_keep_special': tk.decode(ids, skipSpecialTokens: false),
        }),
      );
    }

    // The crate truncates the encoding of the whole text. The Dart API cuts
    // the text, the cut text has to encode to the same tokens, and the cut has
    // to land where the last kept token ends. Inside a Hangul syllable the
    // crate keeps some of its jamo tokens, which no cut of the text can match.
    // The Korean case truncates only at syllable ends.
    for (final budget in (c['truncate'] as List<Object?>?) ?? const []) {
      final maxTokens = budget as int;
      final head = tk.truncateToTokens(text, maxTokens);
      final spans = tk.encodeWithOffsets(head);
      if (head != text) {
        final kept = [
          for (final t in spans)
            if (t.end > t.start) t,
        ];
        expect(
          utf8.encode(head).length,
          kept.isEmpty ? 0 : kept.last.end,
          reason:
              '$name cut to $maxTokens does not end where its last token '
              'ends',
        );
      }
      lines.add(
        jsonEncode({
          'case': name,
          'truncate_to': maxTokens,
          'ids': [for (final t in spans) t.id],
          'offsets': [
            for (final t in spans) [t.start, t.end],
          ],
        }),
      );
    }
  }
  return '${lines.join('\n')}\n';
}

/// Package names mapped to the versions a `Cargo.lock` pins for them. A name
/// can appear more than once with different versions.
Map<String, Set<String>> _lockedVersions(String path) {
  final versions = <String, Set<String>>{};
  String? name;
  for (final line in File(path).readAsLinesSync()) {
    if (RegExp(r'^name = "(.+)"$').firstMatch(line) case final m?) {
      name = m[1];
    } else if (RegExp(r'^version = "(.+)"$').firstMatch(line) case final m?
        when name != null) {
      (versions[name] ??= {}).add(m[1]!);
      name = null;
    }
  }
  return versions;
}

bool _sameVersions(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

int? _firstDifference(List<int> a, List<int> b) {
  final shared = min(a.length, b.length);
  for (var i = 0; i < shared; i++) {
    if (a[i] != b[i]) return i;
  }
  return a.length == b.length ? null : shared;
}

/// Names the first differing byte with its line, column and corpus case, and
/// shows the bytes around it on both sides.
String _describe(List<int> expected, List<int> actual, int at) {
  final lineStart = at == 0 ? 0 : expected.lastIndexOf(0x0a, at - 1) + 1;
  final line = expected.take(lineStart).where((b) => b == 0x0a).length + 1;
  final lineEnd = expected.indexOf(0x0a, lineStart);
  var name = '(none)';
  try {
    final record = jsonDecode(
      utf8.decode(
        expected.sublist(lineStart, lineEnd < 0 ? expected.length : lineEnd),
      ),
    );
    if (record case {'case': final String value}) name = '"$value"';
  } on FormatException {
    // The expected file is not JSON there. The excerpt below still shows it.
  }

  String excerpt(List<int> bytes) {
    final from = max(0, at - 40);
    final to = min(bytes.length, at + 40);
    if (from >= to) return '(ends before byte $at)';
    return utf8
        .decode(bytes.sublist(from, to), allowMalformed: true)
        .replaceAll('\n', r'\n');
  }

  return 'First difference at byte $at of $_golden, line $line, column '
      '${at - lineStart + 1}, case $name.\n'
      'golden  ${excerpt(expected)}\n'
      'dart    ${excerpt(actual)}\n'
      'The golden file holds what the tokenizers crate returned. A difference '
      'means the Dart API disagrees with it. Regenerate only after a crate or '
      'corpus change, as CONTRIBUTING.md describes.';
}

/// The `tokenizers` dependency line of a Cargo manifest.
String _requirement(String manifest) => File(
  manifest,
).readAsLinesSync().singleWhere((line) => line.startsWith('tokenizers = '));
