import 'package:flutter/material.dart';

class AcademyInstallHelp extends StatelessWidget {
  const AcademyInstallHelp({super.key});

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Install Al Hassan Academy'),
    content: const SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Android', style: TextStyle(fontWeight: FontWeight.bold)),
          Text(
            'Open this website in Chrome. Tap the three-dot menu, then Install app or Add to Home screen.',
          ),
          SizedBox(height: 18),
          Text('iPhone / iPad', style: TextStyle(fontWeight: FontWeight.bold)),
          Text(
            'Open this website in Safari. Tap Share, then Add to Home Screen. Keep Open as Web App enabled if shown, then tap Add.',
          ),
          SizedBox(height: 18),
          Text('Desktop', style: TextStyle(fontWeight: FontWeight.bold)),
          Text(
            'In Chrome or Edge, use the install icon in the address bar or the browser’s app installation menu.',
          ),
          SizedBox(height: 18),
          Text(
            'Use your usual academy account on every device. Internet access is required for lessons, messages, and records.',
          ),
          SizedBox(height: 12),
          Text(
            'You can watch a teacher’s shared screen on your phone. Sharing your own phone screen is not supported by most mobile browsers.',
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Got it'),
      ),
    ],
  );
}
