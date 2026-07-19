import 'dart:convert';
import 'dart:typed_data';

import 'package:hf_tokenizers/hf_tokenizers.dart';
import 'package:test/test.dart';

void main() {
  const fixture = 'test/fixtures/bert-base-uncased.json';

  group('Tokenizer (bert-base-uncased)', () {
    late Tokenizer tk;
    setUpAll(() => tk = Tokenizer.fromFile(fixture));
    tearDownAll(() => tk.close());

    test('vocab size matches the model', () {
      expect(tk.vocabSize, 30522);
    });

    test('encode is byte-exact with HuggingFace', () {
      // [CLS] hello world [SEP]
      expect(tk.encode('hello world'), [101, 7592, 2088, 102]);
      // Without special tokens.
      expect(tk.encode('hello world', addSpecialTokens: false), [7592, 2088]);
    });

    test('decode round-trips', () {
      final ids = tk.encode('the quick brown fox', addSpecialTokens: false);
      expect(tk.decode(ids), 'the quick brown fox');
    });

    test('encodeWithOffsets keeps ids and maps tokens back to the input', () {
      const text = 'hello world';
      final bytes = utf8.encode(text);
      final tokens = tk.encodeWithOffsets(text, addSpecialTokens: false);
      // Same ids as encode(), in the same order.
      expect(tokens.map((t) => t.id).toList(),
          tk.encode(text, addSpecialTokens: false));
      // The byte offsets recover the original words (slice the UTF-8 bytes).
      expect(
        tokens
            .map((t) => utf8.decode(bytes.sublist(t.start, t.end)))
            .toList(),
        ['hello', 'world'],
      );
    });

    test('encodeWithOffsets offsets are UTF-8 byte ranges, not UTF-16', () {
      // 'é' is two UTF-8 bytes but one UTF-16 unit, so a byte offset past it is
      // larger than the character index. This is why callers slice the bytes.
      const text = 'café bar';
      final bytes = utf8.encode(text);
      final tokens = tk.encodeWithOffsets(text, addSpecialTokens: false);
      expect(tokens.last.end, bytes.length); // last token ends at the last byte
      expect(utf8.decode(bytes.sublist(tokens.last.start, tokens.last.end)),
          'bar');
      // The 'bar' token starts at byte 6 (café=5 bytes + space), past the
      // UTF-16 length would be off by the multibyte 'é'.
      expect(tokens.last.start, 6);
    });

    test('encodeWithOffsets gives special tokens an empty range', () {
      // [CLS] hello world [SEP]: the added specials carry no input span.
      final tokens = tk.encodeWithOffsets('hello world');
      expect(tokens.first.id, 101); // [CLS]
      expect(tokens.first.start, tokens.first.end); // empty range
      expect(tokens.last.id, 102); // [SEP]
      expect(tokens.last.start, tokens.last.end);
      // The middle two carry the real spans.
      expect(tokens[1].id, 7592);
      final bytes = utf8.encode('hello world');
      expect(utf8.decode(bytes.sublist(tokens[1].start, tokens[1].end)),
          'hello');
    });

    test('handles WordPiece splitting of unknown-ish words', () {
      // "tokenization" splits into token ##ization under bert wordpiece.
      final ids = tk.encode('tokenization', addSpecialTokens: false);
      expect(ids.length, greaterThan(1));
      expect(tk.decode(ids), 'tokenization');
    });

    test('tokenToId looks up single tokens, including special ones', () {
      // These are the fixed ids bert-base-uncased assigns.
      expect(tk.tokenToId('[CLS]'), 101);
      expect(tk.tokenToId('[SEP]'), 102);
      expect(tk.tokenToId('hello'), 7592);
    });

    test('tokenToId returns null for a token outside the vocabulary', () {
      expect(tk.tokenToId('thisisnotarealtoken'), isNull);
    });

    test('idToToken is the inverse of tokenToId', () {
      expect(tk.idToToken(101), '[CLS]');
      expect(tk.idToToken(7592), 'hello');
      // WordPiece continuation tokens keep their ## marker, unlike decode.
      final ids = tk.encode('tokenization', addSpecialTokens: false);
      final pieces = ids.map(tk.idToToken).toList();
      expect(pieces, ['token', '##ization']);
    });

    test('idToToken returns null for an id outside the vocabulary', () {
      expect(tk.idToToken(tk.vocabSize + 1000), isNull);
    });

    test('tokenToId and idToToken round-trip every encoded id', () {
      for (final id in tk.encode('the quick brown fox')) {
        final token = tk.idToToken(id);
        expect(token, isNotNull);
        expect(tk.tokenToId(token!), id);
      }
    });
  });

  test('fromBytes rejects invalid json', () {
    expect(
      () => Tokenizer.fromBytes(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });

  test('using a closed tokenizer throws', () {
    final tk = Tokenizer.fromFile(fixture)..close();
    expect(() => tk.encode('x'), throwsStateError);
  });
}
