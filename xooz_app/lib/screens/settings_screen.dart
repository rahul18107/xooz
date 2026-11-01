import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
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
                      iconColor: const Color(0xFFC8B89A),
                    ),
                    _SettingsItem(
                      icon: Icons.bar_chart_outlined,
                      title: 'Plan & Usage',
                      iconColor: const Color(0xFFE8DFD0),
                    ),
                    _SettingsItem(
                      icon: Icons.card_giftcard_outlined,
                      title: 'Referral Program',
                      iconColor: const Color(0xFFE8DFD0),
                      badge: 'NEW',
                    ),
                  ]),
                  const SizedBox(height: 16),
                  _buildSection([
                    _SettingsItem(
                      icon: Icons.bluetooth_outlined,
                      title: 'Device',
                      iconColor: const Color(0xFFE8DFD0),
                    ),
                    _SettingsItem(
                      icon: Icons.mic_outlined,
                      title: 'Recording & Transcription',
                      iconColor: const Color(0xFFE8DFD0),
                    ),
                    _SettingsItem(
                      icon: Icons.volume_up_outlined,
                      title: 'Voice',
                      iconColor: const Color(0xFFE8DFD0),
                    ),
                    _SettingsItem(
                      icon: Icons.notifications_outlined,
                      title: 'Notifications & Display',
                      iconColor: const Color(0xFFE8DFD0),
                    ),
                    _SettingsItem(
                      icon: Icons.account_tree_outlined,
                      title: 'Integrations',
                      iconColor: const Color(0xFFE8DFD0),
                      badge: 'BETA',
                      badgeColor: const Color(0xFFC8B89A),
                    ),
                    _SettingsItem(
                      icon: Icons.terminal_outlined,
                      title: 'Connect an Agent',
                      iconColor: const Color(0xFFE8DFD0),
                    ),
                    _SettingsItem(
                      icon: Icons.shield_outlined,
                      title: 'Data & Privacy',
                      iconColor: const Color(0xFFE8DFD0),
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
                color: const Color(0xFF1A1512),
                borderRadius: BorderRadius.circular(19),
              ),
              child: const Icon(
                Icons.close,
                color: Color(0xFF6B6460),
                size: 18,
              ),
            ),
          ),
          const Spacer(),
          const Text(
            'Settings',
            style: TextStyle(
              fontFamily: 'DMSerifDisplay',
              fontSize: 22,
              color: Color(0xFFE8DFD0),
            ),
          ),
          const Spacer(),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1512),
              borderRadius: BorderRadius.circular(19),
            ),
            child: const Icon(
              Icons.search,
              color: Color(0xFF6B6460),
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1512),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF252018),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(
              Icons.person_outline,
              color: Color(0xFFC8B89A),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rahul',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFE8DFD0),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'rahul@gmail.com',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    color: Color(0xFF6B6460),
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            color: Color(0xFF6B6460),
            size: 18,
          ),
        ],
      ),
    );
  }

  Widget _buildSection(List<_SettingsItem> items) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1512),
        borderRadius: BorderRadius.circular(16),
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
                const Divider(
                  height: 1,
                  color: Color(0xFF252018),
                  indent: 56,
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSettingsRow(_SettingsItem item) {
    return GestureDetector(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF252018),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                item.icon,
                color: item.iconColor,
                size: 16,
              ),
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
                      color: Color(0xFFE8DFD0),
                    ),
                  ),
                  if (item.subtitle != null)
                    Text(
                      item.subtitle!,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: Color(0xFF6B6460),
                      ),
                    ),
                ],
              ),
            ),
            if (item.badge != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: (item.badgeColor ?? const Color(0xFF4CAF50))
                      .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  item.badge!,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: item.badgeColor ?? const Color(0xFF4CAF50),
                  ),
                ),
              ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right,
              color: Color(0xFF6B6460),
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

  _SettingsItem({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.iconColor,
    this.badge,
    this.badgeColor,
  });
}