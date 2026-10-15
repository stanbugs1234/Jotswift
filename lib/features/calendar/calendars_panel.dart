import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'calendar_providers.dart';
import 'domain/event.dart';

/// The user's calendars, each with a checkbox to show or hide its events,
/// and a way to add or edit them.
class CalendarsPanel extends ConsumerWidget {
  const CalendarsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final calendars =
        ref.watch(calendarsProvider).value ?? const [CalendarInfo.personal];
    final repo = ref.read(calendarRepositoryProvider);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text('Calendars', style: theme.textTheme.titleMedium),
        ),
        for (final c in calendars)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 8, right: 4),
            leading: Checkbox(
              value: c.visible,
              activeColor: Color(c.color),
              side: BorderSide(color: Color(c.color), width: 2),
              semanticLabel: 'Show ${c.name}',
              onChanged: (v) => repo.saveCalendar(c.copyWith(visible: v)),
            ),
            title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              tooltip: 'Edit ${c.name}',
              iconSize: 18,
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => showCalendarEditor(context, calendar: c),
            ),
            onTap: () => repo.saveCalendar(c.copyWith(visible: !c.visible)),
          ),
        ListTile(
          dense: true,
          leading: const Padding(
            padding: EdgeInsets.only(left: 12),
            child: Icon(Icons.add),
          ),
          title: const Text('New calendar'),
          onTap: () => showCalendarEditor(context),
        ),
      ],
    );
  }
}

/// Shows the panel in a sheet, for screens too narrow to keep it beside
/// the calendar.
Future<void> showCalendarsSheet(BuildContext context) => showModalBottomSheet(
  context: context,
  showDragHandle: true,
  builder: (_) => const SafeArea(child: CalendarsPanel()),
);

/// Adds a calendar, or edits [calendar] (rename, recolour, delete).
Future<void> showCalendarEditor(
  BuildContext context, {
  CalendarInfo? calendar,
}) => showDialog<void>(
  context: context,
  builder: (_) => _CalendarEditor(calendar: calendar),
);

class _CalendarEditor extends ConsumerStatefulWidget {
  const _CalendarEditor({this.calendar});

  final CalendarInfo? calendar;

  @override
  ConsumerState<_CalendarEditor> createState() => _CalendarEditorState();
}

class _CalendarEditorState extends ConsumerState<_CalendarEditor> {
  late final _name = TextEditingController(text: widget.calendar?.name ?? '');
  late int _color = widget.calendar?.color ?? calendarColors[8];

  bool get _isNew => widget.calendar == null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final repo = ref.read(calendarRepositoryProvider);
    final existing = widget.calendar;
    if (existing == null) {
      final count = ref.read(calendarsProvider).value?.length ?? 1;
      repo.saveCalendar(
        CalendarInfo(
          id: '',
          name: name,
          color: _color,
          order: count.toDouble(),
        ),
      );
    } else {
      repo.saveCalendar(existing.copyWith(name: name, color: _color));
    }
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final calendar = widget.calendar!;
    final choice = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${calendar.name}?'),
        content: const Text(
          'Its events can move to Personal, or be deleted with it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete events too'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Move to Personal'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    await deleteCalendar(ref, calendar, deleteEvents: choice);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(_isNew ? 'New calendar' : 'Edit calendar'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              autofocus: _isNew,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
              onSubmitted: (_) => _save(),
            ),
            if (_isNew) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final (name, color) in calendarPresets)
                    ActionChip(
                      avatar: CircleAvatar(backgroundColor: Color(color)),
                      label: Text(name),
                      onPressed: () => setState(() {
                        _name.text = name;
                        _color = color;
                      }),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Text('Color', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final (i, c) in calendarColors.indexed)
                  Semantics(
                    button: true,
                    selected: c == _color,
                    label: 'Calendar color ${i + 1}',
                    excludeSemantics: true,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => setState(() => _color = c),
                      child: CircleAvatar(
                        radius: 15,
                        backgroundColor: Color(c),
                        child: c == _color
                            ? const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 16,
                              )
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        if (!_isNew && widget.calendar!.id != personalCalendarId)
          TextButton(
            onPressed: _delete,
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: Text(_isNew ? 'Add' : 'Save')),
      ],
    );
  }
}
