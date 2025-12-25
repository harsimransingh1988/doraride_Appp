// lib/features/onboarding/widgets/onboarding_scaffold.dart
import 'package:flutter/material.dart';

const _kThemeBlue = Color(0xFF180D3B);
const _kThemeGreen = Color(0xFF279C56);

class OnboardingScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget content;
  final String buttonText;
  final VoidCallback onNext;
  final bool showBackButton;

  const OnboardingScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.content,
    required this.buttonText,
    required this.onNext,
    this.showBackButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenWidth = mq.size.width;
    final screenHeight = mq.size.height;

    // ✅ Responsive title size (smaller on narrow screens)
    double titleSize;
    if (screenWidth < 340) {
      titleSize = 22;
    } else if (screenWidth < 400) {
      titleSize = 24;
    } else if (screenWidth < 500) {
      titleSize = 26;
    } else {
      titleSize = 30;
    }

    // ✅ Limit content width on very wide screens (web/tablet)
    final maxContentWidth = screenWidth > 600 ? 600.0 : screenWidth;

    return Scaffold(
      backgroundColor: _kThemeGreen,
      appBar: AppBar(
        backgroundColor: _kThemeGreen,
        elevation: 0,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: showBackButton,
        centerTitle: true,
        title: const Text(
          'Onboarding',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ✅ Scrollable content area
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: maxContentWidth,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 16),

                              // Subtitle (optional, smaller text)
                              if (subtitle != null)
                                Text(
                                  subtitle!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                        color: Colors.white70,
                                        fontWeight: FontWeight.w500,
                                      ),
                                  textAlign: TextAlign.left,
                                ),
                              if (subtitle != null)
                                const SizedBox(height: 4),

                              // Main heading
                              Text(
                                title,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      fontSize: titleSize,
                                    ),
                                textAlign: TextAlign.left,
                              ),

                              const SizedBox(height: 24),

                              // Content (images / text etc.)
                              content,

                              // Extra space so content never hides behind button
                              SizedBox(height: screenHeight * 0.08),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // ✅ Fixed bottom button
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: onNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kThemeBlue,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                    buttonText, // ✅ use the passed label
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
