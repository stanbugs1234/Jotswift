import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/dialogs.dart';
import '../notebooks/domain/notebook_models.dart' show notebookColors;
import '../reminders/reminders.dart';
import 'calendar_providers.dart';
import 'domain/event.dart';

/// Opens the editor for [event], or for a new event starting at [start]
/// (all day if [allDay]).
Future<void> showEventEditor(
  BuildContext context, {
  CalendarEvent? event,
  DateTime? start,
  bool allDay = false,
}) {
  final now = DateTime.now();
  final begin =
      start ?? DateTime(now.year, now.month, now.day, min(now.hour + 1, 23));
  final initial =
      event ??
      CalendarEvent(
        id: '',
        title: '',
        allDay: allDay,
        start: allDay ? Day.of(begin).toDateTime() : begin,
        end: allDay
            ? Day.of(begin).toDateTime()
            : begin.add(const Duration(hours: 1)),
        color: notebookColors.first,
      );
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (context) => EventEditor(initial: initial),
    ),
  );
}

class EventEditor extends ConsumerStatefulWidget {
  const EventEditor({required this.initial, super.key});

  final CalendarEvent initial;

  @override
  ConsumerState<EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends ConsumerState<EventEditor> {
  late final _title = TextEditingController(text: widget.initial.title);
  late final _notes = TextEditingController(text: widget.initial.notes);
  late bool _allDay = widget.initial.allDay;
  late DateTime _start = widget.initial.start;
  late DateTime _end = widget.initial.end;
  late int _color = widget.initial.color;
  late Recurrence? _repeat = widget.initial.recurrence;

  /// Minutes before the start; null for no alert. See
  /// [CalendarEvent.reminderMinutes].
  late int? _alert = widget.initial.reminderMinutes.firstOrNull;

  bool get _isNew => widget.initial.id.isEmpty;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    ref
        .read(eventRepositoryProvider)
        .saveEvent(
          widget.initial.copyWith(
            title: title.isEmpty ? 'New event' : title,
            notes: _notes.text.trim(),
            allDay: _allDay,
            start: _allDay ? Day.of(_start).toDateTime() : _start,
            end: _allDay ? Day.of(_end).toDateTime() : _end,
            color: _color,
            recurrence: _repeat,
            clearRecurrence: _repeat == null,
            reminderMinutes: [?_validAlert],
          ),
        );
    if (_validAlert != null) {
      ref.read(reminderServiceProvider).requestPermission();
    }
    Navigator.pop(context);
  }

  /// The alert choices: timed events count back from the start; all-day
  /// events from midnight, so 9 AM on the day is -540.
  List<(int?, String)> get _alertChoices => _allDay
      ? const [
          (null, 'None'),
          (-540, 'On the day (9 AM)'),
          (900, 'The day before (9 AM)'),
        ]
      : const [
          (null, 'None'),
          (0, 'At the start'),
          (5, '5 minutes before'),
          (15, '15 minutes before'),
          (30, '30 minutes before'),
          (60, '1 hour before'),
          (1440, '1 day before'),
        ];

  /// The alert, if it suits all-day or timed as currently chosen.
  int? get _validAlert =>
      _alertChoices.any((c) => c.$1 == _alert) ? _alert : null;

  Future<void> _delete() async {
    final ok = await confirmDelete(
      context,
      title: 'Delete this event?',
      message: _repeat == null
          ? 'It will be removed from your calendar.'
          : 'Every repeat of it will be removed.',
    );
    if (!ok || !mounted) return;
    await ref.read(eventRepositoryProvider).deleteEvent(widget.initial.id);
    if (mounted) Navigator.pop(context);
  }

  /// Changes the start, keeping the length (moving the end with it).
  void _setStart(DateTime start) {
    final length = _end.difference(_start);
    setState(() {
      _start = start;
      _end = start.add(length);
    });
  }

  void _setEnd(DateTime end) => setState(() {
    _end = end.isBefore(_start) ? _start : end;
  });

