import 'package:flutter/material.dart';
import 'package:nobryo_final/features/agenda/screens/agenda_screen.dart';
import 'package:nobryo_final/features/medicamentos/screens/medicamentos_screen.dart';
import 'package:nobryo_final/features/propriedades/screens/propriedades_screen.dart';
import 'package:nobryo_final/shared/widgets/custom_nav_bar.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _widgetOptions = <Widget>[
    AgendaScreen(),
    PropriedadesScreen(),
    MedicamentosScreen(),
  ];

  static const List<BottomNavigationBarItem> _navBarItems = <BottomNavigationBarItem>[
    BottomNavigationBarItem(
      icon: Icon(Icons.calendar_today_outlined),
      activeIcon: Icon(Icons.calendar_today),
      label: 'AGENDA',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.home_outlined),
      activeIcon: Icon(Icons.home),
      label: 'PROPRIEDADES',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.vaccines_outlined),
      activeIcon: Icon(Icons.vaccines),
      label: 'MEDICAMENTOS',
    ),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        child: Container(
          key: ValueKey<int>(_selectedIndex),
          child: _widgetOptions.elementAt(_selectedIndex),
        ),
      ),
      bottomNavigationBar: CustomNavBar(
        items: _navBarItems,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}