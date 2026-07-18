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
