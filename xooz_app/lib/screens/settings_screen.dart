import '../theme/app_theme.dart';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/chat.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  ProfileInfo? _profile;
  UsageInfo? _usage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        ApiService.getProfile(),
        ApiService.getUsage(),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = results[0] as ProfileInfo?;
        _usage = results[1] as UsageInfo?;
      });
    } catch (e) {
      // keep the placeholder data
    }
  }

  Future<void> _editVocabulary() async {
    final controller = TextEditingController(
      text: (_profile?.transcriptionVocabulary ?? []).join('\n'),
    );
    String? validationError;
    final terms = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateDialog) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'Vocabulary',
            style: TextStyle(color: AppColors.ink),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                maxLines: 8,
                minLines: 5,
                style: const TextStyle(color: AppColors.ink),
                decoration: const InputDecoration(
                  hintText: 'One name or term per line',
                  border: OutlineInputBorder(),
                ),
              ),
              if (validationError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    validationError!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final values = controller.text
                    .split('\n')
                    .map((term) => term.trim())
                    .where((term) => term.isNotEmpty)
                    .toSet()
                    .toList();
                if (values.length > 200 ||
                    values.any(
                      (term) =>
                          term.length > 50 ||
                          term.split(RegExp(r'\s+')).length > 6,
                    )) {
                  updateDialog(
                    () => validationError =
                        'Use up to 200 terms, each at most 50 characters and 6 words.',
                  );
                  return;
                }
                Navigator.pop(dialogContext, values);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (terms == null || !mounted) return;
    try {
      final profile = await ApiService.updateTranscriptionVocabulary(terms);
      if (!mounted) return;
      setState(() => _profile = profile);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Vocabulary saved')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save vocabulary')),
      );
    }
  }

  Future<void> _editDailyRecapSchedule() async {
    final profile = _profile;
    if (profile == null) return;
    final timezoneController = TextEditingController(text: profile.timezone);
    var enabled = profile.dailyRecapEnabled;
    var hour = profile.dailyRecapHour;
    final choice =
        await showDialog<({bool enabled, int hour, String timezone})>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, updateDialog) => AlertDialog(
              backgroundColor: Colors.white,
              title: const Text(
                'Daily recap',
                style: TextStyle(color: AppColors.ink),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile(
                      title: const Text(
                        'Automatic recap',
                        style: TextStyle(color: AppColors.ink),
                      ),
                      value: enabled,
                      onChanged: (value) => updateDialog(() => enabled = value),
                    ),
                    DropdownButtonFormField<int>(
                      initialValue: hour,
                      decoration: const InputDecoration(
                        labelText: 'Local hour',
                      ),
                      items: [
                        for (var h = 0; h < 24; h++)
                          DropdownMenuItem(
                            value: h,
                            child: Text('${h.toString().padLeft(2, '0')}:00'),
                          ),
                      ],
                      onChanged: (value) =>
                          updateDialog(() => hour = value ?? hour),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: timezoneController,
                      style: const TextStyle(color: AppColors.ink),
                      decoration: const InputDecoration(
                        labelText: 'Timezone',
                        hintText: 'Asia/Kolkata',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, (
                    enabled: enabled,
                    hour: hour,
                    timezone: timezoneController.text.trim(),
                  )),
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        );
    timezoneController.dispose();
    if (choice == null || !mounted) return;
    try {
      final saved = await ApiService.updateDailyRecapSchedule(
        enabled: choice.enabled,
        hour: choice.hour,
        timezone: choice.timezone,
      );
      if (!mounted) return;
      setState(() => _profile = saved);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Daily recap schedule saved')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save daily recap schedule')),
      );
    }
  }

  void _showDataPrivacy() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Data & Privacy',
          style: TextStyle(color: AppColors.ink),
        ),
        content: const Text(
          'Recordings are sent to the server for transcription. If the connection fails, the audio stays on this phone and retries automatically. You can delete individual recordings from the home or transcript screen. Full account export and deletion will be available with sign-in.',
          style: TextStyle(color: AppColors.ink),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const SizedBox(height: 8),
                  _buildProfileCard(),
                  const SizedBox(height: 16),
                  _buildSection([
                    _SettingsItem(
                      icon: Icons.workspace_premium_outlined,
                      title: 'Upgrade',
                      subtitle: 'Start your 7-day free trial',
                      iconColor: AppColors.accent,
                    ),
                    _SettingsItem(
                      icon: Icons.bar_chart_outlined,
                      title: 'Plan & Usage',
                      subtitle: _usage?.label,
                      iconColor: AppColors.ink,
                    ),
                    _SettingsItem(
                      icon: Icons.card_giftcard_outlined,
                      title: 'Referral Program',
                      iconColor: AppColors.ink,
                      badge: 'NEW',
                    ),
                  ]),
                  const SizedBox(height: 16),
                  _buildSection([
                    _SettingsItem(
                      icon: Icons.bluetooth_outlined,
                      title: 'Device',
                      iconColor: AppColors.ink,
                    ),
                    _SettingsItem(
                      icon: Icons.mic_outlined,
                      title: 'Recording & Transcription',
                      subtitle: 'Vocabulary',
                      iconColor: AppColors.ink,
                      onTap: _editVocabulary,
                    ),
                    _SettingsItem(
                      icon: Icons.volume_up_outlined,
                      title: 'Voice',
                      iconColor: AppColors.ink,
                    ),
                    _SettingsItem(
                      icon: Icons.notifications_outlined,
                      title: 'Notifications & Display',
                      subtitle: _profile?.dailyRecapEnabled == true
                          ? 'Daily recap at ${_profile!.dailyRecapHour.toString().padLeft(2, '0')}:00'
                          : 'Daily recap off',
                      iconColor: AppColors.ink,
                      onTap: _editDailyRecapSchedule,
                    ),
                    _SettingsItem(
                      icon: Icons.account_tree_outlined,
                      title: 'Integrations',
                      iconColor: AppColors.ink,
                      badge: 'BETA',
                      badgeColor: AppColors.accent,
                    ),
                    _SettingsItem(
                      icon: Icons.terminal_outlined,
                      title: 'Connect an Agent',
                      iconColor: AppColors.ink,
                    ),
                    _SettingsItem(
                      icon: Icons.shield_outlined,
                      title: 'Data & Privacy',
                      iconColor: AppColors.ink,
                      onTap: _showDataPrivacy,
                    ),
                  ]),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: const Border.fromBorderSide(
                  BorderSide(color: AppColors.homeBorder),
                ),
                borderRadius: BorderRadius.circular(19),
              ),
              child: const Icon(Icons.close, color: AppColors.muted, size: 18),
            ),
          ),
          const Spacer(),
          const Text(
            'Settings',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const Spacer(),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: const Border.fromBorderSide(
                BorderSide(color: AppColors.homeBorder),
              ),
              borderRadius: BorderRadius.circular(19),
            ),
            child: const Icon(Icons.search, color: AppColors.muted, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
    final name = _profile?.displayName?.isNotEmpty == true
        ? _profile!.displayName!
        : 'Rahul';
    final email = _profile?.email?.isNotEmpty == true
        ? _profile!.email!
        : 'rahul@gmail.com';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border.fromBorderSide(
          BorderSide(color: AppColors.homeBorder),
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.raised,
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(
              Icons.person_outline,
              color: AppColors.ink,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    color: AppColors.cardMuted,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.cardMuted, size: 18),
        ],
      ),
    );
  }

  Widget _buildSection(List<_SettingsItem> items) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border.fromBorderSide(
          BorderSide(color: AppColors.homeBorder),
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final isLast = index == items.length - 1;
          return Column(
            children: [
              _buildSettingsRow(item),
              if (!isLast)
                const Divider(height: 1, color: AppColors.raised, indent: 56),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSettingsRow(_SettingsItem item) {
    return GestureDetector(
      onTap: item.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.raised,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(item.icon, color: item.iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.ink,
                    ),
                  ),
                  if (item.subtitle != null)
                    Text(
                      item.subtitle!,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: AppColors.cardMuted,
                      ),
                    ),
                ],
              ),
            ),
            if (item.badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (item.badgeColor ?? AppColors.accent).withValues(
                    alpha: 0.15,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  item.badge!,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: item.badgeColor ?? AppColors.accent,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right,
              color: AppColors.cardMuted,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsItem {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color iconColor;
  final String? badge;
  final Color? badgeColor;
  final VoidCallback? onTap;

  _SettingsItem({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.iconColor,
    this.badge,
    this.badgeColor,
    this.onTap,
  });
}
