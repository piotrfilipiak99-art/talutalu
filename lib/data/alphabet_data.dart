class AlphabetEntry {
  final String char;
  final String name;
  final Map<String, String> phonetics;
  // Syllable form spoken by TTS (e.g. 'ba, aba'); null = fall back to entry.name
  final String? ttsText;

  const AlphabetEntry({
    required this.char,
    required this.name,
    required this.phonetics,
    this.ttsText,
  });

  // source lang → phonetic; fallback to 'latin'; fallback to name
  String phoneticFor(String sourceLang) =>
      phonetics[sourceLang] ?? phonetics['latin'] ?? name;
}

class AlphabetGroup {
  final String label;
  final List<AlphabetEntry> entries;
  const AlphabetGroup({required this.label, required this.entries});
}

class LanguageAlphabet {
  final String targetCode;
  final String ttsLocale;
  final String nativeName;
  final List<AlphabetGroup> groups;
  const LanguageAlphabet({
    required this.targetCode,
    required this.ttsLocale,
    required this.nativeName,
    required this.groups,
  });
}

/// Returns null for Latin-script languages (no panel needed).
LanguageAlphabet? alphabetFor(String targetCode) {
  switch (targetCode) {
    case 'ru': return _russian;
    case 'uk': return _ukrainian;
    case 'el': return _greek;
    case 'ja': return _japanese;
    case 'ko': return _korean;
    case 'ar': return _arabic;
    case 'hi': return _hindi;
    case 'pl': return _polish;
    case 'de': return _german;
    case 'es': return _spanish;
    case 'fr': return _french;
    case 'it': return _italian;
    case 'pt': return _portuguese;
    case 'sv': return _swedish;
    case 'tr': return _turkish;
    case 'cs': return _czech;
    case 'nl': return _dutch;
    case 'en': return _english;
    default:   return null;
  }
}

// ── Character sets per language (uppercase) ───────────────────────────────────
// Used to compute which target-language letters are absent from the source
// language, so the panel only shows genuinely new characters.

const _latinCharSets = <String, Set<String>>{
  'en': {'A','B','C','D','E','F','G','H','I','J','K','L','M',
         'N','O','P','Q','R','S','T','U','V','W','X','Y','Z'},
  'pl': {'A','Ą','B','C','Ć','D','E','Ę','F','G','H','I','J',
         'K','L','Ł','M','N','Ń','O','Ó','P','R','S','Ś','T',
         'U','W','Y','Z','Ź','Ż'},
  'de': {'A','Ä','B','C','D','E','F','G','H','I','J','K','L',
         'M','N','O','Ö','P','Q','R','S','ß','T','U','Ü','V',
         'W','X','Y','Z'},
  'es': {'A','B','C','D','E','F','G','H','I','J','K','L','M',
         'N','Ñ','O','P','Q','R','S','T','U','V','W','X','Y','Z'},
  'fr': {'A','À','Â','Æ','B','C','Ç','D','E','É','È','Ê','Ë',
         'F','G','H','I','Î','Ï','J','K','L','M','N','O','Ô',
         'Œ','P','Q','R','S','T','U','Ù','Û','Ü','V','W','X',
         'Y','Z'},
  'it': {'A','B','C','D','E','F','G','H','I','J','K','L','M',
         'N','O','P','Q','R','S','T','U','V','W','X','Y','Z'},
  'pt': {'A','Á','Â','Ã','À','B','C','Ç','D','E','É','Ê','F',
         'G','H','I','Í','J','K','L','M','N','O','Ó','Ô','Õ',
         'P','Q','R','S','T','U','Ú','V','W','X','Y','Z'},
  'sv': {'A','Å','Ä','B','C','D','E','F','G','H','I','J','K',
         'L','M','N','O','Ö','P','Q','R','S','T','U','V','W',
         'X','Y','Z'},
  'tr': {'A','B','C','Ç','D','E','F','G','Ğ','H','I','İ','J',
         'K','L','M','N','O','Ö','P','R','S','Ş','T','U','Ü',
         'V','Y','Z'},
  'nl': {'A','B','C','D','E','F','G','H','I','J','K','L','M',
         'N','O','P','Q','R','S','T','U','V','W','X','Y','Z'},
  'cs': {'A','Á','B','C','Č','D','Ď','E','É','Ě','F','G','H',
         'I','Í','J','K','L','M','N','Ň','O','Ó','P','R','Ř',
         'S','Š','T','Ť','U','Ú','Ů','V','W','X','Y','Ý','Z','Ž'},
};

/// Returns entries from [entries] whose character is absent from
/// [sourceLang]'s alphabet. For non-Latin or unknown source languages
/// (Cyrillic, Kana, etc.) returns all entries unchanged.
List<AlphabetEntry> missingEntries(
    String sourceLang, List<AlphabetEntry> entries) {
  final sourceChars = _latinCharSets[sourceLang];
  if (sourceChars == null) return entries; // non-Latin source → all are new
  return entries
      .where((e) => !sourceChars.contains(e.char.toUpperCase()))
      .toList();
}

// ── Russian ───────────────────────────────────────────────────────────────────

const _russianLetters = <AlphabetEntry>[
  AlphabetEntry(char: 'А', name: 'а',   phonetics: {'latin': 'a'},                              ttsText: 'а'),
  AlphabetEntry(char: 'Б', name: 'бэ',  phonetics: {'latin': 'b'},                              ttsText: 'ба, аба'),
  AlphabetEntry(char: 'В', name: 'вэ',  phonetics: {'latin': 'v', 'pl': 'w', 'de': 'w'},        ttsText: 'ва, ава'),
  AlphabetEntry(char: 'Г', name: 'гэ',  phonetics: {'latin': 'g'},                              ttsText: 'га, ага'),
  AlphabetEntry(char: 'Д', name: 'дэ',  phonetics: {'latin': 'd'},                              ttsText: 'да, ада'),
  AlphabetEntry(char: 'Е', name: 'е',   phonetics: {'latin': 'ye', 'pl': 'je', 'de': 'je'},     ttsText: 'е'),
  AlphabetEntry(char: 'Ё', name: 'ё',   phonetics: {'latin': 'yo', 'pl': 'jo', 'de': 'jo'},     ttsText: 'ё'),
  AlphabetEntry(char: 'Ж', name: 'жэ',  phonetics: {'latin': 'zh', 'pl': 'ż', 'de': 'sch'},     ttsText: 'жа, ажа'),
  AlphabetEntry(char: 'З', name: 'зэ',  phonetics: {'latin': 'z', 'de': 's'},                   ttsText: 'за, аза'),
  AlphabetEntry(char: 'И', name: 'и',   phonetics: {'latin': 'i'},                              ttsText: 'и'),
  AlphabetEntry(char: 'Й', name: 'й',   phonetics: {'latin': 'y', 'pl': 'j', 'de': 'j'},        ttsText: 'йа, ай'),
  AlphabetEntry(char: 'К', name: 'ка',  phonetics: {'latin': 'k'},                              ttsText: 'ка, ака'),
  AlphabetEntry(char: 'Л', name: 'эл',  phonetics: {'latin': 'l'},                              ttsText: 'ла, ала'),
  AlphabetEntry(char: 'М', name: 'эм',  phonetics: {'latin': 'm'},                              ttsText: 'ма, ама'),
  AlphabetEntry(char: 'Н', name: 'эн',  phonetics: {'latin': 'n'},                              ttsText: 'на, ана'),
  AlphabetEntry(char: 'О', name: 'о',   phonetics: {'latin': 'o'},                              ttsText: 'о'),
  AlphabetEntry(char: 'П', name: 'пэ',  phonetics: {'latin': 'p'},                              ttsText: 'па, апа'),
  AlphabetEntry(char: 'Р', name: 'эр',  phonetics: {'latin': 'r'},                              ttsText: 'ра, ара'),
  AlphabetEntry(char: 'С', name: 'эс',  phonetics: {'latin': 's'},                              ttsText: 'са, аса'),
  AlphabetEntry(char: 'Т', name: 'тэ',  phonetics: {'latin': 't'},                              ttsText: 'та, ата'),
  AlphabetEntry(char: 'У', name: 'у',   phonetics: {'latin': 'u'},                              ttsText: 'у'),
  AlphabetEntry(char: 'Ф', name: 'эф',  phonetics: {'latin': 'f'},                              ttsText: 'фа, афа'),
  AlphabetEntry(char: 'Х', name: 'ха',  phonetics: {'latin': 'kh', 'pl': 'ch', 'de': 'ch'},     ttsText: 'ха, аха'),
  AlphabetEntry(char: 'Ц', name: 'цэ',  phonetics: {'latin': 'ts', 'pl': 'c', 'de': 'z'},       ttsText: 'ца, аца'),
  AlphabetEntry(char: 'Ч', name: 'чэ',  phonetics: {'latin': 'ch', 'pl': 'cz', 'de': 'tsch'},   ttsText: 'ча, ача'),
  AlphabetEntry(char: 'Ш', name: 'ша',  phonetics: {'latin': 'sh', 'pl': 'sz', 'de': 'sch'},    ttsText: 'ша, аша'),
  AlphabetEntry(char: 'Щ', name: 'ща',  phonetics: {'latin': 'shch', 'pl': 'szcz', 'de': 'schtsch'}, ttsText: 'ща, аща'),
  AlphabetEntry(char: 'Ъ', name: 'ъ',   phonetics: {'latin': 'ʺ', 'en': '(hard)', 'pl': '(tw.)'}),
  AlphabetEntry(char: 'Ы', name: 'ы',   phonetics: {'latin': 'y', 'en': 'ы (uh)'},              ttsText: 'ы'),
  AlphabetEntry(char: 'Ь', name: 'ь',   phonetics: {'latin': 'ʹ', 'en': '(soft)', 'pl': '(mięk.)'}),
  AlphabetEntry(char: 'Э', name: 'э',   phonetics: {'latin': 'e'},                              ttsText: 'э'),
  AlphabetEntry(char: 'Ю', name: 'ю',   phonetics: {'latin': 'yu', 'pl': 'ju', 'de': 'ju'},     ttsText: 'ю'),
  AlphabetEntry(char: 'Я', name: 'я',   phonetics: {'latin': 'ya', 'pl': 'ja', 'de': 'ja'},     ttsText: 'я'),
];

const _russian = LanguageAlphabet(
  targetCode: 'ru',
  ttsLocale: 'ru-RU',
  nativeName: 'Алфавит',
  groups: [AlphabetGroup(label: 'Кириллица', entries: _russianLetters)],
);

// ── Ukrainian ─────────────────────────────────────────────────────────────────

