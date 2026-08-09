# Examples

Three programs, all running against the `bert-base-uncased` fixture committed in
this repository. They work from a checkout with nothing to download. Point them
at the `tokenizer.json` that ships with the model you actually call and the
numbers become yours.

## Spending a context budget

```
dart run example/context_budget.dart [path/to/tokenizer.json]
```

Going over a model's token budget is a rejected request or a silently truncated
answer, never a warning. `context_budget.dart` runs the three things that budget
needs and checks its own work:

```
encode("hello world") -> [101, 7592, 2088, 102]
byte-exact with the reference implementation: yes

a 285-character prompt
  chars / 4 says   72 tokens
  the tokenizer says 78 tokens
  the shortcut is 8% under, and under is the direction that overflows

truncateToTokens(prompt, 40)
  kept 162 characters, which re-encode to 40 tokens (fits)
  ...nd the timestamps. Drop the pleasantries. If the

chunkByTokens(prompt, 24, overlapTokens: 6) -> 5 pieces
  1. [24 tok] Summarise the following support thread for an engineer on call. Keep the customer's account id, the
  2. [24 tok] 's account id, the error codes, and the timestamps. Drop the pleasantries. If the
  3. [24 tok] the pleasantries. If the thread contains a stack trace, keep only the top frame: NoSuchMetho
  4. [24 tok] frame: NoSuchMethodError: 'call' on null at package:acme/sync.
  5. [14 tok] :acme/sync.dart:412:9.

pieces over the 24-token budget: 0
```

Three things in that output are the point.

**The shortcut is wrong in the dangerous direction.** A quarter of a token per
character is the rule of thumb everyone reaches for, and on this prompt it
undercounts by 8%. The error is not a constant: prose, code, identifiers and
punctuation tokenize at different rates, and the same shortcut over-counts other
text. Undercounting is what gets a request rejected in production.

**Truncation is verified.** The example re-encodes the result and prints the
count, which makes `(fits)` a measurement rather than a promise. The cut lands
on a token boundary, which is always a UTF-8 boundary and never halves a
character. The `[CLS]`/`[SEP]` the model adds come off the budget up front
rather than pushing the result one token over.

**Overlap is visible.** Piece 2 begins with `'s account id, the`, which is the
tail of piece 1. A sentence cut across a seam stays retrievable from either
side, and that is the reason to pay for the repetition.

## Why the last line of that output is not free

`chunkByTokens` re-encodes every piece before handing it back. Counting the
spans it already has would be faster and wrong:

```dart
final spans = tk.encodeWithOffsets(document, addSpecialTokens: false);
// spans.length is the count for the whole document. Cut between two of them
// and the pieces can cost more than the spans they were sliced from.
```

![One word tokenized as two pieces, and the same bytes re-encoded as three once a chunk boundary falls between them.](https://raw.githubusercontent.com/Yusufihsangorgel/tokenizers/main/doc/token_split.png)

Tokenization is context-dependent. `internationalization` is two tokens whole.
Cut it at that boundary and the trailing piece re-encodes as two of its own, for
three in total. One extra token per seam is enough to push a chunk over an
embedding endpoint's limit, which is why the last line of the output above
prints a count taken after the cut. `tool/generate_split_diagram.dart` draws the
diagram from the tokenizer at run time, so the numbers in it cannot drift.

## The primitives

```
dart run example/hf_tokenizers_example.dart
```

Byte-exact encode and decode, and `encodeWithOffsets`, which returns each
token's id together with its byte span in the original string. `chunkByTokens`
is built on it. Use it directly when you need a window rule of your own, for
instance breaking on sentence boundaries that happen to fit the budget.

## Chunking for retrieval

```
dart run example/rag_chunking.dart
```

A `Chunker` for [`rag_kit`](https://pub.dev/packages/rag_kit) built on
`encodeWithOffsets`, carrying both an exact token count and a real range back
into the source document. The interesting part is the unit conversion:
`TokenOffset` is in UTF-8 bytes, `rag_kit`'s `Chunk` promises
`source.substring(start, end) == text` in UTF-16, and the two agree on ASCII and
nowhere else. The example asserts that contract rather than describing it.

## Why byte-exact matters

A tokenizer that is approximately right gives you counts that are approximately
right, and a context budget does not degrade gracefully: it is fine until the
request is refused. These encodes produce the same ids as the reference
implementation for the same `tokenizer.json`, which makes a count taken here the
count the model will take.

That is also why the ids are checked in the example itself rather than described
in prose. If they ever drifted, every budget on this page would be quietly
wrong.
