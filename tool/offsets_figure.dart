// Draws the offsets picture on the README: one sentence, and every token span
// the tokenizer returned read twice, once as the UTF-8 byte range it is and
// once as if it were a range of Dart string indices.
//
// Every index, slice and count in the drawing is measured here at run time,
// from test/fixtures/bert-base-uncased.json through the package's own
// `encodeWithOffsets`. Nothing is typed in by hand. The wrong column is
// produced by really calling `String.substring` with the byte offsets and
// keeping whatever comes back, including the throw.
//
// The generator refuses to write the file when the measurement stops saying
// what the caption says: an all-ASCII sentence, a first span that already
// disagrees, or no disagreement at all would each make the picture a claim the
// run did not support.
//
//   dart run tool/offsets_figure.dart
//
// Writes doc/offsets.svg, then rasterises it to doc/offsets.png when a
// converter is on PATH, the same way tool/parity_shot.dart does. pub.dev serves
// `screenshots:` out of the published archive and takes raster images only,
// which is why the PNG is the committed artifact and the SVG is its source.

import 'dart:convert';
import 'dart:io';

import 'package:hf_tokenizers/hf_tokenizers.dart';

const _fixture = 'test/fixtures/bert-base-uncased.json';

/// The sentence in the picture, the same one tool/parity_shot.dart uses. Its
/// three two-byte characters sit far apart, so the gap between the two indexes
/// opens more than once rather than reading as a single off-by-one.
const _text = 'The naïve café in São Paulo';

// GitHub's palette, the same one doc/parity.svg draws with.
const _ink = '#0d1117';
const _body = '#24292f';
const _muted = '#57606a';
const _faint = '#8c959f';
const _rule = '#d0d7de';
const _blueFill = '#ddf4ff';
const _blueLine = '#54aeff';
const _green = '#1a7f37';
const _red = '#cf222e';
const _redFill = '#ffebe9';
const _greyFill = '#f6f8fa';

const _w = 900.0;
const _h = 756.0;
const _left = 56.0;

/// Where the character ruler starts, leaving room for the row labels.
const _strip = 176.0;

/// Monospace advance width as a fraction of the font size. Menlo, SF Mono and
/// DejaVu Sans Mono agree on 0.60 within a rounding error, and the layout needs
/// box widths rather than kerning.
const _adv = 0.60;

/// One token: the span the tokenizer reported, and the text each of the two
/// ways of reading that span hands back.
typedef _Row = ({
  String token,
  int start,
  int end,
  String good,
  String bad,
  bool threw,
  bool agrees,
});

void main() {
  // The ruler draws one cell per UTF-16 code unit because that is the index
  // `substring` takes. A surrogate pair would put two cells under one glyph.
  for (var i = 0; i < _text.length; i++) {
    final u = _text.codeUnitAt(i);
    if (u >= 0xd800 && u <= 0xdfff) {
      throw StateError(
        '"$_text" has a surrogate pair at index $i, and the ruler here draws '
        'one cell per UTF-16 code unit. Pick a sentence inside the basic '
        'multilingual plane, or teach the ruler to span cells.',
      );
    }
  }

  final units = _text.split('');
  final bytes = utf8.encode(_text);

  // Byte offset of every UTF-16 index, built one character at a time. The two
  // rulers in the picture are this list and its own indices.
  final byteAt = <int>[0];
  for (final u in units) {
    byteAt.add(byteAt.last + utf8.encode(u).length);
  }
  if (byteAt.last != bytes.length) {
    throw StateError(
      'the per-character widths sum to ${byteAt.last} bytes and the encoded '
      'string is ${bytes.length}, so the ruler would be drawn from a '
      'different measurement than the spans are read against.',
    );
  }

  final tk = Tokenizer.fromFile(_fixture);
  final rows = <_Row>[
    for (final s in tk.encodeWithOffsets(_text, addSpecialTokens: false))
      _read(s, bytes, tk.idToToken(s.id)!),
  ];
  tk.close();

  if (bytes.length == _text.length) {
    stderr.writeln(
      'every character in "$_text" is a single byte, so the two indexes '
      'cannot come apart and the figure would show nothing',
    );
    exitCode = 1;
    return;
  }
  if (rows.isEmpty || !rows.first.agrees) {
    stderr.writeln(
      'the caption says the two readings agree while the text is ASCII, and '
      'the first span disagrees already',
    );
    exitCode = 1;
    return;
  }
  final wrong = rows.where((r) => !r.agrees).length;
  if (wrong == 0) {
    stderr.writeln(
      'every span reads the same text both ways, so there is no drift to draw',
    );
    exitCode = 1;
    return;
  }

  final wide = units.where((u) => utf8.encode(u).length > 1).length;
  final svg = _draw(rows, units, byteAt, wide: wide, wrong: wrong);
  Directory('doc').createSync(recursive: true);
  File('doc/offsets.svg').writeAsStringSync(svg);
  stdout.writeln(
    'wrote doc/offsets.svg (${svg.length} bytes): ${_text.length} UTF-16 '
    'units, ${bytes.length} bytes, $wide of them two-byte characters',
  );
  for (final r in rows) {
    stdout.writeln(
      '  ${r.token.padRight(7)} [${r.start}, ${r.end})'.padRight(22) +
          'utf8 "${r.good}"'.padRight(18) +
          (r.threw ? 'substring threw RangeError' : 'substring "${r.bad}"'),
    );
  }
  stdout.writeln('$wrong of ${rows.length} spans read different text');
  _rasterise('doc/offsets.svg', 'doc/offsets.png');
}

