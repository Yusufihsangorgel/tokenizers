// Draws the byte-exactness picture on the README: one sentence tokenized by
// this package, and the same sentence run through the shortest reimplementation
// that looks correct (lowercase the text, then look each word up in the same
// vocabulary).
//
// Every token, id and count in the output is computed here at run time from
// test/fixtures/bert-base-uncased.json, the file HuggingFace ships. Nothing is
// typed in by hand, so the picture cannot drift away from what the package
// does. The ids on the hf_tokenizers row are checked a second time against the
// vocabulary table parsed straight out of that JSON, rather than trusting the
// library to agree with itself.
//
//   dart run tool/parity_shot.dart
//
// Writes doc/parity.svg, then rasterises it to doc/parity.png when a converter
// is on PATH. pub.dev serves `screenshots:` out of the published archive and
// takes raster images only, which is why the PNG is the committed artifact and
// the SVG is its source. Both files are written rather than printed: the build
// hooks announce themselves on stdout and a redirect would capture that too.

import 'dart:convert';
import 'dart:io';

import 'package:hf_tokenizers/hf_tokenizers.dart';

const _fixture = 'test/fixtures/bert-base-uncased.json';

/// The sentence in the picture. Three different accented characters, so the
/// point cannot be read as one lucky special case, and every word is in the
/// vocabulary once the normalizer has run.
const _text = 'The naïve café in São Paulo';

// GitHub's palette, the same one doc/token_split.svg draws with.
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
const _h = 900.0;
const _left = 56.0;

/// Monospace advance width as a fraction of the font size. Menlo, SF Mono and
/// DejaVu Sans Mono agree on 0.60 within a rounding error, and the layout needs
/// box widths rather than kerning.
const _adv = 0.60;

/// One column of the picture: what the package produced, and what the shortcut
/// produced, for the same word.
typedef _Col = ({String word, String token, int id, int naiveId, bool missed});

void main() {
  final json = jsonDecode(File(_fixture).readAsStringSync());
  final model = (json as Map<String, dynamic>)['model'] as Map<String, dynamic>;
  final vocab = model['vocab'] as Map<String, dynamic>;
  final unkId = vocab[model['unk_token']] as int;

  final tk = Tokenizer.fromFile(_fixture);
  final ids = tk.encode(_text, addSpecialTokens: false);
  final tokens = [for (final id in ids) tk.idToToken(id)!];
  final vocabSize = tk.vocabSize;
  tk.close();

  final words = _text.split(' ');

  // The rows are drawn as aligned columns, which is only honest while each word
  // produces exactly one token. Fail loudly rather than draw a picture that
  // quietly misaligns if the sentence or the vocabulary ever changes.
  if (words.length != tokens.length) {
    throw StateError(
      '"$_text" is ${words.length} words but ${tokens.length} tokens, and the '
      'column layout here assumes one token per word. Pick another sentence, '
      'or teach the layout to span columns.',
    );
  }

  // Independent check on the top row: every id the library returned has to be
  // the id this vocabulary gives the token string it reported. Reading the JSON
  // here verifies the row against the shipped file instead of against the same
  // call that produced it.
  for (var i = 0; i < ids.length; i++) {
    final fromFile = vocab[tokens[i]];
    if (fromFile != ids[i]) {
      throw StateError(
        'id ${ids[i]} for "${tokens[i]}" is not the id $_fixture assigns '
        '($fromFile)',
      );
    }
  }

  // The shortcut: lowercase, then look the whole word up. With no normalizer an
  // accented character misses even though the word is in the vocabulary under
  // its unaccented spelling.
  final cols = <_Col>[
    for (var i = 0; i < words.length; i++)
      (
        word: words[i].toLowerCase(),
        token: tokens[i],
        id: ids[i],
        naiveId: (vocab[words[i].toLowerCase()] as int?) ?? unkId,
        missed: vocab[words[i].toLowerCase()] == null,
      ),
  ];
  final lost = cols.where((c) => c.missed).length;

  final svg = _draw(cols, lost: lost, unkId: unkId, vocabSize: vocabSize);
  Directory('doc').createSync(recursive: true);
  File('doc/parity.svg').writeAsStringSync(svg);
  stdout.writeln(
    'wrote doc/parity.svg (${svg.length} bytes): ${cols.length} tokens, '
    '$lost of ${cols.length} words lost to [UNK] without the normalizer',
  );
  _rasterise('doc/parity.svg', 'doc/parity.png');
}

