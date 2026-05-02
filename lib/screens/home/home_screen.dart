import 'package:flutter/material.dart';
import '../members/members_screen.dart';
import '../check_ins/check_ins_screen.dart';
import '../revenue/revenue_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../products/products_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  void _navigateToTab(int index) {
    setState(() => _currentIndex = index);
  }

  List<Widget> get _screens => [
    DashboardScreen(onNavigateToTab: _navigateToTab),
    const MembersScreen(),
    const CheckInsScreen(),
    const RevenueScreen(),
    const ProductsScreen(),
  ];

  final List<NavigationDestination> _destinations = const [
    NavigationDestination(
      icon: Icon(Icons.dashboard_outlined),
      selectedIcon: Icon(Icons.dashboard),
      label: 'Acasa',
    ),
    NavigationDestination(
      icon: Icon(Icons.people_outlined),
      selectedIcon: Icon(Icons.people),
      label: 'Membri',
    ),
    NavigationDestination(
      icon: Icon(Icons.check_circle_outlined),
      selectedIcon: Icon(Icons.check_circle),
      label: 'Check-ins',
    ),
    NavigationDestination(
      icon: Icon(Icons.attach_money_outlined),
      selectedIcon: Icon(Icons.attach_money),
      label: 'Venituri',
    ),
    NavigationDestination(
      icon: Icon(Icons.inventory_2_outlined),
      selectedIcon: Icon(Icons.inventory_2),
      label: 'Produse',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: _destinations,
      ),
    );
  }
}
