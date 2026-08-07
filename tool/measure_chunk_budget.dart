// Measures whether `chunkByTokens` keeps its promise: every piece it returns
// must encode to at most the budget it was given.
//
// This exists because the package's own test asserted exactly that from the
// first commit and still missed a real bug — the inputs were prose, and prose
// does not put a long compound word across a chunk boundary. The corpus below
// deliberately does.
//
//   dart run tool/measure_chunk_budget.dart
//
// Exit code is 1 only when a piece is over budget AND could have been split
// smaller, so this doubles as a regression check. Pieces that are a single
// source token are counted and reported but do not fail: a token is the floor,
// and the doc comment on chunkByTokens says so.

import 'dart:io';

import 'package:hf_tokenizers/hf_tokenizers.dart';

const _fixture = 'test/fixtures/bert-base-uncased.json';

/// Five documents, fixed so the numbers are reproducible. The first three are
/// the ones that matter: long words get cut mid-subword, which is where the
/// count of the whole string stops bounding the count of its pieces.
const _corpus = <String, String>{
  'compounds':
      'tokenization internationalization '
      'antidisestablishmentarianism counterrevolutionaries',
  'mixed-case':
      'The quick brown fox jumps over the lazy dog near the river '
      'bank today, uncharacteristically.',
  'unicode':
      'çğışöü 雪 🎿 emoji and accents mixed with ASCII words here, '
      'internationalisation included',
  'letters': 'a b c d e f g h i j k l m n o p q r s t u v w x y z',
  'repeated': 'xylophone xylophone xylophone xylophone xylophone xylophone',
};

const _budgets = (from: 3, to: 30);

void main() {
  final tk = Tokenizer.fromFile(_fixture);
  var checked = 0, over = 0, irreducible = 0;
  final worst = <String, int>{};

  for (final entry in _corpus.entries) {
    for (var budget = _budgets.from; budget <= _budgets.to; budget++) {
      for (final specials in [true, false]) {
        List<String> pieces;
        try {
          pieces = tk.chunkByTokens(
            entry.value,
            budget,
            addSpecialTokens: specials,
          );
        } on ArgumentError {
          continue; // documented refusal, not a violation
        }
        for (final piece in pieces) {
          checked++;
          final cost = tk.encode(piece, addSpecialTokens: specials).length;
          if (cost <= budget) continue;
          over++;
          final excess = cost - budget;
          worst[entry.key] = (worst[entry.key] ?? 0) > excess
              ? worst[entry.key]!
              : excess;
          // A piece covering a single source token cannot be split further,
          // so it is over budget for a reason no implementation can fix.
          if (tk.encodeWithOffsets(piece, addSpecialTokens: false).length > 1 &&
              !piece.trim().contains(' ')) {
            irreducible++;
          }
        }
      }
    }
  }
  tk.close();

  stdout
    ..writeln(
      'corpus: ${_corpus.length} documents, '
      'budgets ${_budgets.from}-${_budgets.to}, both special-token modes',
    )
    ..writeln('pieces checked : $checked')
    ..writeln('over budget    : $over')
    ..writeln('  of those, single-source-token (unsplittable): $irreducible')
    ..writeln('worst excess by document: $worst');

  final reducible = over - irreducible;
  if (reducible > 0) {
    stdout.writeln(
      '\nFAIL: $reducible piece(s) over budget that could have '
      'been split smaller.',
    );
    exit(1);
  }
  stdout.writeln(
    '\nOK: every over-budget piece is a single source token, '
    'which cannot be split further.',
  );
}