const _ukrainianLetters = <AlphabetEntry>[
  AlphabetEntry(char: 'А', name: 'а',  phonetics: {'latin': 'a'},                              ttsText: 'а'),
  AlphabetEntry(char: 'Б', name: 'бе', phonetics: {'latin': 'b'},                              ttsText: 'ба, аба'),
  AlphabetEntry(char: 'В', name: 'ве', phonetics: {'latin': 'v', 'pl': 'w', 'de': 'w'},        ttsText: 'ва, ава'),
  AlphabetEntry(char: 'Г', name: 'ге', phonetics: {'latin': 'h', 'pl': 'h', 'en': 'h'},        ttsText: 'га, ага'),
  AlphabetEntry(char: 'Ґ', name: 'ґе', phonetics: {'latin': 'g'},                              ttsText: 'ґа, аґа'),
  AlphabetEntry(char: 'Д', name: 'де', phonetics: {'latin': 'd'},                              ttsText: 'да, ада'),
  AlphabetEntry(char: 'Е', name: 'е',  phonetics: {'latin': 'e'},                              ttsText: 'е'),
  AlphabetEntry(char: 'Є', name: 'є',  phonetics: {'latin': 'ye', 'pl': 'je', 'de': 'je'},     ttsText: 'є'),
  AlphabetEntry(char: 'Ж', name: 'же', phonetics: {'latin': 'zh', 'pl': 'ż', 'de': 'sch'},     ttsText: 'жа, ажа'),
  AlphabetEntry(char: 'З', name: 'зе', phonetics: {'latin': 'z'},                              ttsText: 'за, аза'),
  AlphabetEntry(char: 'И', name: 'и',  phonetics: {'latin': 'y', 'pl': 'y', 'en': 'y (bit)'}, ttsText: 'и'),
  AlphabetEntry(char: 'І', name: 'і',  phonetics: {'latin': 'i'},                              ttsText: 'і'),
  AlphabetEntry(char: 'Ї', name: 'ї',  phonetics: {'latin': 'yi', 'pl': 'ji'},                 ttsText: 'ї'),
  AlphabetEntry(char: 'Й', name: 'й',  phonetics: {'latin': 'y', 'pl': 'j', 'de': 'j'},        ttsText: 'йа, ай'),
  AlphabetEntry(char: 'К', name: 'ка', phonetics: {'latin': 'k'},                              ttsText: 'ка, ака'),
  AlphabetEntry(char: 'Л', name: 'ел', phonetics: {'latin': 'l'},                              ttsText: 'ла, ала'),
  AlphabetEntry(char: 'М', name: 'ем', phonetics: {'latin': 'm'},                              ttsText: 'ма, ама'),
  AlphabetEntry(char: 'Н', name: 'ен', phonetics: {'latin': 'n'},                              ttsText: 'на, ана'),
  AlphabetEntry(char: 'О', name: 'о',  phonetics: {'latin': 'o'},                              ttsText: 'о'),
  AlphabetEntry(char: 'П', name: 'пе', phonetics: {'latin': 'p'},                              ttsText: 'па, апа'),
  AlphabetEntry(char: 'Р', name: 'ер', phonetics: {'latin': 'r'},                              ttsText: 'ра, ара'),
  AlphabetEntry(char: 'С', name: 'ес', phonetics: {'latin': 's'},                              ttsText: 'са, аса'),
  AlphabetEntry(char: 'Т', name: 'те', phonetics: {'latin': 't'},                              ttsText: 'та, ата'),
  AlphabetEntry(char: 'У', name: 'у',  phonetics: {'latin': 'u'},                              ttsText: 'у'),
  AlphabetEntry(char: 'Ф', name: 'еф', phonetics: {'latin': 'f'},                              ttsText: 'фа, афа'),
  AlphabetEntry(char: 'Х', name: 'ха', phonetics: {'latin': 'kh', 'pl': 'ch', 'de': 'ch'},     ttsText: 'ха, аха'),
  AlphabetEntry(char: 'Ц', name: 'це', phonetics: {'latin': 'ts', 'pl': 'c'},                  ttsText: 'ца, аца'),
  AlphabetEntry(char: 'Ч', name: 'че', phonetics: {'latin': 'ch', 'pl': 'cz', 'de': 'tsch'},   ttsText: 'ча, ача'),
  AlphabetEntry(char: 'Ш', name: 'ша', phonetics: {'latin': 'sh', 'pl': 'sz', 'de': 'sch'},    ttsText: 'ша, аша'),
  AlphabetEntry(char: 'Щ', name: 'ща', phonetics: {'latin': 'shch', 'pl': 'szcz'},             ttsText: 'ща, аща'),
  AlphabetEntry(char: 'Ь', name: 'ь',  phonetics: {'latin': 'ʹ', 'en': '(soft)', 'pl': '(mięk.)'}),
  AlphabetEntry(char: 'Ю', name: 'ю',  phonetics: {'latin': 'yu', 'pl': 'ju', 'de': 'ju'},     ttsText: 'ю'),
  AlphabetEntry(char: 'Я', name: 'я',  phonetics: {'latin': 'ya', 'pl': 'ja', 'de': 'ja'},     ttsText: 'я'),
];

const _ukrainian = LanguageAlphabet(
  targetCode: 'uk',
  ttsLocale: 'uk-UA',
  nativeName: 'Алфавіт',
  groups: [AlphabetGroup(label: 'Кирилиця', entries: _ukrainianLetters)],
);

// ── Greek ─────────────────────────────────────────────────────────────────────

const _greekLetters = <AlphabetEntry>[
  AlphabetEntry(char: 'Α', name: 'άλφα',   phonetics: {'latin': 'a'},                              ttsText: 'α'),
  AlphabetEntry(char: 'Β', name: 'βήτα',   phonetics: {'latin': 'v', 'en': 'v'},                   ttsText: 'βα, αβα'),
  AlphabetEntry(char: 'Γ', name: 'γάμα',   phonetics: {'latin': 'g/y', 'en': 'g/y'},               ttsText: 'γα, αγα'),
  AlphabetEntry(char: 'Δ', name: 'δέλτα',  phonetics: {'latin': 'dh', 'en': 'th(e)'},              ttsText: 'δα, αδα'),
  AlphabetEntry(char: 'Ε', name: 'έψιλον', phonetics: {'latin': 'e'},                              ttsText: 'ε'),
  AlphabetEntry(char: 'Ζ', name: 'ζήτα',   phonetics: {'latin': 'z'},                              ttsText: 'ζα, αζα'),
  AlphabetEntry(char: 'Η', name: 'ήτα',    phonetics: {'latin': 'i', 'en': 'ee'},                   ttsText: 'η'),
  AlphabetEntry(char: 'Θ', name: 'θήτα',   phonetics: {'latin': 'th', 'en': 'th(ink)'},             ttsText: 'θα, αθα'),
  AlphabetEntry(char: 'Ι', name: 'ιώτα',   phonetics: {'latin': 'i', 'en': 'ee'},                   ttsText: 'ι'),
  AlphabetEntry(char: 'Κ', name: 'κάπα',   phonetics: {'latin': 'k'},                              ttsText: 'κα, ακα'),
  AlphabetEntry(char: 'Λ', name: 'λάμδα',  phonetics: {'latin': 'l'},                              ttsText: 'λα, αλα'),
  AlphabetEntry(char: 'Μ', name: 'μι',     phonetics: {'latin': 'm'},                              ttsText: 'μα, αμα'),
  AlphabetEntry(char: 'Ν', name: 'νι',     phonetics: {'latin': 'n'},                              ttsText: 'να, ανα'),
  AlphabetEntry(char: 'Ξ', name: 'ξι',     phonetics: {'latin': 'ks'},                             ttsText: 'ξα, αξα'),
  AlphabetEntry(char: 'Ο', name: 'όμικρον',phonetics: {'latin': 'o'},                              ttsText: 'ο'),
  AlphabetEntry(char: 'Π', name: 'πι',     phonetics: {'latin': 'p'},                              ttsText: 'πα, απα'),
  AlphabetEntry(char: 'Ρ', name: 'ρο',     phonetics: {'latin': 'r'},                              ttsText: 'ρα, αρα'),
  AlphabetEntry(char: 'Σ', name: 'σίγμα',  phonetics: {'latin': 's'},                              ttsText: 'σα, ασα'),
  AlphabetEntry(char: 'Τ', name: 'ταυ',    phonetics: {'latin': 't'},                              ttsText: 'τα, ατα'),
  AlphabetEntry(char: 'Υ', name: 'ύψιλον', phonetics: {'latin': 'i', 'en': 'ee'},                   ttsText: 'υ'),
  AlphabetEntry(char: 'Φ', name: 'φι',     phonetics: {'latin': 'f'},                              ttsText: 'φα, αφα'),
  AlphabetEntry(char: 'Χ', name: 'χι',     phonetics: {'latin': 'ch', 'en': 'ch (loch)', 'pl': 'ch'}, ttsText: 'χα, αχα'),
  AlphabetEntry(char: 'Ψ', name: 'ψι',     phonetics: {'latin': 'ps'},                             ttsText: 'ψα, αψα'),
  AlphabetEntry(char: 'Ω', name: 'ωμέγα',  phonetics: {'latin': 'o'},                              ttsText: 'ω'),
];

const _greek = LanguageAlphabet(
  targetCode: 'el',
  ttsLocale: 'el-GR',
  nativeName: 'Αλφάβητο',
  groups: [AlphabetGroup(label: 'Αλφάβητο', entries: _greekLetters)],
);

// ── Japanese ──────────────────────────────────────────────────────────────────

const _hiragana = <AlphabetEntry>[
  AlphabetEntry(char: 'あ', name: 'あ', phonetics: {'latin': 'a'}),
  AlphabetEntry(char: 'い', name: 'い', phonetics: {'latin': 'i'}),
  AlphabetEntry(char: 'う', name: 'う', phonetics: {'latin': 'u'}),
  AlphabetEntry(char: 'え', name: 'え', phonetics: {'latin': 'e'}),
  AlphabetEntry(char: 'お', name: 'お', phonetics: {'latin': 'o'}),
  AlphabetEntry(char: 'か', name: 'か', phonetics: {'latin': 'ka'}),
  AlphabetEntry(char: 'き', name: 'き', phonetics: {'latin': 'ki'}),
  AlphabetEntry(char: 'く', name: 'く', phonetics: {'latin': 'ku'}),
  AlphabetEntry(char: 'け', name: 'け', phonetics: {'latin': 'ke'}),
  AlphabetEntry(char: 'こ', name: 'こ', phonetics: {'latin': 'ko'}),
  AlphabetEntry(char: 'さ', name: 'さ', phonetics: {'latin': 'sa'}),
  AlphabetEntry(char: 'し', name: 'し', phonetics: {'latin': 'shi'}),
  AlphabetEntry(char: 'す', name: 'す', phonetics: {'latin': 'su'}),
  AlphabetEntry(char: 'せ', name: 'せ', phonetics: {'latin': 'se'}),
  AlphabetEntry(char: 'そ', name: 'そ', phonetics: {'latin': 'so'}),
  AlphabetEntry(char: 'た', name: 'た', phonetics: {'latin': 'ta'}),
  AlphabetEntry(char: 'ち', name: 'ち', phonetics: {'latin': 'chi'}),
  AlphabetEntry(char: 'つ', name: 'つ', phonetics: {'latin': 'tsu'}),
  AlphabetEntry(char: 'て', name: 'て', phonetics: {'latin': 'te'}),
  AlphabetEntry(char: 'と', name: 'と', phonetics: {'latin': 'to'}),
  AlphabetEntry(char: 'な', name: 'な', phonetics: {'latin': 'na'}),
  AlphabetEntry(char: 'に', name: 'に', phonetics: {'latin': 'ni'}),
  AlphabetEntry(char: 'ぬ', name: 'ぬ', phonetics: {'latin': 'nu'}),
  AlphabetEntry(char: 'ね', name: 'ね', phonetics: {'latin': 'ne'}),
  AlphabetEntry(char: 'の', name: 'の', phonetics: {'latin': 'no'}),
  AlphabetEntry(char: 'は', name: 'は', phonetics: {'latin': 'ha'}),
  AlphabetEntry(char: 'ひ', name: 'ひ', phonetics: {'latin': 'hi'}),
  AlphabetEntry(char: 'ふ', name: 'ふ', phonetics: {'latin': 'fu'}),
  AlphabetEntry(char: 'へ', name: 'へ', phonetics: {'latin': 'he'}),
  AlphabetEntry(char: 'ほ', name: 'ほ', phonetics: {'latin': 'ho'}),
  AlphabetEntry(char: 'ま', name: 'ま', phonetics: {'latin': 'ma'}),
  AlphabetEntry(char: 'み', name: 'み', phonetics: {'latin': 'mi'}),
  AlphabetEntry(char: 'む', name: 'む', phonetics: {'latin': 'mu'}),
  AlphabetEntry(char: 'め', name: 'め', phonetics: {'latin': 'me'}),
  AlphabetEntry(char: 'も', name: 'も', phonetics: {'latin': 'mo'}),
  AlphabetEntry(char: 'や', name: 'や', phonetics: {'latin': 'ya'}),
  AlphabetEntry(char: 'ゆ', name: 'ゆ', phonetics: {'latin': 'yu'}),
  AlphabetEntry(char: 'よ', name: 'よ', phonetics: {'latin': 'yo'}),
  AlphabetEntry(char: 'ら', name: 'ら', phonetics: {'latin': 'ra'}),
  AlphabetEntry(char: 'り', name: 'り', phonetics: {'latin': 'ri'}),
  AlphabetEntry(char: 'る', name: 'る', phonetics: {'latin': 'ru'}),
  AlphabetEntry(char: 'れ', name: 'れ', phonetics: {'latin': 're'}),
  AlphabetEntry(char: 'ろ', name: 'ろ', phonetics: {'latin': 'ro'}),
  AlphabetEntry(char: 'わ', name: 'わ', phonetics: {'latin': 'wa'}),
  AlphabetEntry(char: 'を', name: 'を', phonetics: {'latin': 'wo'}),
  AlphabetEntry(char: 'ん', name: 'ん', phonetics: {'latin': 'n'}),
];

