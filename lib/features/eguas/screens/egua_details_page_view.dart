import 'package:flutter/material.dart';
import 'package:nobryo_final/core/models/egua_model.dart';
import 'package:nobryo_final/features/eguas/screens/egua_details_screen.dart';

class EguaDetailsPageView extends StatefulWidget {
  final List<Egua> eguas;
  final int initialIndex;
  final String propriedadeMaeId;

  const EguaDetailsPageView({
    super.key,
    required this.eguas,
    required this.initialIndex,
    required this.propriedadeMaeId,
  });

  @override
  State<EguaDetailsPageView> createState() => _EguaDetailsPageViewState();
}

class _EguaDetailsPageViewState extends State<EguaDetailsPageView> {
  late final PageController _pageController;
  late List<Egua> _currentEguasList;

  @override
  void initState() {
    super.initState();
    _currentEguasList = List.from(widget.eguas);
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onEguaDeleted(String eguaId) {
    if (!mounted) return;
    final index = _currentEguasList.indexWhere((egua) => egua.id == eguaId);
    if (index != -1) {
      setState(() {
        _currentEguasList.removeAt(index);
      });
      if (_currentEguasList.isEmpty) {
        Navigator.of(context).pop();
      }
    }
  }


  void _onEguaUpdated(Egua updatedEgua) {
    if (!mounted) return;
    final index = _currentEguasList.indexWhere((egua) => egua.id == updatedEgua.id);
    if (index != -1) {
      setState(() {
        _currentEguasList[index] = updatedEgua;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentEguasList.isEmpty) {
      return const Scaffold(
        body: Center(
          child: Text("Nenhuma égua para exibir."),
        ),
      );
    }

    return PageView.builder(
      controller: _pageController,
      itemCount: _currentEguasList.length,
      itemBuilder: (context, index) {
        return EguaDetailsScreen(
          egua: _currentEguasList[index],
          onEguaDeleted: (deletedEguaId) => _onEguaDeleted(deletedEguaId),
          onEguaUpdated: _onEguaUpdated,
          propriedadeMaeId: widget.propriedadeMaeId,
        );
      },
    );
  }
}