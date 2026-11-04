-- Capabilities describe the selected distribution, not live terminal state.
local M = {}
local profiles = {
  original = {
    purpose = 'Programming',
    character = 'Clear, structured, familiar',
    ligatures = 'Programming ligatures supported.',
    italics = 'Matching italic styles.',
    customization = 'Alternate glyphs and multiple weights; bundled edition may vary.',
    source = 'https://www.jetbrains.com/lp/mono/',
  },
  writer = {
    purpose = 'Writing; also usable for code',
    character = 'Warm, manuscript-like',
    ligatures = 'No programming-ligature set advertised by iA; do not assume operator ligatures.',
    italics = 'Dedicated italic face.',
    customization = 'Variable weight in the V edition used here.',
    source = 'https://github.com/iaolo/iA-Fonts',
  },
  lilex = {
    purpose = 'Programming',
    character = 'Open, relaxed, technical',
    ligatures = 'Programming ligatures supported; some arrow forms are optional.',
    italics = 'Matching italics, including ligatures.',
    customization = 'Variable weight and OpenType alternate glyphs.',
    source = 'https://github.com/mishamyrt/Lilex',
  },
  maple = {
    purpose = 'Programming',
    character = 'Rounded, warm, expressive',
    ligatures = 'Programming ligatures supported; coverage depends on the font build.',
    italics = 'Expressive italics with cursive letterforms.',
    customization = 'Variable weight, alternate glyphs, and customizable builds.',
    source = 'https://github.com/subframe7536/maple-font',
  },
  recursive = {
    purpose = 'Programming',
    character = 'Casual, sign-painted, notebook-like',
    ligatures = 'Code ligatures and selected stylistic sets are pre-applied in the Code edition.',
    italics = 'Expressive italic styles.',
    customization = 'This package uses static Code faces; full Recursive variable axes are not exposed here.',
    source = 'https://github.com/arrowtype/recursive',
  },
  plex = {
    purpose = 'General typography and code',
    character = 'Editorial, composed, slightly industrial',
    ligatures = 'No programming-ligature set advertised for standard Plex Mono.',
    italics = 'True italics across weights.',
    customization = 'Multiple static weights in this package; OpenType features depend on the face.',
    source = 'https://github.com/IBM/plex',
  },
  commit = {
    purpose = 'Programming',
    character = 'Neutral, quiet, precise',
    ligatures = 'Selective functional ligatures supported; upstream defaults them off.',
    italics = 'Regular and bold italic faces in this package.',
    customization = 'Smart spacing, alternate glyphs, and customizable font builds.',
    source = 'https://commitmono.com/',
  },
  geist = {
    purpose = 'Programming and interface design',
    character = 'Precise, minimal, Swiss-inspired',
    ligatures = 'No operator-ligature set assumed for this distribution.',
    italics = 'Matching italic faces.',
    customization = 'Static weights and variable-weight faces in the Homebrew package.',
    source = 'https://vercel.com/font',
  },
  martian = {
    purpose = 'Programming and technical interfaces',
    character = 'Architectural, substantial, industrial',
    ligatures = 'Do not assume programming operator ligatures.',
    italics = 'This package provides upright styles; terminal italics may be synthesized.',
    customization = 'Static weights and widths; this preset selects the standard-width family.',
    source = 'https://evilmartians.com/products/martian-mono',
  },
  iosevka = {
    purpose = 'Programming, terminals, and technical documents',
    character = 'Narrow, meticulous, compact',
    ligatures = 'Supported by the standard Iosevka build; terminal shaping settings decide usage.',
    italics = 'Italic and oblique styles are included in the collection.',
    customization = 'Many weights and alternate glyphs; custom upstream builds offer further choices.',
    source = 'https://github.com/be5invis/Iosevka',
  },
  ['google-sans-code'] = {
    purpose = 'Programming',
    character = 'Clean, approachable, contemporary',
    ligatures = 'No programming-ligature set assumed; stylistic alternates are available.',
    italics = 'Separate Roman and Italic variable fonts.',
    customization = 'Variable weight from 300 to 800 and stylistic character sets.',
    source = 'https://github.com/googlefonts/googlesans-code',
  },
  victor = {
    purpose = 'Programming',
    character = 'Slender, expressive, cursive',
    ligatures = 'Programming ligatures supported.',
    italics = 'Distinctive cursive italics plus oblique styles; themes must request italics to show them.',
    customization = 'Multiple static weights and OpenType character alternatives.',
    source = 'https://github.com/rubjo/victor-mono',
  },
  departure = {
    purpose = 'Pixel-style interfaces and terminal experiments',
    character = 'Retro-futuristic, pixel-based, deliberately stylized',
    ligatures = 'No programming-ligature set assumed.',
    italics = 'Regular face only; bold and italic may be synthesized.',
    customization = 'Single static face. Pixel edges depend on font size and display scaling.',
    source = 'https://departuremono.com/',
  },
  ['0xproto'] = {
    purpose = 'Programming',
    character = 'Clear, contemporary, carefully differentiated',
    ligatures = 'Includes shaping features such as texture healing; usage depends on terminal settings.',
    italics = 'Regular, bold, and italic faces in the package.',
    customization = 'Alternate glyphs; package also supplies separate ZxProto and TxProto families.',
    source = 'https://github.com/0xType/0xProto',
  },
  ['intel-one'] = {
    purpose = 'Programming, with a focus on character recognition',
    character = 'Substantial, distinctive, technical',
    ligatures = 'Do not assume programming operator ligatures.',
    italics = 'Matching italics for four weights.',
    customization = 'Light, regular, medium, and bold static weights.',
    source = 'https://github.com/intel/intel-one-mono',
  },
}

