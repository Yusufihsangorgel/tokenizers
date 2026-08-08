// Token-exact chunking for rag_kit.
//
//   dart run example/rag_chunking.dart [path/to/tokenizer.json]
//
// rag_kit's built-in chunkers cut on characters, and its own documentation
// says why that is a compromise: an embedding model's limit is in tokens, the
// ratio is not a constant, and a chunk that comes out over the limit is
// silently truncated by the model rather than rejected. Search quality drops
// with nothing raised to explain it.
//
// This package already knows the exact boundaries. `encodeWithOffsets` returns
// each token with the UTF-8 byte span it came from, so a window over tokens
// maps back to a real range in the source once those bytes are converted to
// UTF-16 indices — see the note in `chunk`, which is the part that is easy to
// get wrong.
//
// ⚠️ Scope: this package is FFI and ships prebuilts for Linux, macOS and
// Windows only, so this composition is a server and desktop story. On mobile
// or web, stay with `Chunker.fixed` and size it against your own corpus.
import 'dart:io';

import 'package:hf_tokenizers/hf_tokenizers.dart';
import 'package:rag_kit/rag_kit.dart';

/// A [Chunker] that counts tokens rather than characters.
///
/// Produces chunks of at most [maxTokens] tokens, with [overlapTokens] shared
/// between consecutive chunks so a sentence split by a window edge survives
/// whole in one of them.
final class TokenChunker extends Chunker {
  TokenChunker(this._tokenizer, {this.maxTokens = 256, this.overlapTokens = 32})
    : assert(maxTokens > 0),
      assert(overlapTokens >= 0 && overlapTokens < maxTokens);

  final Tokenizer _tokenizer;

  /// The hard ceiling on tokens per chunk. Unlike a character budget this is
  /// the number the model actually counts.
  final int maxTokens;

  /// Tokens repeated at the start of the next chunk.
  final int overlapTokens;

  @override
  List<Chunk> chunk(String text) {
    if (text.isEmpty) return const [];

    // Special tokens belong to the model call, not to the stored text: adding
    // them here would spend budget on markers the chunk does not contain.
    final tokens = _tokenizer.encodeWithOffsets(text, addSpecialTokens: false);
    if (tokens.isEmpty) return const [];

    // ⚠️ The seam that makes this adapter necessary. `TokenOffset` reports
    // **UTF-8 byte** offsets, because that is what the `tokenizers` crate
    // works in. `Chunk` promises the opposite: its doc is explicit that
    // `source.substring(chunk.start, chunk.end)` equals the chunk text, and
    // `substring` counts UTF-16 units. For ASCII the two agree and the bug
    // hides; add one Japanese sentence and a byte offset runs past the end of
    // the Dart string. Convert once, up front.
    final toUtf16 = _byteToUtf16Index(text);

    final step = maxTokens - overlapTokens;
    final chunks = <Chunk>[];
    for (var i = 0; i < tokens.length; i += step) {
      final last = (i + maxTokens < tokens.length)
          ? i + maxTokens - 1
          : tokens.length - 1;
      final start = toUtf16[tokens[i].start];
      final end = toUtf16[tokens[last].end];
      chunks.add(
        Chunk(
          text: text.substring(start, end),
          start: start,
          end: end,
          metadata: {'tokens': last - i + 1},
        ),
      );
      if (last == tokens.length - 1) break;
    }
    return chunks;
  }

  /// Maps every UTF-8 byte offset in [text] to the UTF-16 index at or before
  /// it, so a byte span from the tokenizer becomes a `substring` range.
  ///
  /// The array is one longer than the byte length so the exclusive end of the
  /// last token maps to `text.length`.
  static List<int> _byteToUtf16Index(String text) {
    final map = <int>[];
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      final int bytes;
      if (unit < 0x80) {
        bytes = 1;
      } else if (unit < 0x800) {
        bytes = 2;
      } else if (unit >= 0xD800 && unit <= 0xDBFF) {
        // A surrogate pair is four UTF-8 bytes across two UTF-16 units. Emit
        // them against the leading unit and skip the trailing one.
        bytes = 4;
        map.addAll(List.filled(bytes, i));
        i++;
        continue;
      } else {
        bytes = 3;
      }
      map.addAll(List.filled(bytes, i));
    }
    map.add(text.length);
    return map;
  }
}

Future<void> main(List<String> args) async {
  final path = args.isEmpty
      ? 'test/fixtures/bert-base-uncased.json'
      : args.first;
  if (!File(path).existsSync()) {
    stderr.writeln(
      'usage: dart run example/rag_chunking.dart [path/to/tokenizer.json]\n'
      '($path is missing, so there is nothing to fall back to)',
    );
    exitCode = 64;
    return;
  }
  final tokenizer = Tokenizer.fromFile(path);

  // Deliberately mixed: English prose runs near four characters per token,
  // while CJK can approach one. A character budget cannot be right for both,
  // which is the whole reason this file exists.
  const document =
      'Retrieval quality depends on what the model actually sees. '
      'An embedding model counts tokens, not characters, and truncates '
      'silently when a chunk runs over. 検索の品質はモデルが実際に見たものに依存します。'
      'Mixing scripts in one corpus makes a character budget wrong for at '
      'least one of them.';

  const budget = 24;
  final chunker = TokenChunker(tokenizer, maxTokens: budget, overlapTokens: 4);
  final chunks = chunker.chunk(document);

  print(
    'document: ${document.length} characters, '
    '${tokenizer.encode(document, addSpecialTokens: false).length} tokens',
  );
  print('budget:   $budget tokens per chunk\n');

  for (final (index, chunk) in chunks.indexed) {
    final tokens = chunk.metadata['tokens'];
    final chars = chunk.end - chunk.start;
    print(
      'chunk $index: $tokens tokens, $chars chars '
      '(${(chars / (tokens! as int)).toStringAsFixed(1)} chars/token)',
    );
    print(
      '  [${chunk.start}..${chunk.end}) '
      '${chunk.text.replaceAll('\n', ' ')}',
    );
  }

  // rag_kit's Chunk contract, checked rather than trusted: the offsets must
  // index the source string. This is the assertion that would have caught the
  // byte-versus-UTF-16 mistake, so it stays in the example.
  for (final chunk in chunks) {
    if (document.substring(chunk.start, chunk.end) != chunk.text) {
      throw StateError('offsets do not index the source at ${chunk.start}');
    }
  }
  print(
    '\nall ${chunks.length} chunks satisfy '
    'source.substring(start, end) == text',
  );

  // The claim this file makes, checked rather than asserted: re-encoding every
  // chunk on its own must stay inside the budget. A character chunker cannot
  // promise that.
  final over = chunks
      .where(
        (c) =>
            tokenizer.encode(c.text, addSpecialTokens: false).length > budget,
      )
      .length;
  print('\nchunks over the $budget-token budget when re-encoded: $over');

  // And the ratio the budget would have had to guess, per chunk.
  final ratios = chunks.map(
    (c) => (c.end - c.start) / (c.metadata['tokens']! as int),
  );
  print(
    'chars per token ranged '
    '${ratios.reduce((a, b) => a < b ? a : b).toStringAsFixed(1)} to '
    '${ratios.reduce((a, b) => a > b ? a : b).toStringAsFixed(1)} '
    'across the same document',
  );

  tokenizer.close();
}
