import 'dart:convert';

import 'package:hf_tokenizers/hf_tokenizers.dart';
import 'package:test/test.dart';

const fixture = 'test/fixtures/bert-base-uncased.json';

/// Non-ASCII on purpose: byte offsets and character indices diverge here, which
/// is where a substring-based cut would split a character in half.
const _mixed =
    'Istanbul kedileri sokakta yaşar, café köşelerinde uyur ve 🍰 sever. '
    'The quick brown fox jumps over the lazy dog, repeatedly and at length. '
    'Ölçüm yapmadan iddia etme; sayıyı göster, sonra konuş.';

void main() {
  late Tokenizer tk;
  setUpAll(() => tk = Tokenizer.fromFile(fixture));
  tearDownAll(() => tk.close());

  group('truncateToTokens', () {
    test('the result really fits the budget, measured not assumed', () {
      // BERT adds two special tokens, so 3 is the smallest workable budget.
      for (final budget in [3, 5, 12, 30]) {
        final head = tk.truncateToTokens(_mixed, budget);
        expect(
          tk.encode(head).length,
          lessThanOrEqualTo(budget),
          reason: 'budget $budget produced "$head"',
        );
      }
    });

    test('it is a prefix of the input, cut on a character boundary', () {
      final head = tk.truncateToTokens(_mixed, 12);
      expect(_mixed.startsWith(head), isTrue);
      // Decoding succeeded at all, so the cut did not land inside a character;
      // re-encoding the bytes proves it round-trips.
      expect(utf8.decode(utf8.encode(head)), head);
    });

    test('text that already fits comes back unchanged', () {
      const short = 'hello world';
      expect(tk.truncateToTokens(short, 1000), short);
    });

    test('a budget of zero gives an empty string', () {
      expect(tk.truncateToTokens(_mixed, 0), isEmpty);
    });

    test('a bigger budget never gives back less text', () {
      var previous = 0;
      for (final budget in [3, 6, 10, 20, 40]) {
        final length = tk.truncateToTokens(_mixed, budget).length;
        expect(length, greaterThanOrEqualTo(previous));
        previous = length;
      }
    });

    test('special tokens count against the budget', () {
      // BERT adds [CLS] and [SEP], so a budget of 3 leaves room for one word.
      final withSpecials = tk.truncateToTokens(_mixed, 3);
      final without = tk.truncateToTokens(_mixed, 3, addSpecialTokens: false);
      expect(without.length, greaterThan(withSpecials.length));
    });

    test('a negative budget is rejected', () {
      expect(() => tk.truncateToTokens(_mixed, -1), throwsArgumentError);
    });

    test('a budget no text could meet is rejected, not silently emptied', () {
      // BERT adds [CLS] and [SEP], so even '' encodes to 2. Handing back an
      // empty string would blow the very budget this call enforces.
      expect(() => tk.truncateToTokens(_mixed, 1), throwsArgumentError);
      expect(() => tk.truncateToTokens(_mixed, 2), throwsArgumentError);
      // Without the markers there is nothing to reserve, so 1 is fine.
      expect(
        tk.encode(
          tk.truncateToTokens(_mixed, 1, addSpecialTokens: false),
          addSpecialTokens: false,
        ).length,
        lessThanOrEqualTo(1),
      );
    });
  });

  group('chunkByTokens', () {
    test('every chunk fits the budget, measured with the tokenizer', () {
      const budget = 16;
      final chunks = tk.chunkByTokens(_mixed, budget);
      expect(chunks, isNotEmpty);
      for (final chunk in chunks) {
        expect(
          tk.encode(chunk).length,
          lessThanOrEqualTo(budget),
          reason: 'chunk "$chunk" blew the budget',
        );
      }
    });

    test('chunks without overlap reproduce the input', () {
      final chunks = tk.chunkByTokens(_mixed, 16);
      expect(chunks.join(), _mixed);
    });

    test('overlap repeats context instead of dropping it', () {
      final plain = tk.chunkByTokens(_mixed, 16);
      final overlapped = tk.chunkByTokens(_mixed, 16, overlapTokens: 4);
      expect(overlapped.length, greaterThan(plain.length));
      // Still bounded: overlap must not push a chunk over the budget.
      for (final chunk in overlapped) {
        expect(tk.encode(chunk).length, lessThanOrEqualTo(16));
      }
      // Content is repeated, so the pieces together are longer than the input.
      expect(overlapped.join().length, greaterThan(_mixed.length));
    });

    test('a short text is one chunk', () {
      final chunks = tk.chunkByTokens('hello world', 100);
      expect(chunks, ['hello world']);
    });

    test('empty text gives no chunks', () {
      expect(tk.chunkByTokens('', 10), isEmpty);
    });

    test('non-ASCII chunks decode cleanly', () {
      const turkish = 'Ölçüm yapmadan iddia etme. Şeftali, ığdır, çğüöşi. 🍰🍰🍰';
      for (final chunk in tk.chunkByTokens(turkish, 4)) {
        // A cut inside a multi-byte character would have thrown on decode.
        expect(utf8.decode(utf8.encode(chunk)), chunk);
      }
      expect(tk.chunkByTokens(turkish, 4).join(), turkish);
    });

    test('bad arguments are rejected', () {
      expect(() => tk.chunkByTokens(_mixed, 0), throwsArgumentError);
      expect(
        () => tk.chunkByTokens(_mixed, 10, overlapTokens: -1),
        throwsArgumentError,
      );
      // An overlap that never advances would loop forever.
      expect(
        () => tk.chunkByTokens(_mixed, 10, overlapTokens: 10),
        throwsArgumentError,
      );
    });

    test('every piece really fits the budget when re-encoded', () {
      // Counting spans in the whole text is not enough, because tokenization
      // is context-dependent: cutting inside `internationalization` used to
      // hand back a piece that led with `##ization` and re-encoded to two
      // tokens where the count assumed one, putting the piece over budget.
      const wordy =
          'tokenization internationalization antidisestablishmentarianism';
      for (final text in [_mixed, wordy]) {
        for (var budget = 8; budget <= 40; budget++) {
          for (final overlap in [0, 1, 3]) {
            for (final chunk in tk.chunkByTokens(
              text,
              budget,
              overlapTokens: overlap,
            )) {
              expect(
                tk.encode(chunk).length,
                lessThanOrEqualTo(budget),
                reason: 'budget $budget overlap $overlap: '
                    '${jsonEncode(chunk)}',
              );
            }
          }
        }
      }
    });

    test('an overlap that only special tokens make too large is rejected', () {
      // BERT adds two, so a budget of 10 leaves 8 for text. An overlap of 8 or
      // 9 is under maxTokens and passes the cheap check, but leaves a step of
      // 0 or -1: the first looped forever, the second walked off the front of
      // the token list.
      expect(
        () => tk.chunkByTokens(_mixed, 10, overlapTokens: 8),
        throwsArgumentError,
      );
      expect(
        () => tk.chunkByTokens(_mixed, 10, overlapTokens: 9),
        throwsArgumentError,
      );
      // One below the real room still works.
      expect(tk.chunkByTokens(_mixed, 10, overlapTokens: 7), isNotEmpty);
    });

    test('a budget with no room left after special tokens is rejected', () {
      // BERT adds two, so a budget of 2 leaves nothing for text.
      expect(() => tk.chunkByTokens(_mixed, 2), throwsArgumentError);
    });
  });
}
