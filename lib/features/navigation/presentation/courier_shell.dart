import 'package:flutter/material.dart';
import 'package:jetkiz_courier_app/features/finance/presentation/finance_page.dart';
import 'package:jetkiz_courier_app/features/home/home_page.dart';
import 'package:jetkiz_courier_app/features/navigation/navigation_presentation/widgets/courier_bottom_bar.dart';
import 'package:jetkiz_courier_app/features/orders/presentation/orders_page.dart';
import 'package:jetkiz_courier_app/features/profile/presentation/profile_page.dart';

class CourierShell extends StatefulWidget {
  const CourierShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<CourierShell> createState() => _CourierShellState();
}

class _CourierShellState extends State<CourierShell> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, 3).toInt();
  }

  void _setTab(int index) {
    final next = index.clamp(0, 3).toInt();
    if (next == _currentIndex) return;
    setState(() => _currentIndex = next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: CourierBottomBar(
        currentIndex: _currentIndex,
        onTap: _setTab,
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const HomePage(),
          const OrdersPage(),
          const FinancePage(),
          const ProfilePage(),
        ],
      ),
    );
  }
}
