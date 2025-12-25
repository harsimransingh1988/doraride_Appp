import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../app_router.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});
  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage>
    with TickerProviderStateMixin {
  late final AnimationController _logoCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  late final Animation<double> _logoFade =
      CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOut);

  late final Animation<Offset> _logoSlide = Tween<Offset>(
    begin: const Offset(0, .08),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutCubic));

  late final AnimationController _btnCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  late final Animation<double> _btnFade =
      CurvedAnimation(parent: _btnCtrl, curve: Curves.easeOut);

  late final Animation<Offset> _btnSlide = Tween<Offset>(
    begin: const Offset(0, .2),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _btnCtrl, curve: Curves.easeOutBack));

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) _btnCtrl.forward();
    });
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _btnCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.green,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 32),
              FadeTransition(
                opacity: _logoFade,
                child: SlideTransition(
                  position: _logoSlide,
                  child: Column(
                    children: const [
                      // your white logo
                      Image(
                        image: AssetImage('assets/logo_white.png'),
                        height: 160,
                        fit: BoxFit.contain,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'DoraRide',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 52,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Expanded(
                child: Center(
                  child: Text(
                    'Ride Smart.\nRide Together.\nSmile on Every Ride.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 50,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                ),
              ),
              SlideTransition(
                position: _btnSlide,
                child: FadeTransition(
                  opacity: _btnFade,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 32),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 300,
                        minHeight: 50,
                      ),
                      child: ElevatedButton(
                        onPressed: () =>
                            Navigator.pushNamed(context, Routes.welcome),
                        child: const Text("Let's go"),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
