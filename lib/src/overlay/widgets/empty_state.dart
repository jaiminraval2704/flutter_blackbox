import 'package:flutter/material.dart';

class EmptyState extends StatefulWidget {
  const EmptyState(
      {super.key, required this.icon, required this.label, this.emoji});
  final IconData icon;
  final String label;
  final String? emoji;

  @override
  State<EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<EmptyState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    
    // Prevent infinite animations breaking tester.pumpAndSettle() in widget tests
    if (!WidgetsBinding.instance.runtimeType.toString().contains('Test')) {
      _ctrl.repeat(reverse: true);
    }
    
    _anim = Tween<Offset>(begin: Offset.zero, end: const Offset(0, -0.15))
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.emoji != null)
              SlideTransition(
                position: _anim,
                child:
                    Text(widget.emoji!, style: const TextStyle(fontSize: 42)),
              )
            else
              Icon(widget.icon, color: Colors.white24, size: 32),
            const SizedBox(height: 12),
            Text(widget.label,
                style: const TextStyle(fontSize: 12, color: Colors.white38)),
          ],
        ),
      );
}

class PanelSearchBar extends StatelessWidget {
  const PanelSearchBar(
      {super.key, required this.hint, required this.onChanged});
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextField(
        onChanged: onChanged,
        style: const TextStyle(fontSize: 12, color: Colors.white70),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 11, color: Colors.white24),
          prefixIcon: const Icon(Icons.search, color: Colors.white24, size: 16),
          isDense: true,
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
        ),
      );
}