/// Reads one span both ways and keeps whatever each way produced.
_Row _read(TokenOffset s, List<int> bytes, String token) {
  final good = utf8.decode(bytes.sublist(s.start, s.end));
  String bad;
  var threw = false;
  try {
    bad = _text.substring(s.start, s.end);
  } on RangeError {
    bad = 'RangeError';
    threw = true;
  }
  return (
    token: token,
    start: s.start,
    end: s.end,
    good: good,
    bad: bad,
    threw: threw,
    agrees: !threw && bad == good,
  );
}

String _draw(
  List<_Row> rows,
  List<String> units,
  List<int> byteAt, {
  required int wide,
  required int wrong,
}) {
  final cellW = (_w - _left - _strip) / units.length;
  final glyph = cellW * 0.78;

  final b = StringBuffer()
    ..writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" width="${_w.toInt()}" '
      'height="${_h.toInt()}" viewBox="0 0 ${_w.toInt()} ${_h.toInt()}" '
      'font-family="ui-sans-serif, -apple-system, Segoe UI, Roboto, Helvetica, '
      'Arial, sans-serif">',
    )
    ..writeln(
      '<style>'
      '.m{font-family:ui-monospace,SFMono-Regular,Menlo,DejaVu Sans Mono,'
      'monospace}'
      '.cap{font-size:13.5px;font-weight:700;letter-spacing:.09em}'
      '.lbl{font-size:12.5px;fill:$_muted;text-anchor:end}'
      '.ix{font-size:10.5px;text-anchor:middle}'
      '.note{font-size:16.5px;fill:$_body}'
      '.tiny{font-size:12.5px;fill:$_faint}'
      '</style>',
    )
    // Screenshots render on both pub.dev themes, so the card is painted rather
    // than left transparent.
    ..writeln(
      '<rect x="1" y="1" width="${_w - 2}" height="${_h - 2}" rx="18" '
      'fill="#ffffff" stroke="$_rule"/>',
    );

  void rule(double y) => b.writeln(
    '<line x1="$_left" y1="$y" x2="${_w - _left}" y2="$y" stroke="$_rule"/>',
  );

  void cap(double y, String s, String fill, {double x = _left}) => b.writeln(
    '<text class="cap" x="$x" y="$y" fill="$fill">${_esc(s)}</text>',
  );

  void label(double y, String s) => b.writeln(
    '<text class="lbl" x="${_strip - 16}" y="$y">${_esc(s)}</text>',
  );

  // ---- the two rulers -----------------------------------------------------
  cap(50, 'ONE STRING, TWO WAYS TO COUNT IT', _muted);
  b.writeln(
    '<text class="tiny" x="${_w - _left}" y="50" text-anchor="end">'
    '$wide characters take two bytes</text>',
  );

  const ixY = 98.0;
  const cellY = 108.0;
  const cellH = 42.0;
  const byteY = 170.0;

  label(ixY, 'string index');
  label(cellY + 28, 'the text');
  label(byteY, 'byte offset');

  for (var i = 0; i < units.length; i++) {
    final x = _strip + i * cellW;
    final mid = x + cellW / 2;
    final two = byteAt[i + 1] - byteAt[i] > 1;
    final drifted = byteAt[i] != i;
    b
      ..writeln('<text class="ix" x="$mid" y="$ixY" fill="$_muted">$i</text>')
      ..writeln(
        '<rect x="${x + 1}" y="$cellY" width="${cellW - 2}" height="$cellH" '
        'rx="4" fill="${two ? _redFill : _greyFill}" '
        'stroke="${two ? '#ffcecb' : _rule}"/>',
      )
      ..writeln(
        '<text class="m" x="$mid" y="${cellY + 28}" text-anchor="middle" '
        'font-size="${glyph.toStringAsFixed(1)}px" '
        'fill="${two ? _red : _ink}"${two ? ' font-weight="700"' : ''}>'
        '${_esc(units[i])}</text>',
      )
      ..writeln(
        '<text class="ix" x="$mid" y="$byteY" '
        'fill="${drifted ? _red : _muted}"'
        '${drifted ? ' font-weight="700"' : ''}>${byteAt[i]}</text>',
      );
  }

  final ahead = byteAt.last - _text.length;
  b.writeln(
    '<text class="note" x="$_strip" y="202">'
    '<tspan class="m" font-size="15px">text.length</tspan> is '
    '<tspan font-weight="700">${_text.length}</tspan>, '
    '<tspan class="m" font-size="15px">utf8.encode(text).length</tspan> is '
    '<tspan font-weight="700">${byteAt.last}</tspan>, and the byte offset '
    'ends <tspan font-weight="700" fill="$_red">$ahead ahead</tspan></text>',
  );
  rule(228);

  // ---- every span, read both ways ----------------------------------------
  cap(262, 'EVERY SPAN THE TOKENIZER RETURNED, READ BOTH WAYS', _muted);
  b.writeln(
    '<text class="tiny" x="$_left" y="280">the token is what the normalizer '
    'produced, and the span points back into the original text</text>',
  );

  const colSpan = 196.0;
  const colGood = 310.0;
  const colBad = 606.0;
  const colMark = _w - _left - 4;

  cap(308, 'TOKEN', _muted);
  cap(308, 'SPAN', _muted, x: colSpan);
  cap(308, 'AS UTF-8 BYTES', _green, x: colGood);
  cap(308, 'AS STRING INDICES', _red, x: colBad);
  b
    ..writeln(
      '<text class="tiny m" x="$colGood" y="324">'
      'utf8.decode(bytes.sublist(s, e))</text>',
    )
    ..writeln(
      '<text class="tiny m" x="$colBad" y="324">text.substring(s, e)</text>',
    );

  const rowY = 336.0;
  const rowH = 42.0;
  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    final y = rowY + i * rowH;
    final base = y + 27;
    final chipW = r.token.length * 15 * _adv + 22;
    b
      ..writeln(
        '<rect x="$_left" y="$y" width="${_w - 2 * _left}" '
        'height="${rowH - 6}" rx="7" '
        'fill="${r.agrees ? _greyFill : '#fff8f7'}" '
        'stroke="${r.agrees ? _rule : '#ffcecb'}"/>',
      )
      ..writeln(
        '<rect x="${_left + 12}" y="${y + 7}" width="$chipW" height="23" '
        'rx="5" fill="$_blueFill" stroke="$_blueLine"/>',
      )
      ..writeln(
        '<text class="m" x="${_left + 12 + chipW / 2}" y="${y + 24}" '
        'text-anchor="middle" font-size="15px" fill="$_ink">'
        '${_esc(r.token)}</text>',
      )
      ..writeln(
        '<text class="m" x="$colSpan" y="$base" font-size="15px" '
        'fill="$_muted">[${r.start}, ${r.end})</text>',
      )
      ..writeln(
        '<text class="m" x="$colGood" y="$base" font-size="16px" '
        'fill="$_ink">"${_esc(r.good)}"</text>',
      )
      ..writeln(
        '<text class="m" x="$colBad" y="$base" font-size="16px" '
        'fill="${r.agrees ? _ink : _red}"'
        '${r.threw ? ' font-weight="700"' : ''}>'
        '${r.threw ? 'throws RangeError' : '"${_esc(r.bad)}"'}</text>',
      )
      ..writeln(
        '<text x="$colMark" y="$base" text-anchor="end" font-size="17px" '
        'fill="${r.agrees ? _green : _red}">${r.agrees ? '✓' : '✗'}</text>',
      );
  }

  // A row of agreement at the top and disagreement below it is the whole
  // lesson, so name it rather than leaving the reader to count.
  final last = rows.last;
  final end = rowY + rows.length * rowH;
  rule(end + 22);
  void note(double y, String markup) =>
      b.writeln('<text class="note" x="$_left" y="$y">$markup</text>');
  note(end + 54, 'Both columns are right while the text is ASCII.');
  note(
    end + 80,
    'From the first two-byte character on, <tspan font-weight="700" '
    'fill="$_red">$wrong of ${rows.length}</tspan> spans name different text.',
  );
  if (last.threw) {
    note(
      end + 106,
      'The last one ends at byte <tspan font-weight="700">${last.end}</tspan> '
      'in a string of length <tspan font-weight="700">${_text.length}</tspan>, '
      'and it is the only one that fails loudly.',
    );
  }
  b
    ..writeln(
      '<text class="tiny m" x="$_left" y="${_h - 30}">'
      'tool/offsets_figure.dart · $_fixture</text>',
    )
    ..writeln('</svg>');
  return b.toString();
}

