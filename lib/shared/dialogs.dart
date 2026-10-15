import 'package:flutter/material.dart';

/// Asks for a short piece of text. Returns null if cancelled.
Future<String?> askForText(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initialValue = '',
  String hint = '',
}) => showDialog<String>(
  context: context,
  builder: (context) => _TextDialog(
    title: title,
    confirmLabel: confirmLabel,
    initialValue: initialValue,
    hint: hint,
  ),
);

/// Owns its text controller, so the controller lives until the dialog has
/// finished animating away.
class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.confirmLabel,
    required this.initialValue,
    required this.hint,
  });

  final String title;
  final String confirmLabel;
  final String initialValue;
  final String hint;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _controller = TextEditingController(text: widget.initialValue)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initialValue.length,
    );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 80,
        decoration: InputDecoration(hintText: widget.hint),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}

/// Asks the user to confirm something that can't be undone.
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
