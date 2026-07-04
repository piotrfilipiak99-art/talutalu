import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// Friendly labels for Universal Dependencies morph features/values — the
/// same tagset regardless of language, see lib/models/text_token.dart.
/// Shared by the reader's word sheet and the flashcards' card detail sheet
/// so the two stay in sync instead of drifting apart.
String morphLabel(String key, String value) {
  const keyLabels = {
    'Case': 'Case',
    'Number': 'Number',
    'Gender': 'Gender',
    'Person': 'Person',
    'Tense': 'Tense',
    'Degree': 'Degree',
    'Voice': 'Voice',
    'Mood': 'Mood',
    'Aspect': 'Aspect',
  };
  const valueLabels = {
    'Nom': 'Nominative', 'Gen': 'Genitive', 'Dat': 'Dative', 'Acc': 'Accusative',
    'Ins': 'Instrumental', 'Loc': 'Locative', 'Voc': 'Vocative',
    'Sing': 'Singular', 'Plur': 'Plural',
    'Masc': 'Masculine', 'Fem': 'Feminine', 'Neut': 'Neuter',
    'Pres': 'Present', 'Past': 'Past', 'Fut': 'Future',
    'Sup': 'Superlative', 'Cmp': 'Comparative', 'Pos': 'Positive',
    'Pass': 'Passive', 'Act': 'Active',
    '1': '1st person', '2': '2nd person', '3': '3rd person',
  };
  final k = keyLabels[key] ?? key;
  final v = valueLabels[value] ?? value;
  return '$k: $v';
}

/// Splits trailing punctuation (.,!?;:) off a word so a tap/speaking
/// highlight can cover just the word itself — otherwise a word at the end
/// of a sentence highlights together with its period/question
/// mark/exclamation mark, which reads as a mistake.
({String core, String trail}) splitTrailingPunct(String word) {
  const punct = {'.', ',', '!', '?', ';', ':'};
  var end = word.length;
  while (end > 0 && punct.contains(word[end - 1])) {
    end--;
  }
  if (end == 0) return (core: word, trail: '');
  return (core: word.substring(0, end), trail: word.substring(end));
}

class AttributeChip extends StatelessWidget {
  final String label;
  const AttributeChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(label,
            style: GoogleFonts.dmSans(
                color: AppColors.text2,
                fontSize: 11,
                fontWeight: FontWeight.w500)),
      );
}
