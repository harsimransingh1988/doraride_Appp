import 'package:flutter/material.dart';

/// Generic layout wrapper for onboarding screens.
/// - Centers content.
/// - Adds maxWidth.
/// - Makes page scrollable on small devices.
class OnboardingLayout extends StatelessWidget {
  final Color backgroundColor;
  final PreferredSizeWidget? appBar;
  final Widget child;
  final EdgeInsets padding;

  const OnboardingLayout({
    super.key,
    required this.backgroundColor,
    required this.child,
    this.appBar,
    this.padding = const EdgeInsets.all(24),
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: appBar,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: padding,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 600,                    // ✅ nice width on web
                    minHeight: constraints.maxHeight, // ✅ fill height on tall screens
                  ),
                  child: child,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
