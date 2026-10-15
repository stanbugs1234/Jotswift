# Phase 3: To-do, Calendar and Planner

The three tabs that are still placeholders, built in four steps. Each step ships on its own, with tests, an iPad build and a commit. The data follows PLAN.md §4.

| # | Step | What you get |
|---|---|---|
| 10 | **To-do** ✅ | Task lists, typed tasks with due dates and priority, and Today and Upcoming views. Works on the web too. |
| 11 | **Calendar** ✅ | Events with month, week and day views, all-day events, colors and repeats. |
| 12 | **Planner** ✅ | A page per day: the day's events and tasks next to a free ink area. |
| 13 | **Reminders** ✅ | Local notifications for tasks and events. |

## 10. To-do ✅

Built as planned: `lib/features/tasks/`, with 22 tests (date maths, views, both storage backends and the screen).

**Data:**
- `users/{uid}/taskLists/{id}`: `title, color, order`.
- `users/{uid}/tasks/{id}`:
  - `title, notes, done, due ("2026-10-14" or absent), priority (0–3), listId (absent = Inbox), order, createdAt, completedAt`
  - A due date is a calendar day, not a moment in time, so it means the same day in every time zone.

**Screen:**
- **Views:**
  - **Today** (with overdue tasks).
  - **Upcoming** (grouped by day).
  - **Inbox** and each list.
  - On wide screens they sit in a side pane; on phones they're chips.
- **Adding:** type in the box at the top. Tasks added from Today are due today.
- **Each task:**
  - A checkbox, a priority flag, and the due day.
  - Tap to edit the title, notes, due day, priority and list, or to delete.
  - Swipe to delete, with Undo.
- **Lists:**
  - In a list, drag to reorder.
  - Completed tasks fold into a "Completed" section.
  - Create, rename, recolor and delete lists. Deleting a list deletes its tasks, after asking.

**Later:**
- Handwritten tasks (an ink snippet as the title).
- Linking a task to a notebook page.

## 11. Calendar ✅

Built in `lib/features/calendar/`, with 17 tests:
- **Repeats:** every N days, chosen weekdays, monthly on the 31st, February 29, and daylight-saving changes.
- **Which days an event appears on.**
- **Side-by-side layout** of overlapping events.
- **Both storage backends.**
- **The screens.**

**Details:**
- All-day events store `startDay`/`endDay` as calendar days. Timed events store `start`/`end` in milliseconds.
- Each repeat keeps the first event's local clock time.
- Editing a repeating event changes every repeat. Moving or deleting a single repeat comes later.
- **Not yet:** tapping a day to open it in the Planner. That comes with the Planner itself.

**Data:**
- `users/{uid}/events/{id}`: `title, start, end, allDay, color, recurrence, notes, reminderMinutes[]`.
- Recurrence is a simple RRULE subset: daily, weekly on chosen days, monthly or yearly, with an end date or count.

**Screen:**
- **Month view:** a grid with dots, plus the chosen day's agenda.
- **Week and day views:** hour grids with timed events and an all-day row.
- **Event editor:** title, all-day, start and end, color, repeat, notes.
- Tapping a day opens it in the Planner.

## 12. Planner ✅

Built in `lib/features/planner/`, with 10 tests.
- **A day's handwriting** is an ordinary page with the fixed id `planner-YYYY-MM-DD` and notebook id `planner`, so every device opens the same page. It isn't in any notebook, so it never shows on the shelf.
- **Layout:** on tablets the plan and the page sit side by side. On phones they're two tabs, and swiping is off so it doesn't fight with writing.
- **Links:** the Calendar's agenda and Day view open a day in the Planner.
- **Not yet:**
  - Choosing which three tasks make the Top 3. It's the three highest-priority tasks for now.
  - A paper style just for planner pages.


- A planner page per date (`/planner/2026-10-14`), in the default notebook style.
- **Live parts:**
  - the day's schedule from the calendar
  - the top three priorities and tasks due that day, which can be checked off
- **A free ink area** stored like any page, with the same pen tools.
- Swipe or use the arrows to change day, and jump to today.

## 13. Reminders ✅

Built in `lib/features/reminders/`, with 9 tests.
- **Tasks:** a task with a due day can have a "Remind me" time, stored as `remindAt`, in minutes after midnight.
- **Event alerts:**
  - Timed events: at the start, or 5, 15 or 30 minutes, 1 hour or 1 day before.
  - All-day events: 9 AM on the day, or 9 AM the day before.
- **Scheduling:**
  - The app schedules the next 14 days, at most 60 reminders, because iOS keeps only 64.
  - It reschedules half a second after any change, each time it starts, and clears everything on sign-out.
- **Notifications:**
  - Tapping one opens its day in the Planner.
  - Permission is asked the first time a reminder is set.
- **Not yet:**
  - Reminders while the app hasn't been opened for two weeks. A server push would cover that.
  - 24-hour times in notification text.


- `flutter_local_notifications` on iOS and Android, with no server needed.
- Reminders are scheduled from tasks with a due time and events with `reminderMinutes`, and rescheduled whenever those change.
- The web has no reminders.