const _katakana = <AlphabetEntry>[
  AlphabetEntry(char: 'ア', name: 'ア', phonetics: {'latin': 'a'}),
  AlphabetEntry(char: 'イ', name: 'イ', phonetics: {'latin': 'i'}),
  AlphabetEntry(char: 'ウ', name: 'ウ', phonetics: {'latin': 'u'}),
  AlphabetEntry(char: 'エ', name: 'エ', phonetics: {'latin': 'e'}),
  AlphabetEntry(char: 'オ', name: 'オ', phonetics: {'latin': 'o'}),
  AlphabetEntry(char: 'カ', name: 'カ', phonetics: {'latin': 'ka'}),
  AlphabetEntry(char: 'キ', name: 'キ', phonetics: {'latin': 'ki'}),
  AlphabetEntry(char: 'ク', name: 'ク', phonetics: {'latin': 'ku'}),
  AlphabetEntry(char: 'ケ', name: 'ケ', phonetics: {'latin': 'ke'}),
  AlphabetEntry(char: 'コ', name: 'コ', phonetics: {'latin': 'ko'}),
  AlphabetEntry(char: 'サ', name: 'サ', phonetics: {'latin': 'sa'}),
  AlphabetEntry(char: 'シ', name: 'シ', phonetics: {'latin': 'shi'}),
  AlphabetEntry(char: 'ス', name: 'ス', phonetics: {'latin': 'su'}),
  AlphabetEntry(char: 'セ', name: 'セ', phonetics: {'latin': 'se'}),
  AlphabetEntry(char: 'ソ', name: 'ソ', phonetics: {'latin': 'so'}),
  AlphabetEntry(char: 'タ', name: 'タ', phonetics: {'latin': 'ta'}),
  AlphabetEntry(char: 'チ', name: 'チ', phonetics: {'latin': 'chi'}),
  AlphabetEntry(char: 'ツ', name: 'ツ', phonetics: {'latin': 'tsu'}),
  AlphabetEntry(char: 'テ', name: 'テ', phonetics: {'latin': 'te'}),
  AlphabetEntry(char: 'ト', name: 'ト', phonetics: {'latin': 'to'}),
  AlphabetEntry(char: 'ナ', name: 'ナ', phonetics: {'latin': 'na'}),
  AlphabetEntry(char: 'ニ', name: 'ニ', phonetics: {'latin': 'ni'}),
  AlphabetEntry(char: 'ヌ', name: 'ヌ', phonetics: {'latin': 'nu'}),
  AlphabetEntry(char: 'ネ', name: 'ネ', phonetics: {'latin': 'ne'}),
  AlphabetEntry(char: 'ノ', name: 'ノ', phonetics: {'latin': 'no'}),
  AlphabetEntry(char: 'ハ', name: 'ハ', phonetics: {'latin': 'ha'}),
  AlphabetEntry(char: 'ヒ', name: 'ヒ', phonetics: {'latin': 'hi'}),
  AlphabetEntry(char: 'フ', name: 'フ', phonetics: {'latin': 'fu'}),
  AlphabetEntry(char: 'ヘ', name: 'ヘ', phonetics: {'latin': 'he'}),
  AlphabetEntry(char: 'ホ', name: 'ホ', phonetics: {'latin': 'ho'}),
  AlphabetEntry(char: 'マ', name: 'マ', phonetics: {'latin': 'ma'}),
  AlphabetEntry(char: 'ミ', name: 'ミ', phonetics: {'latin': 'mi'}),
  AlphabetEntry(char: 'ム', name: 'ム', phonetics: {'latin': 'mu'}),
  AlphabetEntry(char: 'メ', name: 'メ', phonetics: {'latin': 'me'}),
  AlphabetEntry(char: 'モ', name: 'モ', phonetics: {'latin': 'mo'}),
  AlphabetEntry(char: 'ヤ', name: 'ヤ', phonetics: {'latin': 'ya'}),
  AlphabetEntry(char: 'ユ', name: 'ユ', phonetics: {'latin': 'yu'}),
  AlphabetEntry(char: 'ヨ', name: 'ヨ', phonetics: {'latin': 'yo'}),
  AlphabetEntry(char: 'ラ', name: 'ラ', phonetics: {'latin': 'ra'}),
  AlphabetEntry(char: 'リ', name: 'リ', phonetics: {'latin': 'ri'}),
  AlphabetEntry(char: 'ル', name: 'ル', phonetics: {'latin': 'ru'}),
  AlphabetEntry(char: 'レ', name: 'レ', phonetics: {'latin': 're'}),
  AlphabetEntry(char: 'ロ', name: 'ロ', phonetics: {'latin': 'ro'}),
  AlphabetEntry(char: 'ワ', name: 'ワ', phonetics: {'latin': 'wa'}),
  AlphabetEntry(char: 'ヲ', name: 'ヲ', phonetics: {'latin': 'wo'}),
  AlphabetEntry(char: 'ン', name: 'ン', phonetics: {'latin': 'n'}),
];

const _japanese = LanguageAlphabet(
  targetCode: 'ja',
  ttsLocale: 'ja-JP',
  nativeName: '五十音',
  groups: [
    AlphabetGroup(label: 'ひらがな', entries: _hiragana),
    AlphabetGroup(label: 'カタカナ', entries: _katakana),
  ],
);

// ── Korean ────────────────────────────────────────────────────────────────────

const _koreanConsonants = <AlphabetEntry>[
  AlphabetEntry(char: 'ㄱ', name: '기역',   phonetics: {'latin': 'g/k'},  ttsText: '가, 아가'),
  AlphabetEntry(char: 'ㄴ', name: '니은',   phonetics: {'latin': 'n'},    ttsText: '나, 아나'),
  AlphabetEntry(char: 'ㄷ', name: '디귿',   phonetics: {'latin': 'd/t'},  ttsText: '다, 아다'),
  AlphabetEntry(char: 'ㄹ', name: '리을',   phonetics: {'latin': 'r/l'},  ttsText: '라, 아라'),
  AlphabetEntry(char: 'ㅁ', name: '미음',   phonetics: {'latin': 'm'},    ttsText: '마, 아마'),
  AlphabetEntry(char: 'ㅂ', name: '비읍',   phonetics: {'latin': 'b/p'},  ttsText: '바, 아바'),
  AlphabetEntry(char: 'ㅅ', name: '시옷',   phonetics: {'latin': 's'},    ttsText: '사, 아사'),
  AlphabetEntry(char: 'ㅇ', name: '이응',   phonetics: {'latin': 'ng/-'}, ttsText: '아'),
  AlphabetEntry(char: 'ㅈ', name: '지읒',   phonetics: {'latin': 'j'},    ttsText: '자, 아자'),
  AlphabetEntry(char: 'ㅊ', name: '치읓',   phonetics: {'latin': 'ch'},   ttsText: '차, 아차'),
  AlphabetEntry(char: 'ㅋ', name: '키읔',   phonetics: {'latin': 'k'},    ttsText: '카, 아카'),
  AlphabetEntry(char: 'ㅌ', name: '티읕',   phonetics: {'latin': 't'},    ttsText: '타, 아타'),
  AlphabetEntry(char: 'ㅍ', name: '피읖',   phonetics: {'latin': 'p'},    ttsText: '파, 아파'),
  AlphabetEntry(char: 'ㅎ', name: '히읗',   phonetics: {'latin': 'h'},    ttsText: '하, 아하'),
  AlphabetEntry(char: 'ㄲ', name: '쌍기역', phonetics: {'latin': 'kk'},   ttsText: '까, 아까'),
  AlphabetEntry(char: 'ㄸ', name: '쌍디귿', phonetics: {'latin': 'tt'},   ttsText: '따, 아따'),
  AlphabetEntry(char: 'ㅃ', name: '쌍비읍', phonetics: {'latin': 'pp'},   ttsText: '빠, 아빠'),
  AlphabetEntry(char: 'ㅆ', name: '쌍시옷', phonetics: {'latin': 'ss'},   ttsText: '싸, 아싸'),
  AlphabetEntry(char: 'ㅉ', name: '쌍지읒', phonetics: {'latin': 'jj'},   ttsText: '짜, 아짜'),
];

const _koreanVowels = <AlphabetEntry>[
  AlphabetEntry(char: 'ㅏ', name: '아', phonetics: {'latin': 'a'}),
  AlphabetEntry(char: 'ㅐ', name: '애', phonetics: {'latin': 'ae'}),
  AlphabetEntry(char: 'ㅑ', name: '야', phonetics: {'latin': 'ya'}),
  AlphabetEntry(char: 'ㅒ', name: '얘', phonetics: {'latin': 'yae'}),
  AlphabetEntry(char: 'ㅓ', name: '어', phonetics: {'latin': 'eo'}),
  AlphabetEntry(char: 'ㅔ', name: '에', phonetics: {'latin': 'e'}),
  AlphabetEntry(char: 'ㅕ', name: '여', phonetics: {'latin': 'yeo'}),
  AlphabetEntry(char: 'ㅖ', name: '예', phonetics: {'latin': 'ye'}),
  AlphabetEntry(char: 'ㅗ', name: '오', phonetics: {'latin': 'o'}),
  AlphabetEntry(char: 'ㅛ', name: '요', phonetics: {'latin': 'yo'}),
  AlphabetEntry(char: 'ㅜ', name: '우', phonetics: {'latin': 'u'}),
  AlphabetEntry(char: 'ㅠ', name: '유', phonetics: {'latin': 'yu'}),
  AlphabetEntry(char: 'ㅡ', name: '으', phonetics: {'latin': 'eu'}),
  AlphabetEntry(char: 'ㅣ', name: '이', phonetics: {'latin': 'i'}),
];

const _korean = LanguageAlphabet(
  targetCode: 'ko',
  ttsLocale: 'ko-KR',
  nativeName: '한글',
  groups: [
    AlphabetGroup(label: '자음', entries: _koreanConsonants),
    AlphabetGroup(label: '모음', entries: _koreanVowels),
  ],
);

// ── Arabic ────────────────────────────────────────────────────────────────────

const _arabicLetters = <AlphabetEntry>[
  AlphabetEntry(char: 'ا', name: 'ألف', phonetics: {'latin': 'a/ā'},                         ttsText: 'آ'),
  AlphabetEntry(char: 'ب', name: 'باء', phonetics: {'latin': 'b'},                            ttsText: 'با، أبا'),
  AlphabetEntry(char: 'ت', name: 'تاء', phonetics: {'latin': 't'},                            ttsText: 'تا، أتا'),
  AlphabetEntry(char: 'ث', name: 'ثاء', phonetics: {'latin': 'th', 'en': 'th(ink)'},         ttsText: 'ثا، أثا'),
  AlphabetEntry(char: 'ج', name: 'جيم', phonetics: {'latin': 'j', 'en': 'j'},                ttsText: 'جا، أجا'),
  AlphabetEntry(char: 'ح', name: 'حاء', phonetics: {'latin': 'ḥ', 'en': 'h (deep)'},        ttsText: 'حا، أحا'),
  AlphabetEntry(char: 'خ', name: 'خاء', phonetics: {'latin': 'kh', 'pl': 'ch', 'de': 'ch'}, ttsText: 'خا، أخا'),
  AlphabetEntry(char: 'د', name: 'دال', phonetics: {'latin': 'd'},                            ttsText: 'دا، أدا'),
  AlphabetEntry(char: 'ذ', name: 'ذال', phonetics: {'latin': 'dh', 'en': 'th(e)'},           ttsText: 'ذا، أذا'),
  AlphabetEntry(char: 'ر', name: 'راء', phonetics: {'latin': 'r'},                            ttsText: 'را، أرا'),
  AlphabetEntry(char: 'ز', name: 'زاي', phonetics: {'latin': 'z'},                            ttsText: 'زا، أزا'),
  AlphabetEntry(char: 'س', name: 'سين', phonetics: {'latin': 's'},                            ttsText: 'سا، أسا'),
  AlphabetEntry(char: 'ش', name: 'شين', phonetics: {'latin': 'sh', 'pl': 'sz', 'de': 'sch'}, ttsText: 'شا، أشا'),
  AlphabetEntry(char: 'ص', name: 'صاد', phonetics: {'latin': 'ṣ', 'en': 's (emph.)'},       ttsText: 'صا، أصا'),
  AlphabetEntry(char: 'ض', name: 'ضاد', phonetics: {'latin': 'ḍ', 'en': 'd (emph.)'},       ttsText: 'ضا، أضا'),
  AlphabetEntry(char: 'ط', name: 'طاء', phonetics: {'latin': 'ṭ', 'en': 't (emph.)'},       ttsText: 'طا، أطا'),
  AlphabetEntry(char: 'ظ', name: 'ظاء', phonetics: {'latin': 'ẓ', 'en': 'dh (emph.)'},      ttsText: 'ظا، أظا'),
  AlphabetEntry(char: 'ع', name: 'عين', phonetics: {'latin': 'ʿ', 'en': '(glottal)'},        ttsText: 'عا، أعا'),
  AlphabetEntry(char: 'غ', name: 'غين', phonetics: {'latin': 'gh', 'en': 'gh (French r)'},   ttsText: 'غا، أغا'),
  AlphabetEntry(char: 'ف', name: 'فاء', phonetics: {'latin': 'f'},                            ttsText: 'فا، أفا'),
  AlphabetEntry(char: 'ق', name: 'قاف', phonetics: {'latin': 'q', 'en': 'q (deep k)'},       ttsText: 'قا، أقا'),
  AlphabetEntry(char: 'ك', name: 'كاف', phonetics: {'latin': 'k'},                            ttsText: 'كا، أكا'),
  AlphabetEntry(char: 'ل', name: 'لام', phonetics: {'latin': 'l'},                            ttsText: 'لا، ألا'),
  AlphabetEntry(char: 'م', name: 'ميم', phonetics: {'latin': 'm'},                            ttsText: 'ما، أما'),
  AlphabetEntry(char: 'ن', name: 'نون', phonetics: {'latin': 'n'},                            ttsText: 'نا، أنا'),
  AlphabetEntry(char: 'ه', name: 'هاء', phonetics: {'latin': 'h'},                            ttsText: 'ها، أها'),
  AlphabetEntry(char: 'و', name: 'واو', phonetics: {'latin': 'w/ū'},                          ttsText: 'وا، أوا'),
  AlphabetEntry(char: 'ي', name: 'ياء', phonetics: {'latin': 'y/ī'},                          ttsText: 'يا، أيا'),
];

