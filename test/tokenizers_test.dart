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

    test('count matches encode().length, including specials', () {
      // count is the same number encode would give. BERT's two specials make
      // the empty string the interesting case: it is 2, not 0.
      expect(tk.count('hello world'), 4);
      expect(tk.count('hello world', addSpecialTokens: false), 2);
      expect(tk.count(''), 2);
      expect(tk.count('', addSpecialTokens: false), 0);
      const mixed = 'The naïve café in São Paulo';
      expect(tk.count(mixed), tk.encode(mixed).length);
      expect(
        tk.count(mixed, addSpecialTokens: false),
        tk.encode(mixed, addSpecialTokens: false).length,
      );
    });

    test('count sees past a U+0000 the same way encode does', () {
      const withNul = 'hello\u0000world';
      expect(
        tk.count(withNul, addSpecialTokens: false),
        tk.encode(withNul, addSpecialTokens: false).length,
      );
      expect(
        tk.count(withNul, addSpecialTokens: false),
        greaterThan(tk.count('hello', addSpecialTokens: false)),
      );
    });

    test('a U+0000 byte does not truncate the input', () {
      // The old FFI passed a NUL-terminated buffer, so a U+0000 cut the text
      // off at the first NUL and every token after it was lost. With an
      // explicit byte length the whole string reaches the tokenizer.
      const withNul = 'hello\u0000world';
      final ids = tk.encode(withNul, addSpecialTokens: false);
      // The bytes after the NUL contribute tokens the truncating version could
      // never see.
      expect(
        ids.length,
        greaterThan(tk.encode('hello', addSpecialTokens: false).length),
      );
      // And that content survives the round trip.
      expect(tk.decode(ids), contains('world'));
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
      expect(
        tokens.map((t) => t.id).toList(),
        tk.encode(text, addSpecialTokens: false),
      );
      // The byte offsets recover the original words (slice the UTF-8 bytes).
      expect(
        tokens.map((t) => utf8.decode(bytes.sublist(t.start, t.end))).toList(),
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
      expect(
        utf8.decode(bytes.sublist(tokens.last.start, tokens.last.end)),
        'bar',
      );
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
      expect(
        utf8.decode(bytes.sublist(tokens[1].start, tokens[1].end)),
        'hello',
      );
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

    test('idToToken returns null for an id that does not fit a uint32', () {
      // The native lookup takes a uint32, so 1 << 32 and 1 << 40 both used to
      // wrap to 0 and come back as that id's token instead of null.
      expect(tk.idToToken(0), isNotNull, reason: 'id 0 is a real token');
      expect(tk.idToToken(1 << 32), isNull);
      expect(tk.idToToken(1 << 40), isNull);
      expect(tk.idToToken(-1), isNull);
    });

    test('TokenOffset values with the same fields are equal', () {
      final a = tk.encodeWithOffsets('the quick brown fox');
      final b = tk.encodeWithOffsets('the quick brown fox');
      expect(a, b);
      // Values from two separate calls have to collapse into one another. A
      // set built from just one of them proves nothing: a Set is never larger
      // than the list it came from, whatever == and hashCode do.
      expect({...a, ...b}, hasLength(a.length));
      expect(const TokenOffset(1, 0, 3) == const TokenOffset(1, 0, 4), isFalse);
    });

    test('decode rejects an id that does not fit a uint32', () {
      // Truncating into a different valid id would decode to the wrong token
      // rather than fail: 1 << 40 came back as [PAD].
      expect(() => tk.decode([1 << 40]), throwsArgumentError);
      expect(() => tk.decode([-1]), throwsArgumentError);
      expect(() => tk.decode([101, 1 << 32, 102]), throwsArgumentError);
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
    expect(() => tk.count('x'), throwsStateError);
  });

  test('closing twice is safe', () {
    // The second call has to return early rather than free the handle again.
    final tk = Tokenizer.fromFile(fixture)..close();
    expect(tk.close, returnsNormally);
    expect(() => tk.encode('x'), throwsStateError);
  });

  test('decode drops special tokens unless asked to keep them', () {
    final tk = Tokenizer.fromFile(fixture);
    addTearDown(tk.close);
    final ids = tk.encode('hello world');

    expect(tk.decode(ids), 'hello world');
    expect(tk.decode(ids, skipSpecialTokens: false), '[CLS] hello world [SEP]');
  });
}
