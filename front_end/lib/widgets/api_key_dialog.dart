import 'package:flutter/material.dart';

class ApiKeyDialog extends StatefulWidget {
  final String currentKey;

  const ApiKeyDialog({super.key, required this.currentKey});

  @override
  State<ApiKeyDialog> createState() => _ApiKeyDialogState();
}

class _ApiKeyDialogState extends State<ApiKeyDialog> {
  late final TextEditingController _ctrl;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.currentKey);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Gemini API Key',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Zam now uses Google Gemini. Get your free API key at aistudio.google.com',
            style: TextStyle(
                fontSize: 13, color: scheme.onSurface.withOpacity(0.6)),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            obscureText: _obscure,
            decoration: InputDecoration(
              hintText: 'AIza...',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              // In production: use url_launcher
            },
            child: const Text(
              'Get free key at aistudio.google.com →',
              style: TextStyle(
                  color: Color(0xFF534AB7),
                  fontSize: 12,
                  decoration: TextDecoration.underline),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF534AB7)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
