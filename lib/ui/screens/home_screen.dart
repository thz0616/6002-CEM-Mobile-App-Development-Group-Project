import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/horn_detection_service.dart';
import '../../data/repositories/settings_repository.dart';
import 'settings_screen.dart';
import 'category_detail_screen.dart';
import 'allergen_home_screen.dart';
import 'macro_planner_screen.dart';
import 'saved_plans_screen.dart';
import 'expiry_tracker_screen.dart';
import 'auto_send_screen.dart';
import 'summarizer_screen.dart';
import 'chat_screen.dart';
import '../../data/services/sms_scam_detection_service.dart';
import 'accounting_screen.dart';
import 'sms_scam_detection_screen.dart';
import 'scan_to_calendar_screen.dart';
import 'medication_validation_screen.dart';
import 'medication_cabinet_screen.dart';

class _CategoryData {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color borderColor;
  final List<Color> gradientColors;
  final VoidCallback onTap;

  const _CategoryData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.borderColor,
    required this.gradientColors,
    required this.onTap,
  });
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  bool _isConsumingSmsScamOpenRequest = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consumeSmsScamOpenRequest();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _consumeSmsScamOpenRequest();
    }
  }

  Future<void> _consumeSmsScamOpenRequest() async {
    if (_isConsumingSmsScamOpenRequest) return;
    _isConsumingSmsScamOpenRequest = true;
    try {
      final shouldOpen =
          await ref.read(smsScamDetectionServiceProvider).consumeOpenRequest();
      if (!mounted || !shouldOpen) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SmsScamDetectionScreen()),
      );
    } finally {
      _isConsumingSmsScamOpenRequest = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final hornService = ref.read(hornDetectionServiceProvider);

    final categories = [
      _CategoryData(
        title: 'Health & Wellness',
        subtitle: 'Allergen detection & food safety',
        icon: Icons.health_and_safety_rounded,
        borderColor: const Color(0xFF43A047),
        gradientColors: const [Color(0xFF1B5E20), Color(0xFF43A047)],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CategoryDetailScreen(
              title: 'Health & Wellness',
              headerGradient: const [Color(0xFF1B5E20), Color(0xFF43A047)],
              headerIcon: Icons.health_and_safety_rounded,
              features: [
                FeatureItem(
                  icon: Icons.restaurant_menu_rounded,
                  label: 'Allergic',
                  color: const Color(0xFFFF6F00),
                  destination: (_) => const AllergenHomeScreen(),
                ),
                FeatureItem(
                  icon: Icons.calendar_month_rounded,
                  label: '7-Day Planner',
                  color: const Color(0xFF1B5E20),
                  destination: (_) => const MacroPlannerScreen(),
                ),
                FeatureItem(
                  icon: Icons.bookmark_rounded,
                  label: 'Meal Plans',
                  color: const Color(0xFF00897B),
                  destination: (_) => const SavedPlansScreen(),
                ),
                FeatureItem(
                  icon: Icons.timer_rounded,
                  label: 'Expiry Tracker',
                  color: const Color(0xFFE53935),
                  destination: (_) => const ExpiryTrackerScreen(),
                ),
                FeatureItem(
                  icon: Icons.medication_rounded,
                  label: 'Medications',
                  color: Colors.blueAccent[700] ?? Colors.blue,
                  destination: (_) => const MedicationCabinetScreen(),
                ),
              ],
            ),
          ),
        ),
      ),
      _CategoryData(
        title: 'Lifestyle Automation',
        subtitle: 'Smart messaging & automation',
        icon: Icons.auto_awesome_rounded,
        borderColor: const Color(0xFF1E88E5),
        gradientColors: const [Color(0xFF0D47A1), Color(0xFF1E88E5)],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CategoryDetailScreen(
              title: 'Lifestyle Automation',
              headerGradient: const [Color(0xFF0D47A1), Color(0xFF1E88E5)],
              headerIcon: Icons.auto_awesome_rounded,
              features: [
                FeatureItem(
                  icon: Icons.send_rounded,
                  label: 'Auto Send',
                  color: const Color(0xFF2E7D32),
                  destination: (_) => const AutoSendScreen(),
                ),
                    FeatureItem(
                      icon: Icons.event,
                      label: 'Scan to Calendar',
                      color: const Color(0xFF1976D2),
                      destination: (_) => const ScanToCalendarScreen(),
                    ),
              ],
            ),
          ),
        ),
      ),
      _CategoryData(
        title: 'Intelligence & Insights',
        subtitle: 'AI-powered summarizer & chatbot',
        icon: Icons.psychology_rounded,
        borderColor: const Color(0xFF8E24AA),
        gradientColors: const [Color(0xFF4A148C), Color(0xFF8E24AA)],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CategoryDetailScreen(
              title: 'Intelligence & Insights',
              headerGradient: const [Color(0xFF4A148C), Color(0xFF8E24AA)],
              headerIcon: Icons.psychology_rounded,
              features: [
                FeatureItem(
                  icon: Icons.summarize_rounded,
                  label: 'Summarizer',
                  color: const Color(0xFF1565C0),
                  destination: (_) => const SummarizerScreen(),
                ),
                FeatureItem(
                  icon: Icons.chat_bubble_rounded,
                  label: 'Chatbot',
                  color: const Color(0xFF6A1B9A),
                  destination: (_) => const ChatScreen(),
                ),
              ],
            ),
          ),
        ),
      ),
      _CategoryData(
        title: 'Financial Intelligence',
        subtitle: 'Smart finance tools',
        icon: Icons.account_balance_wallet_rounded,
        borderColor: const Color(0xFFFB8C00),
        gradientColors: const [Color(0xFFE65100), Color(0xFFFFA726)],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CategoryDetailScreen(
              title: 'Financial Intelligence',
              headerGradient: const [Color(0xFFE65100), Color(0xFFFFA726)],
              headerIcon: Icons.account_balance_wallet_rounded,
              features: [
                FeatureItem(
                  icon: Icons.receipt_long_rounded,
                  label: 'Accounting',
                  color: const Color(0xFF00695C),
                  destination: (_) => const AccountingScreen(),
                ),
                FeatureItem(
                  icon: Icons.message_rounded,
                  label: 'Scam Detection',
                  color: const Color(0xFFB71C1C),
                  destination: (_) => const SmsScamDetectionScreen(),
                ),
              ],
            ),
          ),
        ),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Welcome',
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (settings.showHornProbability)
                        StreamBuilder<Map<String, dynamic>>(
                          stream: hornService.events,
                          builder: (context, snapshot) {
                            double prob = 0.0;
                            if (snapshot.hasData &&
                                snapshot.data!['type'] == 'prob') {
                              prob =
                                  (snapshot.data!['value'] as num).toDouble();
                            }
                            return Text(
                              'Horn: ${(prob * 100).toStringAsFixed(1)}%',
                              style: const TextStyle(
                                  fontSize: 16, color: Colors.grey),
                            );
                          },
                        ),
                      IconButton(
                        icon: const Icon(Icons.settings, size: 28),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SettingsScreen()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Select a category to get started',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const double gap = 14;
                    const double bottomPad = 16;
                    const int count = 4;
                    final double cardH = ((constraints.maxHeight - (count - 1) * gap - bottomPad) / count)
                        .clamp(82.0, 130.0);
                    return ListView.separated(
                      padding: const EdgeInsets.only(bottom: bottomPad),
                      physics: const ClampingScrollPhysics(),
                      itemCount: count,
                      separatorBuilder: (_, __) => const SizedBox(height: gap),
                      itemBuilder: (_, i) => SizedBox(
                        height: cardH,
                        child: _buildCategoryCard(categories[i]),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryCard(_CategoryData cat) {
    return GestureDetector(
      onTap: cat.onTap,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cat.borderColor, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: cat.borderColor.withValues(alpha: 0.15),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cat.borderColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(cat.icon, color: cat.borderColor, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cat.title,
                      style: TextStyle(
                        color: cat.borderColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      cat.subtitle,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: cat.borderColor, size: 28),
            ],
          ),
        ),
      ),
    );
  }
}
