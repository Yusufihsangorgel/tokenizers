// The claim the README opens with, run rather than pictured.
//
//   dart run example/parity.dart
//
// One sentence takes two paths that share a vocabulary. The first is this
// package, which hands the text to the Rust `tokenizers` crate and gets back
// whatever `tokenizer.json` declares. The second is the shortest thing that
// looks correct: lowercase each word, then look it up in the vocabulary table
// read straight out of that same file.
//
// Everything below is computed at run time from the fixture committed in this
// repository. The fixture is pinned instead of taken from the command line
// because the reference ids belong to it. Against another model there would be
// nothing to check the encode against.
import 'dart:convert';
import 'dart:io';

import 'package:hf_tokenizers/hf_tokenizers.dart';

const _fixture = 'test/fixtures/bert-base-uncased.json';

/// The sentence from the README. Three different accented characters, which
/// keeps the result from resting on one lucky special case.
const _text = 'The naïve café in São Paulo';

/// The ids HuggingFace's own implementation returns for [_text] with this
/// fixture, and the ids printed on the README. Typed in deliberately: a run
/// compared against its own output would agree with itself and prove nothing.
const _reference = [1996, 15743, 7668, 1999, 7509, 9094];

/// One word, carried down both paths.
typedef _Col = ({String word, String token, int id, int? naiveId});

void main() {
  final tk = Tokenizer.fromFile(_fixture);
  final ids = tk.encode(_text, addSpecialTokens: false);
  final tokens = [for (final id in ids) tk.idToToken(id)!];
  tk.close();

  // The shortcut gets the real vocabulary, out of the same file. Anything the
  // two rows disagree about is the pipeline around the lookup.
  final json =
      jsonDecode(File(_fixture).readAsStringSync()) as Map<String, dynamic>;
  final model = json['model'] as Map<String, dynamic>;
  final vocab = model['vocab'] as Map<String, dynamic>;
  final unkToken = model['unk_token'] as String;
  final unkId = vocab[unkToken] as int;
  final normalizer = json['normalizer'] as Map<String, dynamic>;

  final words = _text.split(' ');

  // Two aligned rows stay honest only while each word is one token. Stop with
  // a readable reason rather than print a table whose columns have slipped.
  if (words.length != tokens.length) {
    throw StateError(
      '"$_text" is ${words.length} words but ${tokens.length} tokens, and the '
      'table below pairs them off one to one.',
    );
  }

  final cols = <_Col>[
    for (var i = 0; i < words.length; i++)
      (
        word: words[i],
        token: tokens[i],
        id: ids[i],
        naiveId: vocab[words[i].toLowerCase()] as int?,
      ),
  ];

  // Column widths come from the longest cell, so the two rows line up under
  // each other and a reader can compare them by eye.
  final widths = [
    for (final c in cols)
      2 +
          [
            c.word.length,
            c.token.length,
            '${c.id}'.length,
            c.naiveId?.toString().length ?? unkToken.length,
          ].reduce((a, b) => a > b ? a : b),
  ];

  const gutter = 20;
  String row(String label, List<String> cells) {
    final b = StringBuffer(label.padRight(gutter));
    for (var i = 0; i < cells.length; i++) {
      b.write(cells[i].padRight(widths[i]));
    }
    return b.toString().trimRight();
  }

  print('${'input'.padRight(gutter)}$_text\n');
  print(row('hf_tokenizers', [for (final c in cols) c.token]));
  print(row('  id', [for (final c in cols) '${c.id}']));
  print('');
  print(
    row('lowercase, look up', [for (final c in cols) c.word.toLowerCase()]),
  );
  print(row('  id', [for (final c in cols) c.naiveId?.toString() ?? unkToken]));

  // The top row against the values HuggingFace produces. If this ever printed
  // "no", every token count this package hands back would be wrong by an
  // amount nothing else reports.
  final matches = ids.join(',') == _reference.join(',');
  print(
    '\nencode(text, addSpecialTokens: false) == the reference ids: '
    '${matches ? 'yes' : 'no'}',
  );

  final lost = [
    for (final c in cols)
      if (c.naiveId == null) c.word,
  ];
  final agreed = cols.length - lost.length;
  print(
    '${lost.length} of ${cols.length} words never reached the vocabulary: '
    '${lost.join(', ')}.',
  );
  print(
    'Each came back as $unkId, the id this file gives $unkToken.\n'
    '${lost.length} words, one id, and nothing downstream can separate them '
    'again.',
  );
  print(
    'The $agreed that agreed are the ASCII ones, which is how a shortcut\n'
    'passes its tests and still breaks on the first accented name a user '
    'types.',
  );

  // Why the rows differ at all. Reading the configuration literally is not
  // enough to reproduce the top row.
  print(
    '\nBoth rows read $_fixture.\n'
    'Its normalizer is "${normalizer['type']}", '
    'lowercase=${normalizer['lowercase']}, '
    'strip_accents=${normalizer['strip_accents']}.\n'
    'The accents came off regardless. Reproducing that takes the crate, or a\n'
    'faithful copy of its rules.',
  );
}
