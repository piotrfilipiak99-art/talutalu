/// A single analyzed word/punctuation mark within a reading text — the
/// per-token annotation a real AI generation call would eventually return.
/// [charStart]/[charEnd] index into the raw `body` (or `translation`)
/// string the token belongs to, so they line up with the character offsets
/// flutter_tts's progress handler already reports.
///
/// [translation] is always in the course's base language, never hardcoded
/// to English — the same shape works for any base/target language pair.
/// It's the gloss for this *exact inflected form* — [lemmaTranslation] is
/// the (often different) gloss for the dictionary form, [lemma].
/// [pos] uses the Universal Dependencies tagset (NOUN, VERB, ADJ, ADV,
/// PRON, DET, ADP, NUM, PROPN, PART, CONJ, INTJ, PUNCT, ...) so it means
/// the same thing regardless of language. [morph] holds whichever UD
/// features apply to this word (Case, Number, Gender, Person, Tense,
/// Aspect, Mood, ...) — empty for languages/words that don't have them.
/// [reading] is only set for scripts that need a phonetic transliteration
/// (pinyin, romaji, ...). [root]/[rootMeaning] are the word's stem and,
/// when it carries an identifiable meaning of its own, a gloss of it —
/// both nullable, since plenty of words (function words, most proper
/// nouns) don't have a stem worth surfacing separately from the lemma.
class TextToken {
  final String surface;
  final String lemma;
  final String? translation;
  final String? lemmaTranslation;
  final String pos;
  final Map<String, String> morph;
  final String? reading;
  final String? root;
  final String? rootMeaning;
  final int sentenceIndex;
  final int charStart;
  final int charEnd;

  const TextToken({
    required this.surface,
    required this.lemma,
    this.translation,
    this.lemmaTranslation,
    required this.pos,
    this.morph = const {},
    this.reading,
    this.root,
    this.rootMeaning,
    required this.sentenceIndex,
    required this.charStart,
    required this.charEnd,
  });

  Map<String, dynamic> toJson() => {
        'surface': surface,
        'lemma': lemma,
        'translation': translation,
        'lemmaTranslation': lemmaTranslation,
        'pos': pos,
        'morph': morph,
        'reading': reading,
        'root': root,
        'rootMeaning': rootMeaning,
        'sentenceIndex': sentenceIndex,
        'charStart': charStart,
        'charEnd': charEnd,
      };

  factory TextToken.fromJson(Map<String, dynamic> j) => TextToken(
        surface: j['surface'] as String,
        lemma: j['lemma'] as String,
        translation: j['translation'] as String?,
        lemmaTranslation: j['lemmaTranslation'] as String?,
        pos: j['pos'] as String,
        morph: j['morph'] == null
            ? const {}
            : Map<String, String>.from(j['morph'] as Map),
        reading: j['reading'] as String?,
        root: j['root'] as String?,
        rootMeaning: j['rootMeaning'] as String?,
        sentenceIndex: j['sentenceIndex'] as int,
        charStart: j['charStart'] as int,
        charEnd: j['charEnd'] as int,
      );
}

/// A sentence boundary within a text's `body` or `translation` string.
///
/// For translation sentences, [alignsToIndex] names the body sentence it
/// corresponds to — explicit, instead of assuming the translation has the
/// same sentence count/order as the body. That assumption breaks more
/// often the more typologically distant the base/target pair is (a
/// translation can merge or split sentences), so the alignment is data,
/// not a positional guess.
class TextSentence {
  final int index;
  final int charStart;
  final int charEnd;
  final int? alignsToIndex;

  const TextSentence({
    required this.index,
    required this.charStart,
    required this.charEnd,
    this.alignsToIndex,
  });

  Map<String, dynamic> toJson() => {
        'index': index,
        'charStart': charStart,
        'charEnd': charEnd,
        'alignsToIndex': alignsToIndex,
      };

  factory TextSentence.fromJson(Map<String, dynamic> j) => TextSentence(
        index: j['index'] as int,
        charStart: j['charStart'] as int,
        charEnd: j['charEnd'] as int,
        alignsToIndex: j['alignsToIndex'] as int?,
      );
}