const _arabic = LanguageAlphabet(
  targetCode: 'ar',
  ttsLocale: 'ar-SA',
  nativeName: 'الأبجدية',
  groups: [AlphabetGroup(label: 'الحروف', entries: _arabicLetters)],
);

// ── Hindi / Devanagari ────────────────────────────────────────────────────────

const _hindiVowels = <AlphabetEntry>[
  AlphabetEntry(char: 'अ', name: 'अ', phonetics: {'latin': 'a'}),
  AlphabetEntry(char: 'आ', name: 'आ', phonetics: {'latin': 'aa'}),
  AlphabetEntry(char: 'इ', name: 'इ', phonetics: {'latin': 'i'}),
  AlphabetEntry(char: 'ई', name: 'ई', phonetics: {'latin': 'ii'}),
  AlphabetEntry(char: 'उ', name: 'उ', phonetics: {'latin': 'u'}),
  AlphabetEntry(char: 'ऊ', name: 'ऊ', phonetics: {'latin': 'uu'}),
  AlphabetEntry(char: 'ए', name: 'ए', phonetics: {'latin': 'e'}),
  AlphabetEntry(char: 'ऐ', name: 'ऐ', phonetics: {'latin': 'ai'}),
  AlphabetEntry(char: 'ओ', name: 'ओ', phonetics: {'latin': 'o'}),
  AlphabetEntry(char: 'औ', name: 'औ', phonetics: {'latin': 'au'}),
];

const _hindiConsonants = <AlphabetEntry>[
  AlphabetEntry(char: 'क', name: 'क', phonetics: {'latin': 'ka'}),
  AlphabetEntry(char: 'ख', name: 'ख', phonetics: {'latin': 'kha'}),
  AlphabetEntry(char: 'ग', name: 'ग', phonetics: {'latin': 'ga'}),
  AlphabetEntry(char: 'घ', name: 'घ', phonetics: {'latin': 'gha'}),
  AlphabetEntry(char: 'च', name: 'च', phonetics: {'latin': 'cha'}),
  AlphabetEntry(char: 'छ', name: 'छ', phonetics: {'latin': 'chha'}),
  AlphabetEntry(char: 'ज', name: 'ज', phonetics: {'latin': 'ja'}),
  AlphabetEntry(char: 'झ', name: 'झ', phonetics: {'latin': 'jha'}),
  AlphabetEntry(char: 'ट', name: 'ट', phonetics: {'latin': 'ṭa'}),
  AlphabetEntry(char: 'ठ', name: 'ठ', phonetics: {'latin': 'ṭha'}),
  AlphabetEntry(char: 'ड', name: 'ड', phonetics: {'latin': 'ḍa'}),
  AlphabetEntry(char: 'ढ', name: 'ढ', phonetics: {'latin': 'ḍha'}),
  AlphabetEntry(char: 'त', name: 'त', phonetics: {'latin': 'ta'}),
  AlphabetEntry(char: 'थ', name: 'थ', phonetics: {'latin': 'tha'}),
  AlphabetEntry(char: 'द', name: 'द', phonetics: {'latin': 'da'}),
  AlphabetEntry(char: 'ध', name: 'ध', phonetics: {'latin': 'dha'}),
  AlphabetEntry(char: 'न', name: 'न', phonetics: {'latin': 'na'}),
  AlphabetEntry(char: 'प', name: 'प', phonetics: {'latin': 'pa'}),
  AlphabetEntry(char: 'फ', name: 'फ', phonetics: {'latin': 'pha'}),
  AlphabetEntry(char: 'ब', name: 'ब', phonetics: {'latin': 'ba'}),
  AlphabetEntry(char: 'भ', name: 'भ', phonetics: {'latin': 'bha'}),
  AlphabetEntry(char: 'म', name: 'म', phonetics: {'latin': 'ma'}),
  AlphabetEntry(char: 'य', name: 'य', phonetics: {'latin': 'ya'}),
  AlphabetEntry(char: 'र', name: 'र', phonetics: {'latin': 'ra'}),
  AlphabetEntry(char: 'ल', name: 'ल', phonetics: {'latin': 'la'}),
  AlphabetEntry(char: 'व', name: 'व', phonetics: {'latin': 'va'}),
  AlphabetEntry(char: 'श', name: 'श', phonetics: {'latin': 'sha'}),
  AlphabetEntry(char: 'ष', name: 'ष', phonetics: {'latin': 'ṣha'}),
  AlphabetEntry(char: 'स', name: 'स', phonetics: {'latin': 'sa'}),
  AlphabetEntry(char: 'ह', name: 'ह', phonetics: {'latin': 'ha'}),
];

const _hindi = LanguageAlphabet(
  targetCode: 'hi',
  ttsLocale: 'hi-IN',
  nativeName: 'वर्णमाला',
  groups: [
    AlphabetGroup(label: 'स्वर', entries: _hindiVowels),
    AlphabetGroup(label: 'व्यंजन', entries: _hindiConsonants),
  ],
);

// ── English ───────────────────────────────────────────────────────────────────

const _englishLetters = <AlphabetEntry>[
  AlphabetEntry(char: 'A', name: 'ay',       phonetics: {'latin': 'ay', 'pl': 'ej', 'ru': 'эй'},        ttsText: 'a'),
  AlphabetEntry(char: 'B', name: 'bee',      phonetics: {'latin': 'bi', 'pl': 'bi', 'ru': 'би'},        ttsText: 'ba, aba'),
  AlphabetEntry(char: 'C', name: 'see',      phonetics: {'latin': 'si/k', 'pl': 'si/k', 'ru': 'си/к'}, ttsText: 'ka, aka'),
  AlphabetEntry(char: 'D', name: 'dee',      phonetics: {'latin': 'di', 'pl': 'di'},                   ttsText: 'da, ada'),
  AlphabetEntry(char: 'E', name: 'ee',       phonetics: {'latin': 'ee', 'pl': 'ii', 'ru': 'и'},         ttsText: 'e'),
  AlphabetEntry(char: 'F', name: 'ef',       phonetics: {'latin': 'ef', 'pl': 'ef'},                   ttsText: 'fa, afa'),
  AlphabetEntry(char: 'G', name: 'jee',      phonetics: {'latin': 'dżi', 'pl': 'dżi', 'ru': 'джи'},    ttsText: 'ga, aga'),
  AlphabetEntry(char: 'H', name: 'aitch',    phonetics: {'latin': 'ejcz', 'pl': 'ejcz', 'ru': 'эйч'},  ttsText: 'ha, aha'),
  AlphabetEntry(char: 'I', name: 'eye',      phonetics: {'latin': 'aj', 'pl': 'aj', 'ru': 'ай'},        ttsText: 'i'),
  AlphabetEntry(char: 'J', name: 'jay',      phonetics: {'latin': 'dżej', 'pl': 'dżej', 'ru': 'джей'}, ttsText: 'ja, aja'),
  AlphabetEntry(char: 'K', name: 'kay',      phonetics: {'latin': 'kej', 'pl': 'kej'},                 ttsText: 'ka, aka'),
  AlphabetEntry(char: 'L', name: 'el',       phonetics: {'latin': 'el', 'pl': 'el'},                   ttsText: 'la, ala'),
  AlphabetEntry(char: 'M', name: 'em',       phonetics: {'latin': 'em', 'pl': 'em'},                   ttsText: 'ma, ama'),
  AlphabetEntry(char: 'N', name: 'en',       phonetics: {'latin': 'en', 'pl': 'en'},                   ttsText: 'na, ana'),
  AlphabetEntry(char: 'O', name: 'oh',       phonetics: {'latin': 'ou', 'pl': 'ou', 'ru': 'оу'},        ttsText: 'o'),
  AlphabetEntry(char: 'P', name: 'pee',      phonetics: {'latin': 'pi', 'pl': 'pi'},                   ttsText: 'pa, apa'),
  AlphabetEntry(char: 'Q', name: 'cue',      phonetics: {'latin': 'kju', 'pl': 'kju'},                 ttsText: 'kwa, akwa'),
  AlphabetEntry(char: 'R', name: 'ar',       phonetics: {'latin': 'ar', 'pl': 'ar'},                   ttsText: 'ra, ara'),
  AlphabetEntry(char: 'S', name: 'ess',      phonetics: {'latin': 'es', 'pl': 'es'},                   ttsText: 'sa, asa'),
  AlphabetEntry(char: 'T', name: 'tee',      phonetics: {'latin': 'ti', 'pl': 'ti'},                   ttsText: 'ta, ata'),
  AlphabetEntry(char: 'U', name: 'you',      phonetics: {'latin': 'ju', 'pl': 'ju', 'ru': 'ю'},         ttsText: 'u'),
  AlphabetEntry(char: 'V', name: 'vee',      phonetics: {'latin': 'vi', 'pl': 'vi'},                   ttsText: 'va, ava'),
  AlphabetEntry(char: 'W', name: 'double-u', phonetics: {'latin': 'dablju', 'pl': 'dabljuu', 'ru': 'дабл-ю'}, ttsText: 'wa, awa'),
  AlphabetEntry(char: 'X', name: 'ex',       phonetics: {'latin': 'eks', 'pl': 'eks'},                 ttsText: 'ksa, aksa'),
  AlphabetEntry(char: 'Y', name: 'why',      phonetics: {'latin': 'uaj', 'pl': 'uaj', 'ru': 'уай'},    ttsText: 'ya, aya'),
  AlphabetEntry(char: 'Z', name: 'zee',      phonetics: {'latin': 'zi', 'pl': 'zi', 'ru': 'зи'},       ttsText: 'za, aza'),
];

const _english = LanguageAlphabet(
  targetCode: 'en',
  ttsLocale: 'en-US',
  nativeName: 'Alphabet',
  groups: [AlphabetGroup(label: 'Alphabet', entries: _englishLetters)],
);

// ── Polish ────────────────────────────────────────────────────────────────────

