# Examples

Both run against the BERT fixture in this repository, so they work from a
checkout with no download. Point them at the `tokenizer.json` that ships with
the model you actually call and the numbers become yours.

## Spending a context budget

```
dart run example/context_budget.dart [path/to/tokenizer.json]
```

Going over a model's token budget is not a warning, it is a rejected request or
a silently truncated answer. `context_budget.dart` runs the three things that
budget needs and checks its own work:

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
punctuation tokenize at different rates, so the same shortcut over-counts other
text. Undercounting is what gets a request rejected in production.

**Truncation is verified, not asserted.** The example re-encodes the result and
prints the count, so `(fits)` is a measurement. The cut lands on a token
boundary, which is always a UTF-8 boundary, so no character is halved, and the
`[CLS]`/`[SEP]` the model adds are taken off the budget up front rather than
pushing the result one token over.

**Overlap is visible.** Piece 2 begins with `'s account id, the`, which is the
tail of piece 1. A sentence cut across a seam stays retrievable from either
side, which is the reason to pay for the repetition.

## The primitives

```
dart run example/hf_tokenizers_example.dart
```

Byte-exact encode and decode, and `encodeWithOffsets`, which returns each
token's id together with its byte span in the original string. `chunkByTokens`
is built on it. Use it directly when you need a window rule of your own, for
instance breaking on sentence boundaries that happen to fit the budget.

## Why byte-exact matters

A tokenizer that is approximately right gives you counts that are approximately
right, and a context budget does not degrade gracefully: it is fine until the
request is refused. These encodes produce the same ids as the reference
implementation for the same `tokenizer.json`, so a count taken here is the count
the model will take.

That is also why the ids are checked in the example itself rather than described
in prose. If they ever drifted, every budget on the page would be quietly wrong.