/// Renders the SVG to PNG with whichever converter is installed, then reduces
/// it to a 64-colour palette.
///
/// Prints the commands instead of failing when nothing is installed: the SVG is
/// the source of truth and the PNG is a build product of it. The palette step
/// matters because this file ships inside the published archive as a
/// `screenshots:` entry, where every byte is a byte every consumer downloads.
void _rasterise(String svg, String png) {
  const tries = <(String, List<String>)>[
    ('rsvg-convert', ['-w', '1600']),
    ('magick', []),
  ];
  for (final (exe, extra) in tries) {
    final args = exe == 'rsvg-convert'
        ? [...extra, '-o', png, svg]
        : [svg, '-resize', '1600x', png];
    final ProcessResult r;
    try {
      r = Process.runSync(exe, args);
    } on ProcessException {
      continue; // not installed
    }
    if (r.exitCode != 0) {
      stderr.writeln('$exe exited ${r.exitCode}: ${r.stderr}');
      continue;
    }
    final raw = File(png).lengthSync();
    stdout.writeln('rendered $png ($raw bytes) with $exe');
    _palettise(png, raw);
    return;
  }
  stdout.writeln(
    'no rasteriser on PATH. Refresh $png with:\n'
    '  rsvg-convert -w 1600 $svg -o $png',
  );
}