const _polishLetters = <AlphabetEntry>[
  AlphabetEntry(char: 'A', name: 'a',            phonetics: {'latin': 'a', 'ru': 'а'},                         ttsText: 'a'),
  AlphabetEntry(char: 'Ą', name: 'ą',            phonetics: {'latin': 'on', 'en': 'on (nasal)', 'ru': 'он (носов.)'}, ttsText: 'ą'),
  AlphabetEntry(char: 'B', name: 'be',           phonetics: {'latin': 'b', 'ru': 'б'},                         ttsText: 'ba, aba'),
  AlphabetEntry(char: 'C', name: 'ce',           phonetics: {'latin': 'ts', 'en': 'ts', 'ru': 'ц'},            ttsText: 'ca, aca'),
  AlphabetEntry(char: 'Ć', name: 'cie',          phonetics: {'latin': 'ch\'', 'en': 'ch (soft)', 'ru': 'чь'},  ttsText: 'cia, acia'),
  AlphabetEntry(char: 'D', name: 'de',           phonetics: {'latin': 'd', 'ru': 'д'},                         ttsText: 'da, ada'),
  AlphabetEntry(char: 'E', name: 'e',            phonetics: {'latin': 'e', 'ru': 'э'},                         ttsText: 'e'),
  AlphabetEntry(char: 'Ę', name: 'ę',            phonetics: {'latin': 'en', 'en': 'en (nasal)', 'ru': 'эн (носов.)'}, ttsText: 'ę'),
  AlphabetEntry(char: 'F', name: 'ef',           phonetics: {'latin': 'f', 'ru': 'ф'},                         ttsText: 'fa, afa'),
  AlphabetEntry(char: 'G', name: 'gie',          phonetics: {'latin': 'g', 'ru': 'г'},                         ttsText: 'ga, aga'),
  AlphabetEntry(char: 'H', name: 'ha',           phonetics: {'latin': 'h', 'ru': 'х'},                         ttsText: 'ha, aha'),
  AlphabetEntry(char: 'I', name: 'i',            phonetics: {'latin': 'ee', 'ru': 'и'},                        ttsText: 'i'),
  AlphabetEntry(char: 'J', name: 'jot',          phonetics: {'latin': 'y', 'en': 'y (yes)', 'ru': 'й'},        ttsText: 'ja, aja'),
  AlphabetEntry(char: 'K', name: 'ka',           phonetics: {'latin': 'k', 'ru': 'к'},                         ttsText: 'ka, aka'),
  AlphabetEntry(char: 'L', name: 'el',           phonetics: {'latin': 'l', 'ru': 'л'},                         ttsText: 'la, ala'),
  AlphabetEntry(char: 'Ł', name: 'eł',           phonetics: {'latin': 'w', 'en': 'w (win)', 'ru': 'в'},        ttsText: 'ła, ała'),
  AlphabetEntry(char: 'M', name: 'em',           phonetics: {'latin': 'm', 'ru': 'м'},                         ttsText: 'ma, ama'),
  AlphabetEntry(char: 'N', name: 'en',           phonetics: {'latin': 'n', 'ru': 'н'},                         ttsText: 'na, ana'),
  AlphabetEntry(char: 'Ń', name: 'eń',           phonetics: {'latin': 'ny', 'en': 'ny (canyon)', 'ru': 'нь'}, ttsText: 'nia, ania'),
  AlphabetEntry(char: 'O', name: 'o',            phonetics: {'latin': 'o', 'ru': 'о'},                         ttsText: 'o'),
  AlphabetEntry(char: 'Ó', name: 'o kreskowane', phonetics: {'latin': 'oo', 'en': 'oo (boot)', 'ru': 'у'},     ttsText: 'ó'),
  AlphabetEntry(char: 'P', name: 'pe',           phonetics: {'latin': 'p', 'ru': 'п'},                         ttsText: 'pa, apa'),
  AlphabetEntry(char: 'R', name: 'er',           phonetics: {'latin': 'r', 'ru': 'р'},                         ttsText: 'ra, ara'),
  AlphabetEntry(char: 'S', name: 'es',           phonetics: {'latin': 's', 'ru': 'с'},                         ttsText: 'sa, asa'),
  AlphabetEntry(char: 'Ś', name: 'eś',           phonetics: {'latin': 'sh\'', 'en': 'sh (soft)', 'ru': 'шь'}, ttsText: 'sia, asia'),
  AlphabetEntry(char: 'T', name: 'te',           phonetics: {'latin': 't', 'ru': 'т'},                         ttsText: 'ta, ata'),
  AlphabetEntry(char: 'U', name: 'u',            phonetics: {'latin': 'oo', 'en': 'oo (boot)', 'ru': 'у'},     ttsText: 'u'),
  AlphabetEntry(char: 'W', name: 'wu',           phonetics: {'latin': 'v', 'en': 'v (van)', 'ru': 'в'},        ttsText: 'wa, awa'),
  AlphabetEntry(char: 'Y', name: 'igrek',        phonetics: {'latin': 'uh', 'en': 'uh (bit)', 'ru': 'ы'},      ttsText: 'y'),
  AlphabetEntry(char: 'Z', name: 'zet',          phonetics: {'latin': 'z', 'ru': 'з'},                         ttsText: 'za, aza'),
  AlphabetEntry(char: 'Ź', name: 'ziet',         phonetics: {'latin': 'zh\'', 'en': 'zh (soft)', 'ru': 'жь'}, ttsText: 'zia, azia'),
  AlphabetEntry(char: 'Ż', name: 'żet',          phonetics: {'latin': 'zh', 'en': 'zh (measure)', 'ru': 'ж'}, ttsText: 'ża, aża'),
];

const _polish = LanguageAlphabet(
  targetCode: 'pl',
  ttsLocale: 'pl-PL',
  nativeName: 'Alfabet',
  groups: [AlphabetGroup(label: 'Alfabet', entries: _polishLetters)],
);

// ── German ────────────────────────────────────────────────────────────────────

const _germanLetters = <AlphabetEntry>[
  AlphabetEntry(char: 'A', name: 'a',       phonetics: {'latin': 'a'},                                    ttsText: 'a'),
  AlphabetEntry(char: 'Ä', name: 'ä',       phonetics: {'latin': 'ae', 'en': 'ae (air)', 'pl': 'e (otwarte)'}, ttsText: 'ä'),
  AlphabetEntry(char: 'B', name: 'be',      phonetics: {'latin': 'b'},                                    ttsText: 'ba, aba'),
  AlphabetEntry(char: 'C', name: 'tse',     phonetics: {'latin': 'ts/k'},                                 ttsText: 'ca, aca'),
  AlphabetEntry(char: 'D', name: 'de',      phonetics: {'latin': 'd'},                                    ttsText: 'da, ada'),
  AlphabetEntry(char: 'E', name: 'e',       phonetics: {'latin': 'e'},                                    ttsText: 'e'),
  AlphabetEntry(char: 'F', name: 'ef',      phonetics: {'latin': 'f'},                                    ttsText: 'fa, afa'),
  AlphabetEntry(char: 'G', name: 'ge',      phonetics: {'latin': 'g', 'en': 'g (go)'},                   ttsText: 'ga, aga'),
  AlphabetEntry(char: 'H', name: 'ha',      phonetics: {'latin': 'h'},                                    ttsText: 'ha, aha'),
  AlphabetEntry(char: 'I', name: 'i',       phonetics: {'latin': 'i', 'en': 'ee'},                       ttsText: 'i'),
  AlphabetEntry(char: 'J', name: 'jot',     phonetics: {'latin': 'y', 'en': 'y (yes)', 'pl': 'j'},       ttsText: 'ja, aja'),
  AlphabetEntry(char: 'K', name: 'ka',      phonetics: {'latin': 'k'},                                    ttsText: 'ka, aka'),
  AlphabetEntry(char: 'L', name: 'el',      phonetics: {'latin': 'l'},                                    ttsText: 'la, ala'),
  AlphabetEntry(char: 'M', name: 'em',      phonetics: {'latin': 'm'},                                    ttsText: 'ma, ama'),
  AlphabetEntry(char: 'N', name: 'en',      phonetics: {'latin': 'n'},                                    ttsText: 'na, ana'),
  AlphabetEntry(char: 'O', name: 'o',       phonetics: {'latin': 'o'},                                    ttsText: 'o'),
  AlphabetEntry(char: 'Ö', name: 'ö',       phonetics: {'latin': 'oe', 'en': 'ur (bird)', 'pl': 'eu (zaokr.)'}, ttsText: 'ö'),
  AlphabetEntry(char: 'P', name: 'pe',      phonetics: {'latin': 'p'},                                    ttsText: 'pa, apa'),
  AlphabetEntry(char: 'Q', name: 'ku',      phonetics: {'latin': 'kv'},                                   ttsText: 'kwa, akwa'),
  AlphabetEntry(char: 'R', name: 'er',      phonetics: {'latin': 'r (uvular)'},                           ttsText: 'ra, ara'),
  AlphabetEntry(char: 'S', name: 'es',      phonetics: {'latin': 'z/s', 'en': 'z (before vowel)'},       ttsText: 'sa, asa'),
  AlphabetEntry(char: 'ß', name: 'eszett',  phonetics: {'latin': 'ss', 'pl': 'ss'},                      ttsText: 'ßa, aßa'),
  AlphabetEntry(char: 'T', name: 'te',      phonetics: {'latin': 't'},                                    ttsText: 'ta, ata'),
  AlphabetEntry(char: 'U', name: 'u',       phonetics: {'latin': 'oo', 'en': 'oo (boot)'},               ttsText: 'u'),
  AlphabetEntry(char: 'Ü', name: 'ü',       phonetics: {'latin': 'ue', 'en': 'ue (no eng.)', 'pl': 'u (zaokr.)'}, ttsText: 'ü'),
  AlphabetEntry(char: 'V', name: 've',      phonetics: {'latin': 'f', 'en': 'f (van→fan)', 'pl': 'f'},   ttsText: 'va, ava'),
  AlphabetEntry(char: 'W', name: 'we',      phonetics: {'latin': 'v', 'en': 'v (van)', 'pl': 'w'},       ttsText: 'wa, awa'),
  AlphabetEntry(char: 'X', name: 'iks',     phonetics: {'latin': 'ks'},                                   ttsText: 'ksa, aksa'),
  AlphabetEntry(char: 'Y', name: 'ypsilon', phonetics: {'latin': 'ue/i'},                                 ttsText: 'y'),
  AlphabetEntry(char: 'Z', name: 'tsett',   phonetics: {'latin': 'ts', 'en': 'ts (pizza)', 'pl': 'c'},   ttsText: 'za, aza'),
];

const _german = LanguageAlphabet(
  targetCode: 'de',
  ttsLocale: 'de-DE',
  nativeName: 'Alphabet',
  groups: [AlphabetGroup(label: 'Alphabet', entries: _germanLetters)],
);

// ── Spanish ───────────────────────────────────────────────────────────────────

