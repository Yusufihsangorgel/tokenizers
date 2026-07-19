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
