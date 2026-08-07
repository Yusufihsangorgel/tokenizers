// Draws the diagram used in the chunking write-up: one word, its tokens, and
// what those same bytes cost once a chunk boundary falls between them.
//
// Every number and label in the output comes from the tokenizer at run time —
// nothing here is typed in by hand, so the picture cannot drift away from what
// the package actually does.
//
//   dart run tool/generate_split_diagram.dart
//
// Writes doc/token_split.svg. It writes the file rather than printing it
// because the build hooks announce themselves on stdout, and a redirect picks
// that up along with the SVG.

import 'dart:convert';
import 'dart:io';

import 'package:hf_tokenizers/hf_tokenizers.dart';

const _word = 'internationalization';
const _fixture = 'test/fixtures/bert-base-uncased.json';

void main() {
  final tk = Tokenizer.fromFile(_fixture);
  final bytes = utf8.encode(_word);
  final spans = tk.encodeWithOffsets(_word, addSpecialTokens: false);

  // Whole word: one box per token, as the tokenizer segments it.
  final whole = [
    for (final s in spans)
      (text: tk.idToToken(s.id)!, start: s.start, end: s.end),
  ];

  // Same bytes, cut at every token boundary, each piece re-encoded alone.
  final pieces = <({String slice, List<String> tokens})>[
    for (final s in spans)
      (
        slice: utf8.decode(bytes.sublist(s.start, s.end)),
        tokens: [
          for (final id in tk.encode(
            utf8.decode(bytes.sublist(s.start, s.end)),
            addSpecialTokens: false,
          ))
            tk.idToToken(id)!,
        ],
      ),
  ];
  tk.close();

  final after = pieces.fold<int>(0, (n, p) => n + p.tokens.length);
  final svg = _svg(whole, pieces, before: whole.length, after: after);
  final out = File('doc/token_split.svg')..parent.createSync(recursive: true);
  out.writeAsStringSync(svg);
  stdout.writeln(
    'wrote ${out.path} (${svg.length} bytes): '
    '${whole.length} tokens whole, $after in pieces',
  );
}

String _svg(
  List<({String text, int start, int end})> whole,
  List<({String slice, List<String> tokens})> pieces, {
  required int before,
  required int after,
}) {
  const w = 720.0, unit = 26.0, left = 40.0;
  final b = StringBuffer()
    ..writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" width="$w" height="300" '
      'viewBox="0 0 $w 300" font-family="ui-monospace, SFMono-Regular, '
      'Menlo, monospace">',
    )
    ..writeln(
      '<style>'
      '.lbl{font:600 13px ui-sans-serif,system-ui,sans-serif;fill:#57606a}'
      '.cnt{font:700 15px ui-sans-serif,system-ui,sans-serif}'
      '.tok{font:600 13px ui-monospace,monospace;fill:#0d1117}'
      '.box{fill:#ddf4ff;stroke:#54aeff;stroke-width:1.5;rx:5}'
      '.box2{fill:#fff1e5;stroke:#fb8f44;stroke-width:1.5;rx:5}'
      '.cut{stroke:#cf222e;stroke-width:2;stroke-dasharray:5 4}'
      '@media(prefers-color-scheme:dark){'
      '.lbl{fill:#8b949e}.tok{fill:#0d1117}}'
      '</style>',
    );

  void row(
    double y,
    List<({String text, double x, double w, bool hot})> boxes,
  ) {
    for (final t in boxes) {
      b
        ..writeln(
          '<rect class="${t.hot ? "box2" : "box"}" x="${t.x}" y="$y" '
          'width="${t.w}" height="34" rx="5"/>',
        )
        ..writeln(
          '<text class="tok" x="${t.x + t.w / 2}" y="${y + 22}" '
          'text-anchor="middle">${_esc(t.text)}</text>',
        );
    }
  }

  // Row 1 — the word as the tokenizer sees it.
  b.writeln('<text class="lbl" x="$left" y="34">one word, tokenized</text>');
  var x = left;
  final top = <({String text, double x, double w, bool hot})>[];
  for (final t in whole) {
    final width = (t.end - t.start) * unit;
    top.add((text: t.text, x: x, w: width, hot: false));
    x += width;
  }
  row(48, top);
  b
    ..writeln(
      '<text class="cnt" x="${w - 40}" y="70" text-anchor="end" '
      'fill="#1a7f37">$before tokens</text>',
    )
    // the cut
    ..writeln(
      '<line class="cut" x1="${left + whole.first.end * unit}" y1="40" '
      'x2="${left + whole.first.end * unit}" y2="180"/>',
    )
    ..writeln(
      '<text class="lbl" x="${left + whole.first.end * unit + 8}" '
      'y="118" fill="#cf222e">chunk boundary</text>',
    )
    ..writeln(
      '<text class="lbl" x="$left" y="172">'
      'same bytes, each piece encoded on its own</text>',
    );

  // Row 2 — the pieces, re-encoded.
  x = left;
  final boxes = <({String text, double x, double w, bool hot})>[];
  for (final p in pieces) {
    final span = p.slice.length * unit;
    final each = span / p.tokens.length;
    for (final t in p.tokens) {
      boxes.add((text: t, x: x, w: each - 3, hot: p.tokens.length > 1));
      x += each;
    }
    x += 10;
  }
  row(186, boxes);
  b
    ..writeln(
      '<text class="cnt" x="${w - 40}" y="208" text-anchor="end" '
      'fill="#cf222e">$after tokens</text>',
    )
    ..writeln(
      '<text class="lbl" x="$left" y="262">'
      'The count you measured on the whole string is not a budget for its '
      'pieces.</text>',
    )
    ..writeln('</svg>');
  return b.toString();
}

String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;');
