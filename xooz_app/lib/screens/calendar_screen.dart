import 'package:flutter/material.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _selectedDate = DateTime.now();
  DateTime _focusedMonth = DateTime.now();

  final List<String> _weekDays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
  final List<String> _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  void _previousMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
    });
  }

  List<DateTime?> _getDaysInMonth() {
    final firstDay = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final lastDay = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);
    final List<DateTime?> days = [];

    // add empty slots for days before first day of month
    for (int i = 0; i < firstDay.weekday % 7; i++) {
      days.add(null);
    }

    for (int i = 1; i <= lastDay.day; i++) {
      days.add(DateTime(_focusedMonth.year, _focusedMonth.month, i));
    }

    return days;
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  bool _isSelected(DateTime date) {
    return date.year == _selectedDate.year &&
        date.month == _selectedDate.month &&
        date.day == _selectedDate.day;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A0A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHandle(),
            _buildTopBar(context),
            _buildMonthSelector(),
            _buildWeekDayHeaders(),
            _buildDaysGrid(),
            _buildDoneButton(context),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildHandle() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: const Color(0xFF3A3530),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          const Text(
            'Filter by date',
            style: TextStyle(
              fontFamily: 'DMSerifDisplay',
              fontSize: 20,
              color: Color(0xFFE8DFD0),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(
              Icons.close,
              color: Color(0xFF6B6460),
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {},
            child: Row(
              children: [
                Text(
                  '${_months[_focusedMonth.month - 1]} ${_focusedMonth.year}',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFE8DFD0),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.keyboard_arrow_down,
                  color: Color(0xFF6B6460),
                  size: 18,
                ),
              ],
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _previousMonth,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1512),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.chevron_left,
                color: Color(0xFF6B6460),
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _nextMonth,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1512),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.chevron_right,
                color: Color(0xFF6B6460),
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekDayHeaders() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: _weekDays
            .map(
              (day) => SizedBox(
                width: 36,
                child: Center(
                  child: Text(
                    day,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      color: Color(0xFF6B6460),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildDaysGrid() {
    final days = _getDaysInMonth();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          childAspectRatio: 1,
        ),
        itemCount: days.length,
        itemBuilder: (context, index) {
          final date = days[index];
          if (date == null) return const SizedBox();
          return GestureDetector(
            onTap: () => setState(() => _selectedDate = date),
            child: Container(
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: _isSelected(date)
                    ? const Color(0xFFE8DFD0)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Center(
                child: Text(
                  date.day.toString(),
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: _isToday(date)
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: _isSelected(date)
                        ? const Color(0xFF0A0A0A)
                        : _isToday(date)
                            ? const Color(0xFFC8B89A)
                            : const Color(0xFFE8DFD0),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDoneButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: GestureDetector(
        onTap: () => Navigator.pop(context, _selectedDate),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFE8DFD0),
            borderRadius: BorderRadius.circular(30),
          ),
          child: const Center(
            child: Text(
              'Done',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0A0A0A),
              ),
            ),
          ),
        ),
      ),
    );
  }
}