/// Reduces [png] to a 64-colour palette in place, keeping the larger file if
/// the conversion is unavailable or turns out not to help.
void _palettise(String png, int before) {
  final tmp = '$png.tmp';
  for (final exe in ['magick', 'convert']) {
    final ProcessResult r;
    try {
      // Dithering is what makes this expensive: the fills here are flat, and
      // scattering pixels through them to fake missing shades costs size and
      // shows up as speckle behind the table rows.
      r = Process.runSync(exe, [
        png,
        '-dither',
        'None',
        '-colors',
        '64',
        '-strip',
        '-define',
        'png:compression-level=9',
        tmp,
      ]);
    } on ProcessException {
      continue;
    }
    if (r.exitCode != 0) {
      stderr.writeln('$exe -colors exited ${r.exitCode}: ${r.stderr}');
      continue;
    }
    final after = File(tmp).lengthSync();
    if (after < before) {
      File(tmp).renameSync(png);
      stdout.writeln(
        'palettised $png to $after bytes '
        '(${(100 * (before - after) / before).round()}% smaller)',
      );
    } else {
      File(tmp).deleteSync();
      stdout.writeln('palette was not smaller; kept $before bytes');
    }
    return;
  }
  if (File(tmp).existsSync()) File(tmp).deleteSync();
  stdout.writeln('no palette tool on PATH; $png stays at $before bytes');
}

String _esc(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
