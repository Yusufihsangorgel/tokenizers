/// Counting tokens before you spend them.
///
/// Every call to a model has a budget measured in tokens, and going over it is
/// not a warning, it is a rejected request or a silently truncated answer. This
/// runs the three things that budget needs: an honest count, a way to cut text
/// down to fit, and a way to split a long document into pieces that each fit.
///
///     dart run example/context_budget.dart [path/to/tokenizer.json]
///
/// Defaults to the BERT fixture in this repository. Point it at the
/// tokenizer.json that ships with the model you actually call and the numbers
/// below become your numbers.
library;

import 'package:hf_tokenizers/hf_tokenizers.dart';

const _prompt = '''
Summarise the following support thread for an engineer on call. Keep the
customer's account id, the error codes, and the timestamps. Drop the
pleasantries. If the thread contains a stack trace, keep only the top frame:
NoSuchMethodError: 'call' on null at package:acme/sync.dart:412:9.''';

void main(List<String> args) {
  final path = args.isEmpty
      ? 'test/fixtures/bert-base-uncased.json'
      : args.first;
  final tk = Tokenizer.fromFile(path);

  // 1. The counts are the reference implementation's counts, not an
  //    approximation of them. If these ids drifted, every budget below would be
  //    wrong in a way nothing would report until a request was rejected.
  final reference = tk.encode('hello world');
  print('encode("hello world") -> $reference');
  print(
    'byte-exact with the reference implementation: '
    '${reference.toString() == '[101, 7592, 2088, 102]' ? 'yes' : 'no'}\n',
  );

  // 2. What the usual shortcut costs. Estimating a quarter of a token per
  //    character is the rule of thumb everyone reaches for, and it is wrong by
  //    a different amount for every piece of text: prose, code, identifiers and
  //    punctuation all tokenize at different rates.
  final estimate = (_prompt.length / 4).ceil();
  final actual = tk.count(_prompt);
  final off = ((estimate - actual) / actual * 100).round();
  print('a ${_prompt.length}-character prompt');
  print('  chars / 4 says   $estimate tokens');
  print('  the tokenizer says $actual tokens');
  print(
    '  the shortcut is ${off.abs()}% ${off < 0 ? 'under' : 'over'}, and '
    '${off < 0 ? 'under is the direction that overflows' : 'over just wastes budget'}\n',
  );

  // 3. Cutting to fit. The cut lands on a token boundary, so no character is
  //    split, and the special tokens the model adds come off the budget up
  //    front rather than pushing the result one token over.
  const budget = 40;
  final head = tk.truncateToTokens(_prompt, budget);
  final headTokens = tk.encode(head).length;
  print('truncateToTokens(prompt, $budget)');
  print(
    '  kept ${head.length} characters, which re-encode to $headTokens '
    'tokens${headTokens <= budget ? ' (fits)' : ' (OVER BUDGET)'}',
  );
  print('  ...${head.substring(head.length - 48).replaceAll('\n', ' ')}\n');

  // 4. Splitting for retrieval. Overlap repeats context across the seam so a
  //    sentence cut in half is still findable from either piece.
  final chunks = tk.chunkByTokens(_prompt, 24, overlapTokens: 6);
  print(
    'chunkByTokens(prompt, 24, overlapTokens: 6) -> ${chunks.length} pieces',
  );
  for (final (i, chunk) in chunks.indexed) {
    final n = tk.encode(chunk).length;
    print('  ${i + 1}. [$n tok] ${chunk.trim().replaceAll('\n', ' ')}');
  }
  final over = chunks.where((c) => tk.encode(c).length > 24).length;
  print('\npieces over the 24-token budget: $over');

  tk.close();
}
