import 'package:flutter/material.dart';

class FeatureItem {
  final IconData icon;
  final String label;
  final Color color;
  final WidgetBuilder destination;

  const FeatureItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.destination,
  });
}

class CategoryDetailScreen extends StatelessWidget {
  final String title;
  final List<Color> headerGradient;
  final IconData headerIcon;
  final List<FeatureItem> features;
  final bool comingSoon;

  const CategoryDetailScreen({
    super.key,
    required this.title,
    required this.headerGradient,
    required this.headerIcon,
    this.features = const [],
    this.comingSoon = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: comingSoon ? _buildComingSoon() : _buildFeatures(context),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: headerGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(headerIcon, size: 44, color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComingSoon() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.construction_rounded, size: 72, color: Colors.amber.shade700),
          ),
          const SizedBox(height: 28),
          const Text(
            'Implement Soon',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'This feature is currently being\nbuilt. Stay tuned!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Colors.grey.shade600, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatures(BuildContext context) {
    if (features.length == 1) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _FeatureTile(
            item: features.first,
            size: 180,
            iconSize: 72,
            fontSize: 20,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: GridView.count(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: features
            .map((f) => _FeatureTile(item: f, size: 150, iconSize: 56, fontSize: 16))
            .toList(),
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  final FeatureItem item;
  final double size;
  final double iconSize;
  final double fontSize;

  const _FeatureTile({
    required this.item,
    required this.size,
    required this.iconSize,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: item.destination),
      ),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: item.color,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: item.color.withValues(alpha: 0.45),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(item.icon, size: iconSize, color: Colors.white),
            ),
            const SizedBox(height: 14),
            Text(
              item.label,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
