import 'domain/notebook_models.dart';

/// Route `extra` for a page opened straight from the shelf: it opens like a
/// book, and Back returns to the shelf.
const openedFromShelf = 'openedFromShelf';

/// The page for [now]: the narrowest page whose dates include it (a week
/// before its month, a month before the year). Null when none does.
NotePage? todaysPage(List<NotePage> pages, DateTime now) {
  NotePage? best;
  for (final p in pages) {
    final period = p.period;
    if (period == null || !period.includes(now)) continue;
    if (best == null || period.length < best.period!.length) best = p;
  }
  return best;
}

/// The dated page nearest to [now], for a planner with no page for today
/// (a 2027 planner opened in 2026 gives its first January page). Null when
/// no page has dates.
NotePage? nearestDatedPage(List<NotePage> pages, DateTime now) {
  NotePage? best;
  (int, int)? bestKey;
  for (final p in pages) {
    final period = p.period;
    if (period == null) continue;
    // Nearest first; then the narrowest, so a week wins over its month.
    final key = (period.distanceTo(now), period.length);
    if (bestKey == null ||
        key.$1 < bestKey.$1 ||
        (key.$1 == bestKey.$1 && key.$2 < bestKey.$2)) {
      best = p;
      bestKey = key;
    }
  }
  return best;
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Which page [notebook] opens to, from its [pages] in notebook order:
///
/// - a planner opened on a new day: today's page;
/// - otherwise the page open last time, if it still exists;
/// - otherwise today's page, the dated page nearest today, or the first.
///
/// Null when the notebook has no pages.
NotePage? pageToOpen(Notebook notebook, List<NotePage> pages, DateTime now) {
  if (pages.isEmpty) return null;
  final today = todaysPage(pages, now);
  final lastAt = notebook.lastPageAt;
  final newDay =
      lastAt == null ||
      !_sameDay(DateTime.fromMillisecondsSinceEpoch(lastAt), now);
  if (today != null && newDay) return today;
  final last = pages.where((p) => p.id == notebook.lastPageId).firstOrNull;
  return last ?? today ?? nearestDatedPage(pages, now) ?? pages.first;
}
