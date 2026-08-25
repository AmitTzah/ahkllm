// Generate AhkLLM's original attachment/tray icon artwork.
//
// This intentionally uses only simple geometric primitives and a tiny pixel
// glyph table. It is kept as source for the generated SVG/ICO assets so the
// repository does not depend on an undocumented icon collection.
'use strict';

const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '..');
const FILETYPE_DIR = path.join(ROOT, 'webui', 'icons', 'filetypes');
const ICO_DIR = path.join(ROOT, 'icons');

const filetypes = {
  'ahk.svg': ['AHK', '#5b4bdb'], 'bat.svg': ['BAT', '#8b5cf6'],
  'c.svg': ['C', '#2563eb'], 'cfg.svg': ['CFG', '#64748b'],
  'cplusplus.svg': ['C++', '#2563eb'], 'css3.svg': ['CSS', '#0284c7'],
  'csv.svg': ['CSV', '#15803d'], 'docx.svg': ['DOC', '#2563eb'],
  'env.svg': ['ENV', '#475569'], 'epub.svg': ['EPUB', '#059669'],
  'gnubash.svg': ['SH', '#166534'], 'go.svg': ['GO', '#0891b2'],
  'html5.svg': ['HTML', '#ea580c'], 'image.svg': ['IMG', '#7c3aed'],
  'ini.svg': ['INI', '#64748b'], 'java.svg': ['JAVA', '#b45309'],
  'javascript.svg': ['JS', '#ca8a04'], 'json.svg': ['JSON', '#334155'],
  'markdown.svg': ['MD', '#334155'], 'odp.svg': ['ODP', '#ea580c'],
  'ods.svg': ['ODS', '#15803d'], 'odt.svg': ['ODT', '#2563eb'],
  'pdf.svg': ['PDF', '#dc2626'], 'powershell.svg': ['PS', '#2563eb'],
  'pptx.svg': ['PPT', '#c2410c'], 'python.svg': ['PY', '#1d4ed8'],
  'rtf.svg': ['RTF', '#475569'], 'rust.svg': ['RS', '#57534e'],
  'sqlite.svg': ['SQL', '#0369a1'], 'toml.svg': ['TOML', '#9a3412'],
  'txt.svg': ['TXT', '#475569'], 'typescript.svg': ['TS', '#2563eb'],
  'xlsx.svg': ['XLS', '#15803d'], 'xml.svg': ['XML', '#0369a1'],
  'yaml.svg': ['YML', '#b91c1c']
};