const _spanishLetters = <AlphabetEntry>[
  AlphabetEntry(char: 'A', name: 'a',        phonetics: {'latin': 'a'},                                    ttsText: 'a'),
  AlphabetEntry(char: 'B', name: 'be',       phonetics: {'latin': 'b/v', 'en': 'b≈v'},                   ttsText: 'ba, aba'),
  AlphabetEntry(char: 'C', name: 'ce',       phonetics: {'latin': 's/k', 'en': 's(e/i) k(a/o)'},         ttsText: 'ca, aca'),
  AlphabetEntry(char: 'D', name: 'de',       phonetics: {'latin': 'd'},                                    ttsText: 'da, ada'),
  AlphabetEntry(char: 'E', name: 'e',        phonetics: {'latin': 'e'},                                    ttsText: 'e'),
  AlphabetEntry(char: 'F', name: 'efe',      phonetics: {'latin': 'f'},                                    ttsText: 'fa, afa'),
  AlphabetEntry(char: 'G', name: 'ge',       phonetics: {'latin': 'g/h', 'en': 'g(a/o) h(e/i)'},         ttsText: 'ga, aga'),
  AlphabetEntry(char: 'H', name: 'hache',    phonetics: {'latin': '-', 'en': 'silent'},                   ttsText: 'ha, aha'),
  AlphabetEntry(char: 'I', name: 'i',        phonetics: {'latin': 'ee', 'en': 'ee (see)'},                ttsText: 'i'),
  AlphabetEntry(char: 'J', name: 'jota',     phonetics: {'latin': 'h', 'en': 'h (hard)', 'pl': 'ch (gardłowe)'}, ttsText: 'ja, aja'),
  AlphabetEntry(char: 'K', name: 'ka',       phonetics: {'latin': 'k'},                                    ttsText: 'ka, aka'),
  AlphabetEntry(char: 'L', name: 'ele',      phonetics: {'latin': 'l'},                                    ttsText: 'la, ala'),
  AlphabetEntry(char: 'M', name: 'eme',      phonetics: {'latin': 'm'},                                    ttsText: 'ma, ama'),
  AlphabetEntry(char: 'N', name: 'ene',      phonetics: {'latin': 'n'},                                    ttsText: 'na, ana'),
  AlphabetEntry(char: 'Ñ', name: 'eñe',      phonetics: {'latin': 'ny', 'en': 'ny (canyon)', 'pl': 'ń'}, ttsText: 'ña, aña'),
  AlphabetEntry(char: 'O', name: 'o',        phonetics: {'latin': 'o'},                                    ttsText: 'o'),
  AlphabetEntry(char: 'P', name: 'pe',       phonetics: {'latin': 'p'},                                    ttsText: 'pa, apa'),
  AlphabetEntry(char: 'Q', name: 'cu',       phonetics: {'latin': 'k'},                                    ttsText: 'ka, aka'),
  AlphabetEntry(char: 'R', name: 'erre',     phonetics: {'latin': 'r (rolled)'},                           ttsText: 'ra, ara'),
  AlphabetEntry(char: 'S', name: 'ese',      phonetics: {'latin': 's'},                                    ttsText: 'sa, asa'),
  AlphabetEntry(char: 'T', name: 'te',       phonetics: {'latin': 't'},                                    ttsText: 'ta, ata'),
  AlphabetEntry(char: 'U', name: 'u',        phonetics: {'latin': 'oo', 'en': 'oo (boot)'},               ttsText: 'u'),
  AlphabetEntry(char: 'V', name: 've',       phonetics: {'latin': 'b/v', 'en': 'b≈v'},                   ttsText: 'va, ava'),
  AlphabetEntry(char: 'W', name: 'doble ve', phonetics: {'latin': 'v/w'},                                  ttsText: 'wa, awa'),
  AlphabetEntry(char: 'X', name: 'equis',    phonetics: {'latin': 'ks/s/h'},                              ttsText: 'xa, axa'),
  AlphabetEntry(char: 'Y', name: 'ye',       phonetics: {'latin': 'y/ee', 'pl': 'j/i'},                   ttsText: 'ya, aya'),
  AlphabetEntry(char: 'Z', name: 'zeta',     phonetics: {'latin': 'th/s', 'en': 'th(ink) in Spain'},      ttsText: 'za, aza'),
];

const _spanish = LanguageAlphabet(
  targetCode: 'es',
  ttsLocale: 'es-ES',
  nativeName: 'Alfabeto',
  groups: [AlphabetGroup(label: 'Alfabeto', entries: _spanishLetters)],
);

// ── French ────────────────────────────────────────────────────────────────────

const _frenchBase = <AlphabetEntry>[
  AlphabetEntry(char: 'A', name: 'a',          phonetics: {'latin': 'a'},                                  ttsText: 'a'),
  AlphabetEntry(char: 'B', name: 'bé',         phonetics: {'latin': 'b'},                                  ttsText: 'ba, aba'),
  AlphabetEntry(char: 'C', name: 'cé',         phonetics: {'latin': 's/k'},                               ttsText: 'ca, aca'),
  AlphabetEntry(char: 'D', name: 'dé',         phonetics: {'latin': 'd'},                                  ttsText: 'da, ada'),
  AlphabetEntry(char: 'E', name: 'e',          phonetics: {'latin': 'e/uh'},                              ttsText: 'e'),
  AlphabetEntry(char: 'F', name: 'effe',       phonetics: {'latin': 'f'},                                  ttsText: 'fa, afa'),
  AlphabetEntry(char: 'G', name: 'gé',         phonetics: {'latin': 'g/zh', 'en': 'g(a) zh(e)'},         ttsText: 'ga, aga'),
  AlphabetEntry(char: 'H', name: 'ache',       phonetics: {'latin': '-', 'en': 'silent'},                 ttsText: 'ha, aha'),
  AlphabetEntry(char: 'I', name: 'i',          phonetics: {'latin': 'ee'},                                ttsText: 'i'),
  AlphabetEntry(char: 'J', name: 'ji',         phonetics: {'latin': 'zh', 'en': 'zh (measure)', 'pl': 'ż'}, ttsText: 'ja, aja'),
  AlphabetEntry(char: 'K', name: 'ka',         phonetics: {'latin': 'k'},                                  ttsText: 'ka, aka'),
  AlphabetEntry(char: 'L', name: 'elle',       phonetics: {'latin': 'l'},                                  ttsText: 'la, ala'),
  AlphabetEntry(char: 'M', name: 'emme',       phonetics: {'latin': 'm'},                                  ttsText: 'ma, ama'),
  AlphabetEntry(char: 'N', name: 'enne',       phonetics: {'latin': 'n'},                                  ttsText: 'na, ana'),
  AlphabetEntry(char: 'O', name: 'o',          phonetics: {'latin': 'o'},                                  ttsText: 'o'),
  AlphabetEntry(char: 'P', name: 'pé',         phonetics: {'latin': 'p'},                                  ttsText: 'pa, apa'),
  AlphabetEntry(char: 'Q', name: 'ku',         phonetics: {'latin': 'k'},                                  ttsText: 'ka, aka'),
  AlphabetEntry(char: 'R', name: 'erre',       phonetics: {'latin': 'r (uvular)', 'en': 'r (guttural)'}, ttsText: 'ra, ara'),
  AlphabetEntry(char: 'S', name: 'esse',       phonetics: {'latin': 's/z'},                               ttsText: 'sa, asa'),
  AlphabetEntry(char: 'T', name: 'té',         phonetics: {'latin': 't'},                                  ttsText: 'ta, ata'),
  AlphabetEntry(char: 'U', name: 'u',          phonetics: {'latin': 'ue', 'en': 'ue (no eng.)'},          ttsText: 'u'),
  AlphabetEntry(char: 'V', name: 'vé',         phonetics: {'latin': 'v'},                                  ttsText: 'va, ava'),
  AlphabetEntry(char: 'W', name: 'double vé',  phonetics: {'latin': 'v/w'},                               ttsText: 'wa, awa'),
  AlphabetEntry(char: 'X', name: 'iks',        phonetics: {'latin': 'ks/gz'},                             ttsText: 'xa, axa'),
  AlphabetEntry(char: 'Y', name: 'i grec',     phonetics: {'latin': 'ee/y'},                              ttsText: 'y'),
  AlphabetEntry(char: 'Z', name: 'zède',       phonetics: {'latin': 'z'},                                  ttsText: 'za, aza'),
];

const _frenchSpecial = <AlphabetEntry>[
  AlphabetEntry(char: 'É', name: 'é', phonetics: {'latin': 'ay', 'en': 'ay (play)'},  ttsText: 'é'),
  AlphabetEntry(char: 'È', name: 'è', phonetics: {'latin': 'eh', 'en': 'eh (bed)'},   ttsText: 'è'),
  AlphabetEntry(char: 'Ê', name: 'ê', phonetics: {'latin': 'eh'},                      ttsText: 'ê'),
  AlphabetEntry(char: 'À', name: 'à', phonetics: {'latin': 'a'},                       ttsText: 'à'),
  AlphabetEntry(char: 'Â', name: 'â', phonetics: {'latin': 'ah'},                      ttsText: 'â'),
  AlphabetEntry(char: 'Î', name: 'î', phonetics: {'latin': 'ee'},                      ttsText: 'î'),
  AlphabetEntry(char: 'Ô', name: 'ô', phonetics: {'latin': 'oh'},                      ttsText: 'ô'),
  AlphabetEntry(char: 'Ù', name: 'ù', phonetics: {'latin': 'ue'},                      ttsText: 'ù'),
  AlphabetEntry(char: 'Û', name: 'û', phonetics: {'latin': 'ue'},                      ttsText: 'û'),
  AlphabetEntry(char: 'Ç', name: 'ç', phonetics: {'latin': 's', 'pl': 's'},            ttsText: 'ça, aça'),
  AlphabetEntry(char: 'Œ', name: 'œ', phonetics: {'latin': 'ur', 'en': 'ur (fur)'},   ttsText: 'œ'),
  AlphabetEntry(char: 'Æ', name: 'æ', phonetics: {'latin': 'ae'},                      ttsText: 'æ'),
];

const _french = LanguageAlphabet(
  targetCode: 'fr',
  ttsLocale: 'fr-FR',
  nativeName: 'Alphabet',
  groups: [
    AlphabetGroup(label: 'Alphabet', entries: _frenchBase),
    AlphabetGroup(label: 'Accents', entries: _frenchSpecial),
  ],
);

// ── Italian ───────────────────────────────────────────────────────────────────

const _italianLetters = <AlphabetEntry>[
  AlphabetEntry(char: 'A', name: 'a',    phonetics: {'latin': 'a'},                                  ttsText: 'a'),
  AlphabetEntry(char: 'B', name: 'bi',   phonetics: {'latin': 'b'},                                  ttsText: 'ba, aba'),
  AlphabetEntry(char: 'C', name: 'ci',   phonetics: {'latin': 'ch/k', 'en': 'ch(e/i) k(a/o)'},     ttsText: 'ca, aca'),
  AlphabetEntry(char: 'D', name: 'di',   phonetics: {'latin': 'd'},                                  ttsText: 'da, ada'),
  AlphabetEntry(char: 'E', name: 'e',    phonetics: {'latin': 'e'},                                  ttsText: 'e'),
  AlphabetEntry(char: 'F', name: 'effe', phonetics: {'latin': 'f'},                                  ttsText: 'fa, afa'),
  AlphabetEntry(char: 'G', name: 'gi',   phonetics: {'latin': 'dj/g', 'en': 'j(e/i) g(a/o)'},      ttsText: 'ga, aga'),
  AlphabetEntry(char: 'H', name: 'acca', phonetics: {'latin': '-', 'en': 'silent'},                 ttsText: 'ha, aha'),
  AlphabetEntry(char: 'I', name: 'i',    phonetics: {'latin': 'ee'},                                ttsText: 'i'),
  AlphabetEntry(char: 'L', name: 'elle', phonetics: {'latin': 'l'},                                  ttsText: 'la, ala'),
  AlphabetEntry(char: 'M', name: 'emme', phonetics: {'latin': 'm'},                                  ttsText: 'ma, ama'),
  AlphabetEntry(char: 'N', name: 'enne', phonetics: {'latin': 'n'},                                  ttsText: 'na, ana'),
  AlphabetEntry(char: 'O', name: 'o',    phonetics: {'latin': 'o'},                                  ttsText: 'o'),
  AlphabetEntry(char: 'P', name: 'pi',   phonetics: {'latin': 'p'},                                  ttsText: 'pa, apa'),
  AlphabetEntry(char: 'Q', name: 'cu',   phonetics: {'latin': 'k'},                                  ttsText: 'ka, aka'),
  AlphabetEntry(char: 'R', name: 'erre', phonetics: {'latin': 'r (rolled)'},                         ttsText: 'ra, ara'),
  AlphabetEntry(char: 'S', name: 'esse', phonetics: {'latin': 's/z'},                               ttsText: 'sa, asa'),
  AlphabetEntry(char: 'T', name: 'ti',   phonetics: {'latin': 't'},                                  ttsText: 'ta, ata'),
  AlphabetEntry(char: 'U', name: 'u',    phonetics: {'latin': 'oo'},                                ttsText: 'u'),
  AlphabetEntry(char: 'V', name: 'vi',   phonetics: {'latin': 'v'},                                  ttsText: 'va, ava'),
  AlphabetEntry(char: 'Z', name: 'zeta', phonetics: {'latin': 'ts/dz', 'en': 'ts/dz'},              ttsText: 'za, aza'),
];

const _italian = LanguageAlphabet(
  targetCode: 'it',
  ttsLocale: 'it-IT',
  nativeName: 'Alfabeto',
  groups: [AlphabetGroup(label: 'Alfabeto', entries: _italianLetters)],
);

// ── Portuguese ────────────────────────────────────────────────────────────────

