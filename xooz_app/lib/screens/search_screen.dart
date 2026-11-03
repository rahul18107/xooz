import '../theme/app_theme.dart';
import 'package:flutter/material.dart';

class SearchCategory {
  final String title;
  final IconData icon;
  final int count;
  final Color iconColor;

  SearchCategory({
    required this.title,
    required this.icon,
    required this.count,
    required this.iconColor,
  });
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _isSearching = false;

  final List<SearchCategory> _categories = [
    SearchCategory(
      title: 'Starred',
      icon: Icons.star_outline,
      count: 0,
      iconColor: AppColors.ink,
    ),
    SearchCategory(
      title: 'Work',
      icon: Icons.work_outline,
      count: 0,
      iconColor: AppColors.accent,
    ),
    SearchCategory(
      title: 'Personal',
      icon: Icons.favorite_outline,
      count: 0,
      iconColor: AppColors.ink,
    ),
    SearchCategory(
      title: 'Social',
      icon: Icons.group_outlined,
      count: 0,
      iconColor: AppColors.accent,
    ),
    SearchCategory(
      title: 'Recaps',
      icon: Icons.calendar_today_outlined,
      count: 0,
      iconColor: AppColors.ink,
    ),
    SearchCategory(
      title: 'Memories',
      icon: Icons.psychology_outlined,
      count: 0,
      iconColor: AppColors.accent,
    ),
    SearchCategory(
      title: 'People',
      icon: Icons.people_outline,
      count: 0,
      iconColor: AppColors.ink,
    ),
    SearchCategory(
      title: 'Places',
      icon: Icons.place_outlined,
      count: 0,
      iconColor: AppColors.accent,
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchBar(context),
            Expanded(
              child: _isSearching
                  ? _buildSearchResults()
                  : _buildCategoryGrid(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: const Border.fromBorderSide(
                  BorderSide(color: AppColors.homeBorder),
                ),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: AppColors.muted, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        color: AppColors.ink,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Search',
                        hintStyle: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          color: AppColors.muted,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 14),
                      ),
                      onChanged: (value) {
                        setState(() => _isSearching = value.isNotEmpty);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                color: AppColors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.2,
      ),
      itemCount: _categories.length,
      itemBuilder: (context, index) {
        final category = _categories[index];
        return _buildCategoryCard(category);
      },
    );
  }

  Widget _buildCategoryCard(SearchCategory category) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: const Border.fromBorderSide(
            BorderSide(color: AppColors.homeBorder),
          ),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(category.icon, color: AppColors.ink, size: 22),
                Text(
                  category.count.toString(),
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              category.title,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: AppColors.cardMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    return Center(
      child: Text(
        'Search coming soon',
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          color: AppColors.muted,
        ),
      ),
    );
  }
}
