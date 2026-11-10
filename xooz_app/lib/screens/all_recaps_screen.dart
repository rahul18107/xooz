import 'package:flutter/material.dart';
import '../models/digest.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'recap_screen.dart';

class AllRecapsScreen extends StatefulWidget {
  const AllRecapsScreen({super.key});

  @override
  State<AllRecapsScreen> createState() => _AllRecapsScreenState();
}

class _AllRecapsScreenState extends State<AllRecapsScreen> {
  List<Digest> _digests = [];
  bool _loading = true;
  bool _changed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final digests = await ApiService.getDigests();
      if (!mounted) return;
      setState(() {
        _digests = digests;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst(RegExp(r'^ApiException:\s*'), '');
        _loading = false;
      });
    }
  }

  Future<void> _openRecap(Digest digest) async {
    final deleted = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RecapScreen(date: _dateKey(digest.date))),
    );
    if (deleted == true) {
      setState(() {
        _changed = true;
        _digests = [
          for (final item in _digests)
            if (_dateKey(item.date) != _dateKey(digest.date)) item
        ];
      });
    } else {
      _load();
    }
  }

  String _dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _changed);
        return false;
      },
      child: Scaffold(
        backgroundColor: AppColors.homeBackground,
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _load,
            color: AppColors.homeAccent,
            backgroundColor: AppColors.homeCard,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                _topBar(),
                const SizedBox(height: 24),
                const Text(
                  'Daily Recaps',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: AppColors.homeInk,
                  ),
                ),
                const SizedBox(height: 18),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: Center(child: CircularProgressIndicator(color: AppColors.homeAccent)),
                  )
                else if (_error != null)
                  _messageCard(_error!)
                else if (_digests.isEmpty)
                  _messageCard('No recaps yet.')
                else
                  ..._digests.map(_recapTile),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context, _changed),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.homeCard,
              border: Border.all(color: AppColors.homeBorder),
              borderRadius: BorderRadius.circular(21),
            ),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: AppColors.homeMuted,
              size: 20,
            ),
          ),
        ),
      ],
    );
  }

  Widget _messageCard(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.homeCard,
        border: Border.all(color: AppColors.homeBorder),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.homeMuted,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _recapTile(Digest digest) {
    return GestureDetector(
      onTap: () => _openRecap(digest),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.homeCard,
          border: Border.all(color: AppColors.homeBorder),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.mic_none_rounded, color: AppColors.homeAccent, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    digest.dateLabel,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.homeMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    digest.shortSummary,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.homeInk,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: AppColors.homeMuted, size: 22),
          ],
        ),
      ),
    );
  }
}
