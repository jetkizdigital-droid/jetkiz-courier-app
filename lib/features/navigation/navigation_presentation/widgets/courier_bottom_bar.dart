import 'package:flutter/material.dart';

class CourierBottomBar extends StatelessWidget {
  const CourierBottomBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFF41A62A);
    const inactiveColor = Color(0xFF7E8794);
    const barBackground = Colors.white;
    const barBorderColor = Color(0xFFE9EDF2);

    return SafeArea(
      top: false,
      bottom: true,
      child: Container(
        height: 84,
        width: double.infinity,
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        decoration: const BoxDecoration(
          color: barBackground,
          border: Border(top: BorderSide(color: barBorderColor, width: 1)),
          boxShadow: [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 18,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            _NavItem(
              icon: Icons.home_outlined,
              activeIcon: Icons.home_rounded,
              label: 'Главная',
              isActive: currentIndex == 0,
              activeColor: activeColor,
              inactiveColor: inactiveColor,
              onTap: () => onTap(0),
            ),
            const SizedBox(width: 8),
            _NavItem(
              icon: Icons.receipt_long_outlined,
              activeIcon: Icons.receipt_long_rounded,
              label: 'Заказы',
              isActive: currentIndex == 1,
              activeColor: activeColor,
              inactiveColor: inactiveColor,
              onTap: () => onTap(1),
            ),
            const SizedBox(width: 8),
            _NavItem(
              icon: Icons.account_balance_wallet_outlined,
              activeIcon: Icons.account_balance_wallet_rounded,
              label: 'Финансы',
              isActive: currentIndex == 2,
              activeColor: activeColor,
              inactiveColor: inactiveColor,
              onTap: () => onTap(2),
            ),
            const SizedBox(width: 8),
            _NavItem(
              icon: Icons.person_outline_rounded,
              activeIcon: Icons.person_rounded,
              label: 'Профиль',
              isActive: currentIndex == 3,
              activeColor: activeColor,
              inactiveColor: inactiveColor,
              onTap: () => onTap(3),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foregroundColor = isActive ? activeColor : inactiveColor;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFFF6FFF2) : Colors.transparent,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: isActive ? activeColor : Colors.transparent,
                width: 1.8,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isActive ? activeIcon : icon,
                  size: 22,
                  color: foregroundColor,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.1,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                    color: foregroundColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
