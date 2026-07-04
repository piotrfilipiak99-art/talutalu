import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/app_storage.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late bool _notificationsEnabled;
  late bool _reminderEnabled;
  late TimeOfDay _time;

  @override
  void initState() {
    super.initState();
    _notificationsEnabled = AppStorage.instance.notificationsEnabled;
    _reminderEnabled = AppStorage.instance.reminderEnabled;
    _time = TimeOfDay(
        hour: AppStorage.instance.reminderHour,
        minute: AppStorage.instance.reminderMinute);
  }

  void _persistReminder() => AppStorage.instance.saveReminder(
      enabled: _reminderEnabled, hour: _time.hour, minute: _time.minute);

  void _toggleNotifications(bool v) {
    setState(() {
      _notificationsEnabled = v;
      // Without notifications a reminder can never fire — keep the two in
      // sync instead of leaving the reminder "on" but unreachable.
      if (!v) _reminderEnabled = false;
    });
    AppStorage.instance.setNotificationsEnabled(v);
    _persistReminder();
  }

  void _toggleReminder(bool v) {
    setState(() => _reminderEnabled = v);
    _persistReminder();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) {
      setState(() => _time = picked);
      _persistReminder();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.text),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Notifications',
            style: GoogleFonts.cormorantGaramond(
                color: AppColors.text, fontSize: 22, fontWeight: FontWeight.w500)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                            _notificationsEnabled
                                ? Icons.notifications_active_rounded
                                : Icons.notifications_off_rounded,
                            color: AppColors.text2,
                            size: 20),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text('Notifications',
                              style: GoogleFonts.dmSans(
                                  color: AppColors.text, fontSize: 15)),
                        ),
                        Switch(
                          value: _notificationsEnabled,
                          activeThumbColor: AppColors.primary,
                          onChanged: _toggleNotifications,
                        ),
                      ],
                    ),
                  ),
                  Divider(
                      height: 1,
                      thickness: 0.5,
                      color: AppColors.border,
                      indent: 52),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        Icon(Icons.today_rounded,
                            color: _notificationsEnabled
                                ? AppColors.text2
                                : AppColors.text3,
                            size: 20),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text('Daily reminder',
                              style: GoogleFonts.dmSans(
                                  color: _notificationsEnabled
                                      ? AppColors.text
                                      : AppColors.text3,
                                  fontSize: 15)),
                        ),
                        Switch(
                          value: _reminderEnabled,
                          activeThumbColor: AppColors.primary,
                          onChanged: _notificationsEnabled ? _toggleReminder : null,
                        ),
                      ],
                    ),
                  ),
                  if (_notificationsEnabled && _reminderEnabled) ...[
                    Divider(
                        height: 1,
                        thickness: 0.5,
                        color: AppColors.border,
                        indent: 52),
                    InkWell(
                      onTap: _pickTime,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            Icon(Icons.access_time_rounded,
                                color: AppColors.text2, size: 20),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text('Time',
                                  style: GoogleFonts.dmSans(
                                      color: AppColors.text, fontSize: 15)),
                            ),
                            Text(_time.format(context),
                                style: GoogleFonts.dmSans(
                                    color: AppColors.text2, fontSize: 14)),
                            const SizedBox(width: 6),
                            Icon(Icons.chevron_right_rounded,
                                color: AppColors.text3, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!_notificationsEnabled) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Turn on notifications to set a daily reminder.',
                  style: GoogleFonts.dmSans(
                      color: AppColors.text3, fontSize: 12, height: 1.4),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 15, color: AppColors.text3),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "This saves your preference, but doesn't send a real push "
                      "notification yet — that needs a background scheduler "
                      "this build doesn't have wired up.",
                      style: GoogleFonts.dmSans(
                          color: AppColors.text3, fontSize: 12, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