function escapeXml(value) {
  return value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function filetypeSvg(label, color) {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" role="img" aria-label="${escapeXml(label)} file"><path fill="${color}" d="M5 2h14l8 8v20H5z"/><path fill="#fff" opacity=".28" d="M19 2v8h8z"/><rect x="7" y="18" width="18" height="8" rx="2" fill="#fff" opacity=".9"/><text x="16" y="24.2" text-anchor="middle" font-family="Arial,sans-serif" font-size="5.2" font-weight="700" fill="${color}">${escapeXml(label)}</text></svg>\n`;
}

const glyphs = {
  A: ['01110', '10001', '10001', '11111', '10001', '10001', '10001'],
  D: ['11110', '10001', '10001', '10001', '10001', '10001', '11110'],
  G: ['01110', '10001', '10000', '10111', '10001', '10001', '01110'],
  I: ['11111', '00100', '00100', '00100', '00100', '00100', '11111'],
  O: ['01110', '10001', '10001', '10001', '10001', '10001', '01110'],
  P: ['11110', '10001', '10001', '11110', '10000', '10000', '10000'],
  X: ['10001', '10001', '01010', '00100', '01010', '10001', '10001'],
  N: ['10001', '11001', '10101', '10011', '10001', '10001', '10001'],
  F: ['11111', '10000', '10000', '11110', '10000', '10000', '10000'],
  S: ['01111', '10000', '10000', '01110', '00001', '00001', '11110']
};

function drawGlyph(pixels, label, color) {
  const chars = [...label.toUpperCase()].slice(0, 2);
  const scale = 3;
  const totalWidth = chars.length * 5 * scale + (chars.length - 1) * scale;
  let left = Math.floor((32 - totalWidth) / 2);
  const top = 8;
  for (const char of chars) {
    const rows = glyphs[char] || glyphs.X;
    for (let y = 0; y < rows.length; y++) {
      for (let x = 0; x < rows[y].length; x++) {
        if (rows[y][x] !== '1') continue;
        for (let sy = 0; sy < scale; sy++) {
          for (let sx = 0; sx < scale; sx++) {
            const px = left + x * scale + sx;
            const py = top + y * scale + sy;
            if (px >= 0 && px < 32 && py >= 0 && py < 32) pixels[py * 32 + px] = color;
          }
        }
      }
    }
    left += 5 * scale + scale;
  }
}

function makeIco(background, label, layers = false) {
  const pixels = Array.from({length: 32 * 32}, () => background);
  if (layers) {
    for (const [y, alpha] of [[8, 255], [14, 210], [20, 165]]) {
      for (let x = 8; x < 24; x++) {
        pixels[y * 32 + x] = [255, 255, 255, alpha];
        pixels[(y + 1) * 32 + x] = [255, 255, 255, alpha];
      }
    }
  } else {
    drawGlyph(pixels, label, [255, 255, 255, 255]);
  }

  const dib = Buffer.alloc(40 + 32 * 32 * 4 + 32 * 4);
  dib.writeUInt32LE(40, 0);
  dib.writeInt32LE(32, 4);
  dib.writeInt32LE(64, 8);
  dib.writeUInt16LE(1, 12);
  dib.writeUInt16LE(32, 14);
  dib.writeUInt32LE(0, 16);
  dib.writeUInt32LE(32 * 32 * 4, 20);
  let offset = 40;
  for (let y = 31; y >= 0; y--) {
    for (let x = 0; x < 32; x++) {
      const [r, g, b, a] = pixels[y * 32 + x];
      dib[offset++] = b; dib[offset++] = g; dib[offset++] = r; dib[offset++] = a;
    }
  }

  const header = Buffer.alloc(22);
  header.writeUInt16LE(0, 0); header.writeUInt16LE(1, 2); header.writeUInt16LE(1, 4);
  header.writeUInt8(32, 6); header.writeUInt8(32, 7); header.writeUInt8(0, 8);
  header.writeUInt8(0, 9); header.writeUInt16LE(1, 10); header.writeUInt16LE(32, 12);
  header.writeUInt32LE(dib.length, 14); header.writeUInt32LE(22, 18);
  return Buffer.concat([header, dib]);
}

fs.mkdirSync(FILETYPE_DIR, {recursive: true});
fs.mkdirSync(ICO_DIR, {recursive: true});
for (const [filename, [label, color]] of Object.entries(filetypes)) {
  fs.writeFileSync(path.join(FILETYPE_DIR, filename), filetypeSvg(label, color));
}
const icoAssets = {
  'IconOn.ico': [[91, 75, 219, 255], '', true],
  'IconOff.ico': [[100, 116, 139, 255], '', true],
  'anthropic.ico': [[217, 119, 6, 255], 'AN'],
  'deepseek.ico': [[37, 99, 235, 255], 'DS'],
  'google.ico': [[22, 163, 74, 255], 'GG'],
  'openai.ico': [[15, 118, 110, 255], 'AI'],
  'openrouter.ico': [[124, 58, 237, 255], 'OR'],
  'perplexity.ico': [[8, 145, 178, 255], 'PX']
};
for (const [filename, [color, label, layers]] of Object.entries(icoAssets)) {
  fs.writeFileSync(path.join(ICO_DIR, filename), makeIco(color, label, layers));
}
console.log(`Generated ${Object.keys(filetypes).length} original SVGs and ${Object.keys(icoAssets).length} original ICOs.`);