const _portugueseLetters = <AlphabetEntry>[
  AlphabetEntry(char: 'A', name: 'a',       phonetics: {'latin': 'a'},                                    ttsText: 'a'),
  AlphabetEntry(char: 'Á', name: 'á',       phonetics: {'latin': 'ah'},                                   ttsText: 'á'),
  AlphabetEntry(char: 'Â', name: 'â',       phonetics: {'latin': 'uh'},                                   ttsText: 'â'),
  AlphabetEntry(char: 'Ã', name: 'ã',       phonetics: {'latin': 'ung', 'en': 'ung (nasal)'},             ttsText: 'ã'),
  AlphabetEntry(char: 'B', name: 'bê',      phonetics: {'latin': 'b'},                                    ttsText: 'ba, aba'),
  AlphabetEntry(char: 'C', name: 'cê',      phonetics: {'latin': 's/k'},                                  ttsText: 'ca, aca'),
  AlphabetEntry(char: 'Ç', name: 'cedilha', phonetics: {'latin': 's', 'en': 's (always)'},               ttsText: 'ça, aça'),
  AlphabetEntry(char: 'D', name: 'dê',      phonetics: {'latin': 'd'},                                    ttsText: 'da, ada'),
  AlphabetEntry(char: 'E', name: 'e',       phonetics: {'latin': 'e/ee'},                                 ttsText: 'e'),
  AlphabetEntry(char: 'É', name: 'é',       phonetics: {'latin': 'eh'},                                   ttsText: 'é'),
  AlphabetEntry(char: 'Ê', name: 'ê',       phonetics: {'latin': 'e (closed)'},                           ttsText: 'ê'),
  AlphabetEntry(char: 'F', name: 'efe',     phonetics: {'latin': 'f'},                                    ttsText: 'fa, afa'),
  AlphabetEntry(char: 'G', name: 'gê',      phonetics: {'latin': 'g/zh'},                                 ttsText: 'ga, aga'),
  AlphabetEntry(char: 'H', name: 'agá',     phonetics: {'latin': '-', 'en': 'silent'},                   ttsText: 'ha, aha'),
  AlphabetEntry(char: 'I', name: 'i',       phonetics: {'latin': 'ee'},                                   ttsText: 'i'),
  AlphabetEntry(char: 'Í', name: 'í',       phonetics: {'latin': 'ee'},                                   ttsText: 'í'),
  AlphabetEntry(char: 'J', name: 'jota',    phonetics: {'latin': 'zh', 'en': 'zh (measure)', 'pl': 'ż'}, ttsText: 'ja, aja'),
  AlphabetEntry(char: 'L', name: 'ele',     phonetics: {'latin': 'l'},                                    ttsText: 'la, ala'),
  AlphabetEntry(char: 'M', name: 'eme',     phonetics: {'latin': 'm'},                                    ttsText: 'ma, ama'),
  AlphabetEntry(char: 'N', name: 'ene',     phonetics: {'latin': 'n'},                                    ttsText: 'na, ana'),
  AlphabetEntry(char: 'O', name: 'o',       phonetics: {'latin': 'o/oo'},                                 ttsText: 'o'),
  AlphabetEntry(char: 'Ó', name: 'ó',       phonetics: {'latin': 'oh'},                                   ttsText: 'ó'),
  AlphabetEntry(char: 'Ô', name: 'ô',       phonetics: {'latin': 'o (closed)'},                           ttsText: 'ô'),
  AlphabetEntry(char: 'Õ', name: 'õ',       phonetics: {'latin': 'ong', 'en': 'ong (nasal)'},             ttsText: 'õ'),
  AlphabetEntry(char: 'P', name: 'pê',      phonetics: {'latin': 'p'},                                    ttsText: 'pa, apa'),
  AlphabetEntry(char: 'R', name: 'erre',    phonetics: {'latin': 'r/h', 'en': 'r or h (initial)'},       ttsText: 'ra, ara'),
  AlphabetEntry(char: 'S', name: 'esse',    phonetics: {'latin': 's/z/sh'},                              ttsText: 'sa, asa'),
  AlphabetEntry(char: 'T', name: 'tê',      phonetics: {'latin': 't'},                                    ttsText: 'ta, ata'),
  AlphabetEntry(char: 'U', name: 'u',       phonetics: {'latin': 'oo'},                                   ttsText: 'u'),
  AlphabetEntry(char: 'Ú', name: 'ú',       phonetics: {'latin': 'oo'},                                   ttsText: 'ú'),
  AlphabetEntry(char: 'V', name: 'vê',      phonetics: {'latin': 'v'},                                    ttsText: 'va, ava'),
  AlphabetEntry(char: 'X', name: 'xis',     phonetics: {'latin': 'sh/ks/z/s'},                           ttsText: 'xa, axa'),
  AlphabetEntry(char: 'Z', name: 'zê',      phonetics: {'latin': 'z'},                                    ttsText: 'za, aza'),
];

const _portuguese = LanguageAlphabet(
  targetCode: 'pt',
  ttsLocale: 'pt-PT',
  nativeName: 'Alfabeto',
  groups: [AlphabetGroup(label: 'Alfabeto', entries: _portugueseLetters)],
);

// ── Swedish ───────────────────────────────────────────────────────────────────

const _swedishLetters = <AlphabetEntry>[
  AlphabetEntry(char: 'A', name: 'a',    phonetics: {'latin': 'a'},                                    ttsText: 'a'),
  AlphabetEntry(char: 'B', name: 'be',   phonetics: {'latin': 'b'},                                    ttsText: 'ba, aba'),
  AlphabetEntry(char: 'C', name: 'se',   phonetics: {'latin': 's/k'},                                  ttsText: 'ca, aca'),
  AlphabetEntry(char: 'D', name: 'de',   phonetics: {'latin': 'd'},                                    ttsText: 'da, ada'),
  AlphabetEntry(char: 'E', name: 'e',    phonetics: {'latin': 'e'},                                    ttsText: 'e'),
  AlphabetEntry(char: 'F', name: 'ef',   phonetics: {'latin': 'f'},                                    ttsText: 'fa, afa'),
  AlphabetEntry(char: 'G', name: 'ge',   phonetics: {'latin': 'g/y', 'en': 'g or y(e/i)'},            ttsText: 'ga, aga'),
  AlphabetEntry(char: 'H', name: 'ho',   phonetics: {'latin': 'h'},                                    ttsText: 'ha, aha'),
  AlphabetEntry(char: 'I', name: 'i',    phonetics: {'latin': 'ee'},                                   ttsText: 'i'),
  AlphabetEntry(char: 'J', name: 'ji',   phonetics: {'latin': 'y', 'en': 'y (yes)', 'pl': 'j'},       ttsText: 'ja, aja'),
  AlphabetEntry(char: 'K', name: 'ko',   phonetics: {'latin': 'k/ch', 'en': 'k or ch(e/i)'},          ttsText: 'ka, aka'),
  AlphabetEntry(char: 'L', name: 'el',   phonetics: {'latin': 'l'},                                    ttsText: 'la, ala'),
  AlphabetEntry(char: 'M', name: 'em',   phonetics: {'latin': 'm'},                                    ttsText: 'ma, ama'),
  AlphabetEntry(char: 'N', name: 'en',   phonetics: {'latin': 'n'},                                    ttsText: 'na, ana'),
  AlphabetEntry(char: 'O', name: 'o',    phonetics: {'latin': 'oo/o'},                                 ttsText: 'o'),
  AlphabetEntry(char: 'P', name: 'pe',   phonetics: {'latin': 'p'},                                    ttsText: 'pa, apa'),
  AlphabetEntry(char: 'Q', name: 'ku',   phonetics: {'latin': 'kv'},                                   ttsText: 'kwa, akwa'),
  AlphabetEntry(char: 'R', name: 'är',   phonetics: {'latin': 'r'},                                    ttsText: 'ra, ara'),
  AlphabetEntry(char: 'S', name: 'es',   phonetics: {'latin': 's'},                                    ttsText: 'sa, asa'),
  AlphabetEntry(char: 'T', name: 'te',   phonetics: {'latin': 't'},                                    ttsText: 'ta, ata'),
  AlphabetEntry(char: 'U', name: 'u',    phonetics: {'latin': 'oo/ue'},                                ttsText: 'u'),
  AlphabetEntry(char: 'V', name: 've',   phonetics: {'latin': 'v'},                                    ttsText: 'va, ava'),
  AlphabetEntry(char: 'X', name: 'eks',  phonetics: {'latin': 'ks'},                                   ttsText: 'ksa, aksa'),
  AlphabetEntry(char: 'Y', name: 'y',    phonetics: {'latin': 'ue', 'en': 'ue (no eng.)'},             ttsText: 'y'),
  AlphabetEntry(char: 'Z', name: 'säta', phonetics: {'latin': 's'},                                    ttsText: 'za, aza'),
  AlphabetEntry(char: 'Å', name: 'å',    phonetics: {'latin': 'aw', 'en': 'aw (saw)', 'pl': 'o (długie)'}, ttsText: 'å'),
  AlphabetEntry(char: 'Ä', name: 'ä',    phonetics: {'latin': 'ae', 'en': 'ae (air)', 'pl': 'e (otwarte)'}, ttsText: 'ä'),
  AlphabetEntry(char: 'Ö', name: 'ö',    phonetics: {'latin': 'ur', 'en': 'ur (bird)', 'pl': 'eu (zaokr.)'}, ttsText: 'ö'),
];

const _swedish = LanguageAlphabet(
  targetCode: 'sv',
  ttsLocale: 'sv-SE',
  nativeName: 'Alfabet',
  groups: [AlphabetGroup(label: 'Alfabet', entries: _swedishLetters)],
);

// ── Turkish ───────────────────────────────────────────────────────────────────

const _turkishLetters = <AlphabetEntry>[
  AlphabetEntry(char: 'A', name: 'a',           phonetics: {'latin': 'a'},                                     ttsText: 'a'),
  AlphabetEntry(char: 'B', name: 'be',          phonetics: {'latin': 'b'},                                     ttsText: 'ba, aba'),
  AlphabetEntry(char: 'C', name: 'ce',          phonetics: {'latin': 'j', 'en': 'j (just)', 'pl': 'dż'},      ttsText: 'ca, aca'),
  AlphabetEntry(char: 'Ç', name: 'çe',          phonetics: {'latin': 'ch', 'en': 'ch (chin)', 'pl': 'cz'},    ttsText: 'ça, aça'),
  AlphabetEntry(char: 'D', name: 'de',          phonetics: {'latin': 'd'},                                     ttsText: 'da, ada'),
  AlphabetEntry(char: 'E', name: 'e',           phonetics: {'latin': 'e'},                                     ttsText: 'e'),
  AlphabetEntry(char: 'F', name: 'fe',          phonetics: {'latin': 'f'},                                     ttsText: 'fa, afa'),
  AlphabetEntry(char: 'G', name: 'ge',          phonetics: {'latin': 'g'},                                     ttsText: 'ga, aga'),
  AlphabetEntry(char: 'Ğ', name: 'yumuşak ge',  phonetics: {'latin': '-', 'en': 'silent/lengthens'},          ttsText: 'ğa, ağa'),
  AlphabetEntry(char: 'H', name: 'he',          phonetics: {'latin': 'h'},                                     ttsText: 'ha, aha'),
  AlphabetEntry(char: 'I', name: 'ı',           phonetics: {'latin': 'uh', 'en': 'uh (dotless-i)'},           ttsText: 'ı'),
  AlphabetEntry(char: 'İ', name: 'i',           phonetics: {'latin': 'ee', 'en': 'ee (dotted-i)'},            ttsText: 'i'),
  AlphabetEntry(char: 'J', name: 'je',          phonetics: {'latin': 'zh', 'en': 'zh (measure)', 'pl': 'ż'},  ttsText: 'ja, aja'),
  AlphabetEntry(char: 'K', name: 'ke',          phonetics: {'latin': 'k'},                                     ttsText: 'ka, aka'),
  AlphabetEntry(char: 'L', name: 'le',          phonetics: {'latin': 'l'},                                     ttsText: 'la, ala'),
  AlphabetEntry(char: 'M', name: 'me',          phonetics: {'latin': 'm'},                                     ttsText: 'ma, ama'),
  AlphabetEntry(char: 'N', name: 'ne',          phonetics: {'latin': 'n'},                                     ttsText: 'na, ana'),
  AlphabetEntry(char: 'O', name: 'o',           phonetics: {'latin': 'o'},                                     ttsText: 'o'),
  AlphabetEntry(char: 'Ö', name: 'ö',           phonetics: {'latin': 'ur', 'en': 'ur (bird)', 'pl': 'eu (zaokr.)'}, ttsText: 'ö'),
  AlphabetEntry(char: 'P', name: 'pe',          phonetics: {'latin': 'p'},                                     ttsText: 'pa, apa'),
  AlphabetEntry(char: 'R', name: 're',          phonetics: {'latin': 'r'},                                     ttsText: 'ra, ara'),
  AlphabetEntry(char: 'S', name: 'se',          phonetics: {'latin': 's'},                                     ttsText: 'sa, asa'),
  AlphabetEntry(char: 'Ş', name: 'şe',          phonetics: {'latin': 'sh', 'en': 'sh (shoe)', 'pl': 'sz'},    ttsText: 'şa, aşa'),
  AlphabetEntry(char: 'T', name: 'te',          phonetics: {'latin': 't'},                                     ttsText: 'ta, ata'),
  AlphabetEntry(char: 'U', name: 'u',           phonetics: {'latin': 'oo'},                                    ttsText: 'u'),
  AlphabetEntry(char: 'Ü', name: 'ü',           phonetics: {'latin': 'ue', 'en': 'ue (no eng.)', 'pl': 'u (zaokr.)'}, ttsText: 'ü'),
  AlphabetEntry(char: 'V', name: 've',          phonetics: {'latin': 'v'},                                     ttsText: 'va, ava'),
  AlphabetEntry(char: 'Y', name: 'ye',          phonetics: {'latin': 'y', 'en': 'y (yes)', 'pl': 'j'},        ttsText: 'ya, aya'),
  AlphabetEntry(char: 'Z', name: 'ze',          phonetics: {'latin': 'z'},                                     ttsText: 'za, aza'),
];