/// Renders the SVG to PNG with whichever converter is installed, then puts the
/// result on a palette.
///
/// Prints the command instead of failing when nothing is installed: the SVG is
/// the source of truth and the PNG is a build product of it. The palette step
/// matters because this file ships inside the published archive as a
/// `screenshots:` entry, where every byte is a byte every consumer downloads.
/// Flat fills and antialiased text quantise to 64 colours without a visible
/// difference, and that is roughly a quarter of the size.
void _rasterise(String svg, String png) {
  final tries = <(String, List<String>)>[
    ('rsvg-convert', ['-w', '900', '-h', '900', '-o', png, svg]),
    ('magick', [svg, '-resize', '900x900', png]),
    ('convert', [svg, '-resize', '900x900', png]),
  ];
  for (final (exe, args) in tries) {
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
    'no rasteriser on PATH. Refresh $png with either of:\n'
    '  rsvg-convert -w 900 -h 900 -o $png $svg\n'
    '  magick $svg -resize 900x900 $png',
  );
}

/// Reduces [png] to a 64-colour palette in place, keeping the larger file if
/// the conversion is unavailable or turns out not to help.
void _palettise(String png, int before) {
  final tmp = '$png.tmp';
  for (final exe in ['magick', 'convert']) {
    final ProcessResult r;
    try {
      r = Process.runSync(exe, [
        png,
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

String _draw(
  List<_Col> cols, {
  required int lost,
  required int unkId,
  required int vocabSize,
}) {
  const boxFont = 23.0;
  const idFont = 20.0;
  const padChars = 1.8; // characters of breathing room inside a box
  const gap = 11.0;
  const boxH = 52.0;

  // One column per word, wide enough for whichever row holds the longer string.
  final colW = [
    for (final c in cols)
      (c.word.length > c.token.length ? c.word.length : c.token.length) *
              boxFont *
              _adv +
          padChars * boxFont * _adv,
  ];
  final colX = <double>[];
  var x = _left;
  for (final w in colW) {
    colX.add(x);
    x += w + gap;
  }

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
      '.sub{font-size:16px;fill:$_muted}'
      '.tok{font-size:${boxFont}px}'
      '.id{font-size:${idFont}px;font-weight:700}'
      '.note{font-size:17.5px;fill:$_body}'
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

  void caption(double y, String s, String fill) => b.writeln(
    '<text class="cap" x="$_left" y="$y" fill="$fill">${_esc(s)}</text>',
  );

  void sub(double y, double dx, String s) =>
      b.writeln('<text class="sub" x="${_left + dx}" y="$y">${_esc(s)}</text>');

  void note(double y, String markup, {String fill = _body}) => b.writeln(
    '<text class="note" x="$_left" y="$y" fill="$fill">$markup'
    '</text>',
  );

  // ---- the input ---------------------------------------------------------
  caption(52, 'INPUT', _muted);
  const inFont = 27.0;
  var ix = _left;
  for (final ch in _text.split('')) {
    final accented = ch.codeUnitAt(0) > 127;
    b.writeln(
      '<text class="m" x="$ix" y="96" font-size="${inFont}px" '
      'fill="${accented ? _red : _ink}"'
      '${accented ? ' font-weight="700"' : ''}>${_esc(ch)}</text>',
    );
    ix += inFont * _adv;
  }
  b.writeln(
    '<text class="tiny" x="${_w - _left}" y="96" text-anchor="end">'
    'three accented characters</text>',
  );
  rule(130);

  // ---- row A: this package -----------------------------------------------
  caption(178, 'HF_TOKENIZERS', _green);
  sub(178, 152, 'encode(text, addSpecialTokens: false)');
  const aY = 198.0;
  for (var i = 0; i < cols.length; i++) {
    b
      ..writeln(
        '<rect x="${colX[i]}" y="$aY" width="${colW[i]}" height="$boxH" rx="7" '
        'fill="$_blueFill" stroke="$_blueLine"/>',
      )
      ..writeln(
        '<text class="m tok" x="${colX[i] + colW[i] / 2}" y="${aY + 34}" '
        'text-anchor="middle" fill="$_ink">${_esc(cols[i].token)}</text>',
      )
      ..writeln(
        '<text class="m id" x="${colX[i] + colW[i] / 2}" '
        'y="${aY + boxH + 32}" text-anchor="middle" fill="$_ink">'
        '${cols[i].id}</text>',
      );
  }
  note(
    aY + boxH + 74,
    '<tspan fill="$_green" font-weight="700">✓</tspan>  every id above is the '
    'value <tspan class="m" font-size="16px">tokenizer.json</tspan> assigns to '
    'that token',
  );
  rule(aY + boxH + 112);

  // ---- row B: the shortcut -----------------------------------------------
  const bY = 428.0;
  caption(bY - 20, 'LOWERCASE, THEN LOOK THE WORD UP', _red);
  sub(bY - 20, 330, 'same vocabulary, no normalizer');
  for (var i = 0; i < cols.length; i++) {
    final c = cols[i];
    b
      ..writeln(
        '<rect x="${colX[i]}" y="$bY" width="${colW[i]}" height="$boxH" rx="7" '
        'fill="${c.missed ? _redFill : _greyFill}" '
        'stroke="${c.missed ? _red : _rule}"/>',
      )
      ..writeln(
        '<text class="m tok" x="${colX[i] + colW[i] / 2}" y="${bY + 34}" '
        'text-anchor="middle" fill="${c.missed ? _red : _ink}">'
        '${_esc(c.word)}</text>',
      )
      ..writeln(
        '<text class="m id" x="${colX[i] + colW[i] / 2}" '
        'y="${bY + boxH + 32}" text-anchor="middle" '
        'fill="${c.missed ? _red : _muted}">'
        '${c.missed ? "[UNK]" : c.naiveId}</text>',
      );
    if (c.missed) {
      b.writeln(
        '<text class="m" x="${colX[i] + colW[i] / 2}" y="${bY + boxH + 56}" '
        'text-anchor="middle" font-size="15px" fill="$_red">'
        '${c.naiveId}</text>',
      );
    }
  }
  rule(bY + boxH + 100);

  // ---- what the second row costs -----------------------------------------
  // The three misses do not just lose their spelling, they land on the same id,
  // which is the part that cannot be undone downstream. Draw the collapse.
  const sY = bY + boxH + 132;
  const sH = 112.0;
  b.writeln(
    '<rect x="$_left" y="$sY" width="${_w - 2 * _left}" height="$sH" rx="10" '
    'fill="#fff8f7" stroke="#ffcecb"/>',
  );
  final missed = [
    for (final c in cols)
      if (c.missed) c.word,
  ];
  const chipY = sY + 26.0;
  const chipH = 40.0;
  const chipFont = 19.0;
  var cx = _left + 26;
  final chipMid = <double>[];
  for (final wtext in missed) {
    final cw = wtext.length * chipFont * _adv + 22;
    b
      ..writeln(
        '<rect x="$cx" y="$chipY" width="$cw" height="$chipH" rx="6" '
        'fill="#ffffff" stroke="$_red"/>',
      )
      ..writeln(
        '<text class="m" x="${cx + cw / 2}" y="${chipY + 27}" '
        'text-anchor="middle" font-size="${chipFont}px" fill="$_red">'
        '${_esc(wtext)}</text>',
      );
    chipMid.add(cx + cw / 2);
    cx += cw + 14;
  }
  // Converge the chips onto one id.
  const joinY = chipY + chipH + 22;
  final target = cx + 44;
  for (final mx in chipMid) {
    b.writeln(
      '<path d="M $mx ${chipY + chipH} V ${joinY - 8} H $target" '
      'fill="none" stroke="$_red" stroke-width="1.4" opacity=".55"/>',
    );
  }
  b
    ..writeln(
      '<path d="M $target ${joinY - 8} V ${chipY + 12}" fill="none" '
      'stroke="$_red" stroke-width="1.4" opacity=".55"/>',
    )
    ..writeln(
      '<text class="m" x="${target + 12}" y="${chipY + 28}" '
      'font-size="27px" font-weight="700" fill="$_red">$unkId</text>',
    )
    ..writeln(
      '<text class="sub" x="${target + 12}" y="${chipY + 52}">'
      '${missed.length} different words, one id</text>',
    );

  // ---- what the two rows mean --------------------------------------------
  final agreed = cols.length - lost;
  const fy = sY + sH + 44;
  note(
    fy,
    'The normalizer this file declares lowercases '
    '<tspan font-weight="700">and strips accents</tspan> before any lookup.',
  );
  note(
    fy + 27,
    'Skip that step and $lost of ${cols.length} words are gone. The $agreed '
    'that survived are the trap:',
  );
  note(
    fy + 54,
    'a shortcut is right on the ASCII you test with and wrong on what users '
    'send.',
  );
  b
    ..writeln(
      '<text class="tiny m" x="$_left" y="${_h - 38}">'
      'tool/parity_shot.dart · $_fixture · $vocabSize tokens</text>',
    )
    ..writeln('</svg>');
  return b.toString();
}

String _esc(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
