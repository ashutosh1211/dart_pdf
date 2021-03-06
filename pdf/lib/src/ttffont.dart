/*
 * Copyright (C) 2017, David PHAM-VAN <dev.nfet.net@gmail.com>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// ignore_for_file: omit_local_variable_types

part of pdf;

class PdfTtfFont extends PdfFont {
  /// Constructs a [PdfTtfFont]
  PdfTtfFont(PdfDocument pdfDocument, ByteData bytes, {bool protect = false})
      : font = TtfParser(bytes),
        super._create(pdfDocument, subtype: '/TrueType') {
    file = PdfObjectStream(pdfDocument, isBinary: true);
    unicodeCMap = PdfUnicodeCmap(pdfDocument, protect);
    descriptor = PdfFontDescriptor(this, file);
    widthsObject = PdfArrayObject(pdfDocument, PdfArray());
  }

  @override
  String get subtype => font.unicode ? '/Type0' : super.subtype;

  PdfUnicodeCmap unicodeCMap;

  PdfFontDescriptor descriptor;

  PdfObjectStream file;

  PdfArrayObject widthsObject;

  final TtfParser font;

  @override
  String get fontName => font.fontName;

  @override
  double get ascent => font.ascent.toDouble() / font.unitsPerEm;

  @override
  double get descent => font.descent.toDouble() / font.unitsPerEm;

  @override
  PdfFontMetrics glyphMetrics(int charCode) {
//    final int g = font.charToGlyphIndexMap[charCode];

    if (charCode == null) {
      return PdfFontMetrics.zero;
    }

    return font.glyphInfoMap[charCode] ?? PdfFontMetrics.zero;
  }

  void _buildTrueType(PdfDict params) {
    int charMin;
    int charMax;

    file.buf.putBytes(font.bytes.buffer.asUint8List());
    file.params['/Length1'] = PdfNum(font.bytes.lengthInBytes);

    params['/BaseFont'] = PdfName('/' + fontName);
    params['/FontDescriptor'] = descriptor.ref();
    charMin = 32;
    charMax = 255;
    for (int i = charMin; i <= charMax; i++) {
      widthsObject.array
          .add(PdfNum((glyphMetrics(i).advanceWidth * 1000.0).toInt()));
    }
    params['/FirstChar'] = PdfNum(charMin);
    params['/LastChar'] = PdfNum(charMax);
    params['/Widths'] = widthsObject.ref();
  }

  void _buildType0(PdfDict params) {
    int charMin;
    int charMax;

    final TtfWriter ttfWriter = TtfWriter(font);
    final Uint8List data = ttfWriter.withChars(unicodeCMap.cmap);
    file.buf.putBytes(data);
    file.params['/Length1'] = PdfNum(data.length);

    final PdfDict descendantFont = PdfDict(<String, PdfDataType>{
      '/Type': const PdfName('/Font'),
      '/BaseFont': PdfName('/' + fontName),
      '/FontFile2': file.ref(),
      '/FontDescriptor': descriptor.ref(),
      '/W': PdfArray(<PdfDataType>[
        const PdfNum(0),
        widthsObject.ref(),
      ]),
      '/CIDToGIDMap': const PdfName('/Identity'),
      '/DW': const PdfNum(1000),
      '/Subtype': const PdfName('/CIDFontType2'),
      '/CIDSystemInfo': PdfDict(<String, PdfDataType>{
        '/Supplement': const PdfNum(0),
        '/Registry': PdfSecString.fromString(this, 'Adobe'),
        '/Ordering': PdfSecString.fromString(this, 'Identity-H'),
      })
    });

    params['/BaseFont'] = PdfName('/' + fontName);
    params['/Encoding'] = const PdfName('/Identity-H');
    params['/DescendantFonts'] = PdfArray(<PdfDataType>[descendantFont]);
    params['/ToUnicode'] = unicodeCMap.ref();

    charMin = 0;
    charMax = unicodeCMap.cmap.length - 1;
    for (int i = charMin; i <= charMax; i++) {
      widthsObject.array.add(PdfNum(
          (glyphMetrics(unicodeCMap.cmap[i]).advanceWidth * 1000.0).toInt()));
    }
  }

  @override
  void _prepare() {
    super._prepare();

    if (font.unicode) {
      _buildType0(params);
    } else {
      _buildTrueType(params);
    }
  }

  @override
  void putText(PdfStream stream, String text) {
    if (!font.unicode) {
      super.putText(stream, text);
    }

    Bidi bidi = Bidi();
    // Create and register 'glyphIndex' state modifier
    var charToGlyphIndexMod = (Token token, ContextParams contextParams) =>
        this.charToGlyphIndex(token.char);
    bidi.registerModifier('glyphIndex', null, charToGlyphIndexMod);

    bidi.applyFeatures(this.font, [
      {
        "script": 'dev2',
        "tags": ['nukt', 'akhn', 'rphf', 'blwf', 'half', 'vatu', 'cjct']
      }
    ]);

    var indexes = bidi.getTextGlyphs(text);

    final Runes runes = text.runes;

    stream.putByte(0x3c);
    for (int rune in runes) {
      int char = unicodeCMap.cmap.indexOf(rune);
      if (char == -1) {
        char = unicodeCMap.cmap.length;
        unicodeCMap.cmap.add(rune);
      }

      stream.putBytes(char.toRadixString(16).padLeft(4, '0').codeUnits);
    }
    stream.putByte(0x3e);
  }

  dynamic charToGlyphIndex(String c) {
    var code = c.codeUnitAt(0);
    return this.font.charToGlyphIndexMap[code] ?? null;
  }

  @override
  PdfFontMetrics stringMetrics(String s) {
    if (s.isEmpty || !font.unicode) {
      return super.stringMetrics(s);
    }

    final Runes runes = s.runes;
    final List<int> bytes = <int>[];
    runes.forEach(bytes.add);

    final Iterable<PdfFontMetrics> metrics = bytes.map(glyphMetrics);
    return PdfFontMetrics.append(metrics);
  }
}