for id, character in pairs {
  neon = 'Restrained neo-grotesque sans',
  argon = 'Warm humanist sans',
  xenon = 'Editorial slab serif',
  krypton = 'Engineered mechanical sans',
  radon = 'Expressive handwriting',
} do
  profiles['monaspace-' .. id] = {
    purpose = 'Programming',
    character = character,
    ligatures = 'Coding ligatures and texture healing; OpenType settings control their use.',
    italics = 'Matching italic faces.',
    customization = 'Static weights and widths in this package; preset uses the standard-width family.',
    source = 'https://monaspace.githubnext.com/',
  }
end

function M.lines(item, installed)
  local p = assert(profiles[item.id], 'Missing font profile: ' .. item.id)
  -- A user's baseline can be a different family; never attach JetBrains facts to it.
  if item.id == 'original' and item.label ~= 'JetBrains Mono (baseline)' then
    p = {
      purpose = 'Your configured baseline',
      character = 'Preserved from your existing setup',
      ligatures = 'Not catalogued for this baseline family.',
      italics = 'Depends on the configured font faces.',
      customization = 'Depends on the configured font edition.',
    }
  end
  local lines = {
    '# ' .. item.label,
    '',
    'Designed for: ' .. p.purpose,
    'Character (subjective): ' .. p.character,
    '',
    '## Font supports',
    'Programming ligatures: ' .. p.ligatures,
    'Italics: ' .. p.italics,
    'Customization: ' .. p.customization,
    '',
    '## Our preset',
    item.detail,
    item.family and ('Font family: ' .. item.family) or 'Removes our overrides; restores underlying Ghostty settings.',
    'Ligatures: inherited, not explicitly enabled or disabled.',
    'Alternate glyphs / variable axes: inherited; no overrides.',
    'Actual shaping depends on Ghostty settings and the installed font build.',
    item.family and 'Bold / italic faces: automatic matching; your theme decides where italics are used.'
      or 'Bold / italics: existing configuration and theme decide usage.',
    '',
    '## Installation',
    item.family and (installed and 'Installed' or 'Not installed') or 'Uses your existing Ghostty configuration',
  }
  if item.cask then lines[#lines + 1] = 'Homebrew package: ' .. item.cask end
  if item.id == 'recursive' then lines[#lines + 1] = 'Package also includes the other Recursive Code faces.' end
  if item.cask == 'font-monaspace' then lines[#lines + 1] = 'One package installs all five Monaspace designs and their static weights/widths.' end
  vim.list_extend(lines, {
    item.family and not installed and 'Enter: confirm installation (No selected by default).' or 'Enter: apply and remember across Ghostty.',
    'Esc: close without changing typography.',
    '',
    '## Specimen — rendered in the ACTIVE terminal font',
    'Highlighting a row does not preview its font. Apply it to compare.',
    '',
    'Reading code should feel comfortable.',
    'const ready = count >= 10 && value != null;',
    '-> => == === != !== <= >=',
    '0O 1Il {} [] () rn m',
  })
  if p.source then vim.list_extend(lines, { '', 'Font documentation: ' .. p.source }) end
  return lines
end
return M
