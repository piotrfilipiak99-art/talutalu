import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

const _topics = [
  {'label': 'Bug report', 'icon': Icons.bug_report_outlined},
  {'label': 'Suggestion', 'icon': Icons.lightbulb_outline_rounded},
  {'label': 'Question', 'icon': Icons.help_outline_rounded},
  {'label': 'Other', 'icon': Icons.chat_bubble_outline_rounded},
];

class HelpFeedbackScreen extends StatefulWidget {
  const HelpFeedbackScreen({super.key});

  @override
  State<HelpFeedbackScreen> createState() => _HelpFeedbackScreenState();
}

class _HelpFeedbackScreenState extends State<HelpFeedbackScreen> {
  int _topic = 0;
  final _emailCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  bool _triedToSend = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  bool get _messageValid => _messageCtrl.text.trim().isNotEmpty;

  void _send() {
    if (!_messageValid) {
      setState(() => _triedToSend = true);
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Icon(Icons.mark_email_read_outlined,
                color: AppColors.primary, size: 32),
            const SizedBox(height: 12),
            Text('Message sent',
                style: GoogleFonts.cormorantGaramond(
                    color: AppColors.text,
                    fontSize: 26,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text(
              'Thanks for reaching out — your message helps make Talutalu '
              'better.',
              style: GoogleFonts.dmSans(
                  color: AppColors.text2, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text('Done',
                    style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    ).then((_) {
      // Back to Profile once the confirmation is dismissed.
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final showError = _triedToSend && !_messageValid;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.text),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Help & feedback',
            style: GoogleFonts.cormorantGaramond(
                color: AppColors.text,
                fontSize: 22,
                fontWeight: FontWeight.w500)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('TOPIC',
                style: GoogleFonts.dmSans(
                    color: AppColors.text3,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(_topics.length, (i) {
                final selected = _topic == i;
                return GestureDetector(
                  onTap: () => setState(() => _topic = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color:
                          selected ? AppColors.primaryGlow : AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color:
                              selected ? AppColors.primary : AppColors.border,
                          width: selected ? 1.5 : 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_topics[i]['icon'] as IconData,
                            size: 16,
                            color: selected
                                ? AppColors.primary
                                : AppColors.text2),
                        const SizedBox(width: 6),
                        Text(_topics[i]['label'] as String,
                            style: GoogleFonts.dmSans(
                                color: selected
                                    ? AppColors.primary
                                    : AppColors.text,
                                fontSize: 13,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),
            Text('EMAIL (OPTIONAL)',
                style: GoogleFonts.dmSans(
                    color: AppColors.text3,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2)),
            const SizedBox(height: 10),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              style: GoogleFonts.dmSans(color: AppColors.text, fontSize: 15),
              decoration: const InputDecoration(
                  hintText: 'Where can we reach you back?'),
            ),
            const SizedBox(height: 24),
            Text('MESSAGE',
                style: GoogleFonts.dmSans(
                    color: AppColors.text3,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2)),
            const SizedBox(height: 10),
            TextField(
              controller: _messageCtrl,
              minLines: 5,
              maxLines: 10,
              onChanged: (_) {
                if (_triedToSend) setState(() {});
              },
              style: GoogleFonts.dmSans(
                  color: AppColors.text, fontSize: 15, height: 1.5),
              decoration: const InputDecoration(
                  hintText: 'Tell us what happened or what you\'d improve…'),
            ),
            if (showError) ...[
              const SizedBox(height: 8),
              Text('Please write a message before sending.',
                  style: GoogleFonts.dmSans(
                      color: const Color(0xFFFF6B6B), fontSize: 12)),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _send,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.send_rounded, size: 18),
              label: Text('Send',
                  style: GoogleFonts.dmSans(
                      fontWeight: FontWeight.w600, fontSize: 15)),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 15, color: AppColors.text3),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "This build doesn't deliver the message anywhere yet — "
                    "sending is mocked until a backend is wired up.",
                    style: GoogleFonts.dmSans(
                        color: AppColors.text3, fontSize: 12, height: 1.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