const _turkish = LanguageAlphabet(
  targetCode: 'tr',
  ttsLocale: 'tr-TR',
  nativeName: 'Alfabe',
  groups: [AlphabetGroup(label: 'Alfabe', entries: _turkishLetters)],
);

// ── Czech ─────────────────────────────────────────────────────────────────────

const _czechLetters = <AlphabetEntry>[
  AlphabetEntry(char: 'A',  name: 'a',       phonetics: {'latin': 'a'},                                   ttsText: 'a'),
  AlphabetEntry(char: 'Á',  name: 'á',       phonetics: {'latin': 'aa', 'en': 'aa (long)'},              ttsText: 'á'),
  AlphabetEntry(char: 'B',  name: 'bé',      phonetics: {'latin': 'b'},                                   ttsText: 'ba, aba'),
  AlphabetEntry(char: 'C',  name: 'cé',      phonetics: {'latin': 'ts', 'en': 'ts (pizza)', 'pl': 'c'},  ttsText: 'ca, aca'),
  AlphabetEntry(char: 'Č',  name: 'čé',      phonetics: {'latin': 'ch', 'en': 'ch (chin)', 'pl': 'cz'},  ttsText: 'ča, ača'),
  AlphabetEntry(char: 'D',  name: 'dé',      phonetics: {'latin': 'd'},                                   ttsText: 'da, ada'),
  AlphabetEntry(char: 'Ď',  name: 'ď',       phonetics: {'latin': 'dy', 'en': 'dy (soft)'},              ttsText: 'ďa, aďa'),
  AlphabetEntry(char: 'E',  name: 'e',       phonetics: {'latin': 'e'},                                   ttsText: 'e'),
  AlphabetEntry(char: 'É',  name: 'é',       phonetics: {'latin': 'ee', 'en': 'ee (long)'},              ttsText: 'é'),
  AlphabetEntry(char: 'Ě',  name: 'ě',       phonetics: {'latin': 'ye', 'pl': 'je'},                     ttsText: 'ě'),
  AlphabetEntry(char: 'F',  name: 'ef',      phonetics: {'latin': 'f'},                                   ttsText: 'fa, afa'),
  AlphabetEntry(char: 'G',  name: 'gé',      phonetics: {'latin': 'g'},                                   ttsText: 'ga, aga'),
  AlphabetEntry(char: 'H',  name: 'há',      phonetics: {'latin': 'h'},                                   ttsText: 'ha, aha'),
  AlphabetEntry(char: 'Ch', name: 'chá',     phonetics: {'latin': 'kh', 'en': 'kh (loch)', 'pl': 'ch'}, ttsText: 'cha, acha'),
  AlphabetEntry(char: 'I',  name: 'i',       phonetics: {'latin': 'i'},                                   ttsText: 'i'),
  AlphabetEntry(char: 'Í',  name: 'í',       phonetics: {'latin': 'ee', 'en': 'ee (long)'},              ttsText: 'í'),
  AlphabetEntry(char: 'J',  name: 'jé',      phonetics: {'latin': 'y', 'en': 'y (yes)', 'pl': 'j'},      ttsText: 'ja, aja'),
  AlphabetEntry(char: 'K',  name: 'ká',      phonetics: {'latin': 'k'},                                   ttsText: 'ka, aka'),
  AlphabetEntry(char: 'L',  name: 'el',      phonetics: {'latin': 'l'},                                   ttsText: 'la, ala'),
  AlphabetEntry(char: 'M',  name: 'em',      phonetics: {'latin': 'm'},                                   ttsText: 'ma, ama'),
  AlphabetEntry(char: 'N',  name: 'en',      phonetics: {'latin': 'n'},                                   ttsText: 'na, ana'),
  AlphabetEntry(char: 'Ň',  name: 'eň',      phonetics: {'latin': 'ny', 'en': 'ny (canyon)', 'pl': 'ń'}, ttsText: 'ňa, aňa'),
  AlphabetEntry(char: 'O',  name: 'o',       phonetics: {'latin': 'o'},                                   ttsText: 'o'),
  AlphabetEntry(char: 'Ó',  name: 'ó',       phonetics: {'latin': 'oo', 'en': 'oo (long)'},              ttsText: 'ó'),
  AlphabetEntry(char: 'P',  name: 'pé',      phonetics: {'latin': 'p'},                                   ttsText: 'pa, apa'),
  AlphabetEntry(char: 'R',  name: 'er',      phonetics: {'latin': 'r'},                                   ttsText: 'ra, ara'),
  AlphabetEntry(char: 'Ř',  name: 'eř',      phonetics: {'latin': 'rzh', 'en': 'r+zh (unique!)'},        ttsText: 'řa, ařa'),
  AlphabetEntry(char: 'S',  name: 'es',      phonetics: {'latin': 's'},                                   ttsText: 'sa, asa'),
  AlphabetEntry(char: 'Š',  name: 'eš',      phonetics: {'latin': 'sh', 'en': 'sh (shoe)', 'pl': 'sz'},  ttsText: 'ša, aša'),
  AlphabetEntry(char: 'T',  name: 'té',      phonetics: {'latin': 't'},                                   ttsText: 'ta, ata'),
  AlphabetEntry(char: 'Ť',  name: 'ť',       phonetics: {'latin': 'ty', 'en': 'ty (soft)'},              ttsText: 'ťa, aťa'),
  AlphabetEntry(char: 'U',  name: 'u',       phonetics: {'latin': 'oo'},                                  ttsText: 'u'),
  AlphabetEntry(char: 'Ú',  name: 'ú',       phonetics: {'latin': 'oo', 'en': 'oo (long)'},              ttsText: 'ú'),
  AlphabetEntry(char: 'Ů',  name: 'ů',       phonetics: {'latin': 'oo', 'en': 'oo (historical)'},        ttsText: 'ů'),
  AlphabetEntry(char: 'V',  name: 'vé',      phonetics: {'latin': 'v'},                                   ttsText: 'va, ava'),
  AlphabetEntry(char: 'X',  name: 'iks',     phonetics: {'latin': 'ks'},                                  ttsText: 'ksa, aksa'),
  AlphabetEntry(char: 'Y',  name: 'ypsilon', phonetics: {'latin': 'i'},                                   ttsText: 'y'),
  AlphabetEntry(char: 'Ý',  name: 'ý',       phonetics: {'latin': 'ee', 'en': 'ee (long)'},              ttsText: 'ý'),
  AlphabetEntry(char: 'Z',  name: 'zet',     phonetics: {'latin': 'z'},                                   ttsText: 'za, aza'),
  AlphabetEntry(char: 'Ž',  name: 'žet',     phonetics: {'latin': 'zh', 'en': 'zh (measure)', 'pl': 'ż'}, ttsText: 'ža, aža'),
];

const _czech = LanguageAlphabet(
  targetCode: 'cs',
  ttsLocale: 'cs-CZ',
  nativeName: 'Abeceda',
  groups: [AlphabetGroup(label: 'Abeceda', entries: _czechLetters)],
);

// ── Dutch ─────────────────────────────────────────────────────────────────────

const _dutchLetters = <AlphabetEntry>[
  AlphabetEntry(char: 'A',  name: 'a',   phonetics: {'latin': 'a/aa'},                                      ttsText: 'a'),
  AlphabetEntry(char: 'B',  name: 'be',  phonetics: {'latin': 'b'},                                         ttsText: 'ba, aba'),
  AlphabetEntry(char: 'C',  name: 'se',  phonetics: {'latin': 's/k'},                                       ttsText: 'ca, aca'),
  AlphabetEntry(char: 'D',  name: 'de',  phonetics: {'latin': 'd/t'},                                       ttsText: 'da, ada'),
  AlphabetEntry(char: 'E',  name: 'e',   phonetics: {'latin': 'e/ee'},                                      ttsText: 'e'),
  AlphabetEntry(char: 'F',  name: 'ef',  phonetics: {'latin': 'f'},                                         ttsText: 'fa, afa'),
  AlphabetEntry(char: 'G',  name: 'ge',  phonetics: {'latin': 'kh', 'en': 'kh (guttural)', 'pl': 'ch (gardłowe)'}, ttsText: 'ga, aga'),
  AlphabetEntry(char: 'H',  name: 'ha',  phonetics: {'latin': 'h'},                                         ttsText: 'ha, aha'),
  AlphabetEntry(char: 'I',  name: 'i',   phonetics: {'latin': 'i/ee'},                                      ttsText: 'i'),
  AlphabetEntry(char: 'IJ', name: 'ei',  phonetics: {'latin': 'ay', 'en': 'ay (pay)'},                     ttsText: 'ij'),
  AlphabetEntry(char: 'J',  name: 'jé',  phonetics: {'latin': 'y', 'en': 'y (yes)', 'pl': 'j'},            ttsText: 'ja, aja'),
  AlphabetEntry(char: 'K',  name: 'ka',  phonetics: {'latin': 'k'},                                         ttsText: 'ka, aka'),
  AlphabetEntry(char: 'L',  name: 'el',  phonetics: {'latin': 'l'},                                         ttsText: 'la, ala'),
  AlphabetEntry(char: 'M',  name: 'em',  phonetics: {'latin': 'm'},                                         ttsText: 'ma, ama'),
  AlphabetEntry(char: 'N',  name: 'en',  phonetics: {'latin': 'n'},                                         ttsText: 'na, ana'),
  AlphabetEntry(char: 'O',  name: 'o',   phonetics: {'latin': 'o/oo'},                                      ttsText: 'o'),
  AlphabetEntry(char: 'P',  name: 'pe',  phonetics: {'latin': 'p'},                                         ttsText: 'pa, apa'),
  AlphabetEntry(char: 'R',  name: 'er',  phonetics: {'latin': 'r'},                                         ttsText: 'ra, ara'),
  AlphabetEntry(char: 'S',  name: 'es',  phonetics: {'latin': 's'},                                         ttsText: 'sa, asa'),
  AlphabetEntry(char: 'T',  name: 'te',  phonetics: {'latin': 't'},                                         ttsText: 'ta, ata'),
  AlphabetEntry(char: 'U',  name: 'u',   phonetics: {'latin': 'ue/oo'},                                     ttsText: 'u'),
  AlphabetEntry(char: 'V',  name: 've',  phonetics: {'latin': 'v/f'},                                       ttsText: 'va, ava'),
  AlphabetEntry(char: 'W',  name: 'we',  phonetics: {'latin': 'v/w', 'en': 'between v and w'},              ttsText: 'wa, awa'),
  AlphabetEntry(char: 'X',  name: 'iks', phonetics: {'latin': 'ks'},                                        ttsText: 'ksa, aksa'),
  AlphabetEntry(char: 'Y',  name: 'ei',  phonetics: {'latin': 'y/ee'},                                      ttsText: 'y'),
  AlphabetEntry(char: 'Z',  name: 'zet', phonetics: {'latin': 'z'},                                         ttsText: 'za, aza'),
];

const _dutch = LanguageAlphabet(
  targetCode: 'nl',
  ttsLocale: 'nl-NL',
  nativeName: 'Alfabet',
  groups: [AlphabetGroup(label: 'Alfabet', entries: _dutchLetters)],
);
