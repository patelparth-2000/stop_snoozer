import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/color_constants.dart';
import '../../core/constants/app_constants.dart';

const _prefKey = 'onboarding_shown';

Future<bool> shouldShowOnboarding() async {
  final prefs = await SharedPreferences.getInstance();
  return !(prefs.getBool(_prefKey) ?? false);
}

Future<void> markOnboardingShown() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_prefKey, true);
}

// ── Step data ──────────────────────────────────────────────────────────────

class _Step {
  const _Step({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;
}

const _steps = [
  _Step(
    icon: Icons.search_rounded,
    title: 'Search for your stop',
    body: 'Tap the search bar and find any bus stop, tube station or rail platform in the UK.',
  ),
  _Step(
    icon: Icons.sensors_rounded,
    title: 'Arm your journey',
    body: 'Set your destination stop. StopSnoozer tracks your location in the background — even when the app is closed.',
  ),
  _Step(
    icon: Icons.notifications_active_rounded,
    title: 'Get alerted when you arrive',
    body: 'Your phone rings and a full-screen alarm appears the moment you reach your stop. Never miss it.',
  ),
];

// ── Overlay widget ─────────────────────────────────────────────────────────

class OnboardingOverlay extends StatefulWidget {
  const OnboardingOverlay({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<OnboardingOverlay> createState() => _OnboardingOverlayState();
}

class _OnboardingOverlayState extends State<OnboardingOverlay>
    with SingleTickerProviderStateMixin {
  int _page = 0;
  late final PageController _ctrl;
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = PageController();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1.0,
    );
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _steps.length - 1) {
      _ctrl.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _done();
    }
  }

  Future<void> _done() async {
    await markOnboardingShown();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: Container(
        color: Colors.black.withValues(alpha: 0.82),
        child: SafeArea(
          child: Column(
            children: [
              // Skip button
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.containerMargin),
                  child: GestureDetector(
                    onTap: _done,
                    child: Text(
                      'Skip',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: ColorConstants.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),

              // Page content
              Expanded(
                child: PageView.builder(
                  controller: _ctrl,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemCount: _steps.length,
                  itemBuilder: (_, i) => _StepPage(step: _steps[i]),
                ),
              ),

              // Dots + button
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.containerMargin,
                  0,
                  AppConstants.containerMargin,
                  AppConstants.spaceLg,
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _steps.length,
                        (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: i == _page ? 20 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i == _page
                                ? ColorConstants.primary
                                : ColorConstants.textDisabled,
                            borderRadius:
                                BorderRadius.circular(AppConstants.radiusFull),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppConstants.spaceLg),
                    SizedBox(
                      width: double.infinity,
                      child: GestureDetector(
                        onTap: _next,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: ColorConstants.primary,
                            borderRadius: BorderRadius.circular(
                                AppConstants.radiusFull),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            _page < _steps.length - 1 ? 'Next' : 'Get Started',
                            style: GoogleFonts.sora(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Single step page ───────────────────────────────────────────────────────

class _StepPage extends StatelessWidget {
  const _StepPage({required this.step});
  final _Step step;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.containerMargin * 1.5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: ColorConstants.primarySubtle,
              shape: BoxShape.circle,
              border: Border.all(color: ColorConstants.primaryGlow, width: 1.5),
            ),
            child: Icon(step.icon, color: ColorConstants.primary, size: 44),
          ),
          const SizedBox(height: 32),
          Text(
            step.title,
            textAlign: TextAlign.center,
            style: GoogleFonts.sora(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            step.body,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 15,
              color: ColorConstants.textSecondary,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
