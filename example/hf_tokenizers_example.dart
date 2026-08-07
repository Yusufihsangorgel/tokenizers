// Loads a tokenizer.json and shows two things: byte-exact encode/decode, and
// using token offsets to split text into token-budgeted chunks that still carry
// their original characters (the preprocessing step a RAG pipeline needs).
//
// Run: dart run example/hf_tokenizers_example.dart
import 'dart:convert';

import 'package:hf_tokenizers/hf_tokenizers.dart';

void main() {
  final tk = Tokenizer.fromFile('test/fixtures/bert-base-uncased.json');
  print('vocab size: ${tk.vocabSize}');

  const text = 'hello world';
  final ids = tk.encode(text);
  print('encode("$text") -> $ids'); // [101, 7592, 2088, 102]
  print('decode($ids) -> "${tk.decode(ids)}"');

  // Chunking by hand, to show the primitive underneath.
  //
  // `tk.chunkByTokens(document, 12)` does this in one call and handles the
  // parts left out below: the whitespace between two token spans, the special
  // tokens the model adds on top of each piece, and overlap across the seam.
  // Reach for the loop only when you need a window rule of your own, for
  // instance breaking on sentences that happen to fit. See
  // example/context_budget.dart for the direct route.
  //
  // encodeWithOffsets is what makes either possible: it gives the tokens (to
  // count against the budget) and the byte span (to recover the text).
  const document =
      'Native tokenization runs in Dart. It is byte-exact with the '
      'reference implementation, so retrieval and generation agree on token '
      'boundaries. That matters when a context window is measured in tokens.';
  const budget = 12; // tokens per chunk

  final bytes = utf8.encode(document);
  final tokens = tk.encodeWithOffsets(document, addSpecialTokens: false);

  print('\n$budget-token chunks of a ${tokens.length}-token document:');
  for (var i = 0; i < tokens.length; i += budget) {
    final window = tokens.sublist(i, (i + budget).clamp(0, tokens.length));
    // The chunk's text runs from the first token's start to the last's end.
    final chunk = utf8.decode(
      bytes.sublist(window.first.start, window.last.end),
    );
    print('  [${window.length} tok] ${chunk.trim()}');
  }

  tk.close();
}