  Future<DateTime?> _pickDay(DateTime initial) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
    );
    if (picked == null) return null;
    return DateTime(
      picked.year,
      picked.month,
      picked.day,
      initial.hour,
      initial.minute,
    );
  }

  Future<DateTime?> _pickTime(DateTime initial) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (picked == null) return null;
    return DateTime(
      initial.year,
      initial.month,
      initial.day,
      picked.hour,
      picked.minute,
    );
  }

  Widget _when(String label, DateTime value, ValueChanged<DateTime> onChanged) {
    final local = MaterialLocalizations.of(context);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(width: 64, child: Text(label)),
        TextButton(
          onPressed: () async {
            final d = await _pickDay(value);
            if (d != null) onChanged(d);
          },
          child: Text(local.formatMediumDate(value)),
        ),
        if (!_allDay)
          TextButton(
            onPressed: () async {
              final t = await _pickTime(value);
              if (t != null) onChanged(t);
            },
            child: Text(local.formatTimeOfDay(TimeOfDay.fromDateTime(value))),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final local = MaterialLocalizations.of(context);
    final repeat = _repeat;

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(_isNew ? 'New event' : 'Edit event'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(onPressed: _save, child: const Text('Save')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            controller: _title,
            autofocus: _isNew,
            style: theme.textTheme.titleLarge,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Title'),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('All day'),
            value: _allDay,
            onChanged: (v) => setState(() => _allDay = v),
          ),
          _when('Starts', _start, _setStart),
          _when('Ends', _end, _setEnd),
          const SizedBox(height: 16),
          DropdownButtonFormField<Frequency?>(
            initialValue: repeat?.frequency,
            decoration: const InputDecoration(labelText: 'Repeat'),
            items: const [
              DropdownMenuItem(value: null, child: Text('Never')),
              DropdownMenuItem(
                value: Frequency.daily,
                child: Text('Every day'),
              ),
              DropdownMenuItem(
                value: Frequency.weekly,
                child: Text('Every week'),
              ),
              DropdownMenuItem(
                value: Frequency.monthly,
                child: Text('Every month'),
              ),
              DropdownMenuItem(
                value: Frequency.yearly,
                child: Text('Every year'),
              ),
            ],
            onChanged: (f) => setState(() {
              _repeat = f == null
                  ? null
                  : (repeat ?? Recurrence(f)).copyWith(frequency: f);
            }),
          ),
          if (repeat?.frequency == Frequency.weekly)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                spacing: 6,
                children: [
                  for (var i = 0; i < 7; i++)
                    // Monday first; narrowWeekdays starts on Sunday.
                    _weekdayChip(local.narrowWeekdays[(i + 1) % 7], i + 1),
                ],
              ),
            ),
          if (repeat != null)
            Row(
              children: [
                const SizedBox(width: 64, child: Text('Until')),
                TextButton(
                  onPressed: () async {
                    final d = await _pickDay(
                      repeat.until?.toDateTime() ?? _start,
                    );
                    if (d != null) {
                      setState(
                        () => _repeat = repeat.copyWith(until: Day.of(d)),
                      );
                    }
                  },
                  child: Text(
                    repeat.until == null
                        ? 'Forever'
                        : local.formatMediumDate(repeat.until!.toDateTime()),
                  ),
                ),
                if (repeat.until != null)
                  IconButton(
                    tooltip: 'Repeat forever',
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(
                      () => _repeat = repeat.copyWith(clearUntil: true),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int?>(
            key: ValueKey(_allDay),
            initialValue: _validAlert,
            decoration: const InputDecoration(labelText: 'Alert'),
            items: [
              for (final (value, label) in _alertChoices)
                DropdownMenuItem(value: value, child: Text(label)),
            ],
            onChanged: (v) => setState(() => _alert = v),
          ),
          const SizedBox(height: 16),
          Text('Color', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final (i, c) in notebookColors.indexed)
                Semantics(
                  button: true,
                  selected: c == _color,
                  label: 'Color ${i + 1}',
                  excludeSemantics: true,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => _color = c),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: Color(c),
                      child: c == _color
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 18,
                            )
                          : null,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _notes,
            minLines: 2,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Notes',
              border: OutlineInputBorder(),
            ),
          ),
          if (!_isNew) ...[
            const SizedBox(height: 24),
            if (repeat != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Changes apply to every repeat.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete event'),
                onPressed: _delete,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _weekdayChip(String label, int weekday) {
    final rule = _repeat!;
    final days = rule.weekdays.isEmpty ? {_start.weekday} : rule.weekdays;
    final on = days.contains(weekday);
    return FilterChip(
      label: Text(label),
      selected: on,
      showCheckmark: false,
      onSelected: (selected) {
        final next = {...days};
        selected ? next.add(weekday) : next.remove(weekday);
        if (next.isEmpty) return;
        setState(() => _repeat = rule.copyWith(weekdays: next));
      },
    );
  }
}
