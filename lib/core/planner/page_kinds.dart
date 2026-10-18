import 'book.dart';
import 'pages.dart';

/// What a kind of page needs to know to draw: nothing, its month, or its
/// week (and month). A kind fits where its needs are met: month pages
/// under each month, week pages under each week; any kind under a day.
enum KindNeeds { nothing, month, week }

/// Where a kind of page is usually wanted, to group the picker.
enum KindPlace { front, month, week, day, section }

/// A kind of page the planner builder offers.
class PageKindInfo {
  const PageKindInfo(
    this.id,
    this.name,
    this.icon,
    this.place,
    this.draw, {
    this.needs = KindNeeds.nothing,
    this.plural,
    this.about = '',
    this.prompts,
    this.parts = const [],
    this.drawParts,
  });

  final String id;

  /// Its name on a chip or tab: Habits, Review, Reading log.
  final String name;
  final String icon;
  final KindPlace place;
  final KindNeeds needs;

  /// What a group of them is called in the builder: Habit trackers.
  final String? plural;

  /// A line on what's on it.
  final String about;

  /// The boxes it shows, for kinds that take their own (reviews).
  final List<Prompt>? prompts;

  final PageBody draw;

  /// The parts that can be left off it: (id, name).
  final List<(String, String)> parts;

  /// Draws it without the parts in its set.
  final void Function(Ctx c, Set<String> off)? drawParts;

  String get groupTitle => plural ?? name;

  /// Draws it, with its prompts changed to [prompts] if it takes them,
  /// and without the parts in [off].
  PageBody body([List<Prompt>? prompts, Set<String> off = const {}]) {
    if (prompts != null && this.prompts != null) {
      return (c) => monthReview(c, prompts);
    }
    final drawParts = this.drawParts;
    if (off.isNotEmpty && drawParts != null) return (c) => drawParts(c, off);
    return draw;
  }

  bool fits(KindPlace at) => switch (needs) {
    KindNeeds.nothing => true,
    KindNeeds.month =>
      at == KindPlace.month || at == KindPlace.week || at == KindPlace.day,
    KindNeeds.week => at == KindPlace.week || at == KindPlace.day,
  };
}

const _front = KindPlace.front;
const _month = KindPlace.month;
const _week = KindPlace.week;
const _day = KindPlace.day;
const _section = KindPlace.section;

/// Every kind of page, by id.
final pageKinds = {
  for (final k in <PageKindInfo>[
    // The year
    const PageKindInfo(
      'year_goals',
      'Year goals',
      'target',
      _front,
      yearGoals,
      about: 'Six areas of life, with goals for each.',
    ),
    const PageKindInfo(
      'year_pixels',
      'Year in pixels',
      'heart',
      _front,
      yearPixels,
      about: 'A square a day to colour by mood.',
    ),
    const PageKindInfo(
      'vision_board',
      'Vision board',
      'star',
      _front,
      visionBoard,
      plural: 'Vision boards',
      about: 'Frames for photos and stickers.',
    ),
    const PageKindInfo(
      'goal_roadmap',
      'Goal roadmap',
      'target',
      _front,
      goalRoadmap,
      about: 'From a dream to this week\'s step.',
    ),
    const PageKindInfo(
      'routines',
      'Routines',
      'sun',
      _front,
      routines,
      about: 'Morning and evening routines.',
    ),
    const PageKindInfo(
      'rewards_menu',
      'Rewards menu',
      'gift',
      _front,
      rewardsMenu,
      about: 'Treats for small, medium and big wins.',
    ),
    const PageKindInfo(
      'class_schedule',
      'Class schedule',
      'cap',
      _front,
      classSchedule,
      about: 'Monday to Friday, 8am to 6pm.',
    ),
    const PageKindInfo(
      'year_review',
      'Year review',
      'star',
      _front,
      yearReview,
      prompts: [],
      about: 'Proudest moments, lessons, next year.',
    ),
    const PageKindInfo(
      'business_strategy',
      'Strategy',
      'target',
      _front,
      businessStrategy,
      prompts: [],
      about: 'Mission, clients, offers and big moves.',
    ),
    const PageKindInfo(
      'marketing_plan',
      'Marketing plan',
      'chart',
      _front,
      marketingPlan,
      about: 'Channels, content and campaigns.',
    ),
    // Months
    PageKindInfo(
      'month_calendar',
      'Calendar',
      'calendar',
      _month,
      monthCalendar,
      needs: KindNeeds.month,
      plural: 'Month calendars',
      about: 'The month, with Focus and Notes boxes.',
      parts: [('focus', 'Focus box'), ('notes', 'Notes box')],
      drawParts: (c, off) => monthCalendar(c, off: off),
    ),
    PageKindInfo(
      'month_calendar_full',
      'Calendar',
      'calendar',
      _month,
      (c) => monthCalendar(c, side: false),
      needs: KindNeeds.month,
      plural: 'Month calendars',
      about: 'The month on the whole page.',
    ),
    const PageKindInfo(
      'month_goals',
      'Goals',
      'target',
      _month,
      monthGoals,
      plural: 'Monthly goals',
      about: 'Goals, steps, dates to remember.',
    ),
    const PageKindInfo(
      'month_habits',
      'Habits',
      'check',
      _month,
      monthHabits,
      needs: KindNeeds.month,
      plural: 'Habit trackers',
      about: 'A row per habit, a box per day.',
    ),
    const PageKindInfo(
      'month_mental_health',
      'Mind',
      'heart',
      _month,
      monthMentalHealth,
      needs: KindNeeds.month,
      plural: 'Monthly mental health',
      about: 'Mood, anxiety, sleep and energy by day.',
    ),
    const PageKindInfo(
      'month_budget',
      'Budget',
      'coin',
      _month,
      monthBudget,
      plural: 'Monthly budgets',
      about: 'Income, bills and spending.',
    ),
    const PageKindInfo(
      'income_expenses',
      'Money',
      'coin',
      _month,
      incomeExpenses,
      plural: 'Monthly income & expenses',
      about: 'Income and expenses, side by side.',
    ),
    const PageKindInfo(
      'content_calendar',
      'Content',
      'chart',
      _month,
      contentCalendar,
      plural: 'Content calendars',
      about: 'Posts: channel, idea and status.',
    ),
    const PageKindInfo(
      'milestones',
      'Milestones',
      'target',
      _month,
      milestones,
      plural: 'Monthly milestones',
      about: 'Milestones, progress and next steps.',
    ),
    const PageKindInfo(
      'assignment_tracker',
      'Assignments',
      'check',
      _month,
      assignmentTracker,
      plural: 'Assignment trackers',
      about: 'Course, assignment, due date, grade.',
    ),
    const PageKindInfo(
      'wins',
      'Wins',
      'star',
      _month,
      wins,
      plural: 'Monthly wins',
      about: 'Boxes to celebrate what went well.',
    ),
    PageKindInfo(
      'month_review',
      'Review',
      'star',
      _month,
      monthReview,
      plural: 'Monthly reviews',
      prompts: monthReviewPrompts,
      about: 'Wins, what worked, next month.',
    ),
    // Weeks
    const PageKindInfo(
      'week_plan',
      'Week',
      'calendar',
      _week,
      weekPlan,
      needs: KindNeeds.week,
      plural: 'Week pages',
      about: 'Each day linked, Top 3 and a focus.',
      parts: [
        ('priorities', 'Top 3 priorities'),
        ('focus', 'One focus'),
        ('calendar', 'Month calendar'),
      ],
      drawParts: weekPlan,
    ),
    const PageKindInfo(
      'meals_movement',
      'Meals',
      'leaf',
      _week,
      mealsMovement,
      needs: KindNeeds.week,
      plural: 'Weekly meals & movement',
      about: 'Meals, movement and water for each day.',
    ),
    PageKindInfo(
      'week_review',
      'Review',
      'star',
      _week,
      weekReview,
      plural: 'Weekly reviews',
      prompts: weekReviewPrompts,
      about: 'Wins, what drained me, next week.',
    ),
    // Days
    const PageKindInfo(
      'day_focus',
      'Plan',
      'target',
      _day,
      dayFocus,
      plural: 'Day plans',
      about: 'Time blocks, the one thing, Top 3, to-do.',
      parts: [
        ('schedule', 'Time blocks'),
        ('one_thing', 'The one thing'),
        ('top3', 'Top 3'),
        ('todo', 'To-do'),
        ('reward', 'Reward'),
      ],
      drawParts: dayFocus,
    ),
    const PageKindInfo(
      'day_life',
      'Day',
      'sun',
      _day,
      dayLife,
      plural: 'Day pages',
      about: 'Schedule, Top 3, to-do, gratitude.',
      parts: [
        ('schedule', 'Schedule'),
        ('top3', 'Top 3'),
        ('todo', 'To-do'),
        ('grateful', 'Grateful for'),
        ('affirmation', 'Affirmation'),
      ],
      drawParts: dayLife,
    ),
    const PageKindInfo(
      'day_goals',
      'Day',
      'target',
      _day,
      dayGoals,
      plural: 'Day pages',
      about: 'Schedule and priorities for your goals.',
      parts: [
        ('schedule', 'Schedule'),
        ('top3', 'Top 3 for my goals'),
        ('tasks', 'Other tasks'),
        ('notes', 'Notes & wins'),
      ],
      drawParts: dayGoals,
    ),
    const PageKindInfo(
      'day_student',
      'Day',
      'cap',
      _day,
      dayStudent,
      plural: 'Day pages',
      about: 'Classes, due today, study blocks.',
    ),
    const PageKindInfo(
      'day_business',
      'Day',
      'briefcase',
      _day,
      dayBusiness,
      plural: 'Day pages',
      about: 'Priorities, calls and admin, habits.',
      parts: [
        ('schedule', 'Time blocks'),
        ('priorities', '3 priorities'),
        ('admin', 'Calls, emails & admin'),
        ('habits', 'Health & habits'),
        ('grateful', 'Grateful for'),
      ],
      drawParts: dayBusiness,
    ),
    const PageKindInfo(
      'day_journal',
      'Journal',
      'pencil',
      _day,
      dayJournal,
      plural: 'Daily journal pages',
      about: 'How I feel, good things, a journal.',
    ),
    const PageKindInfo(
      'day_checkin',
      'Check-in',
      'bolt',
      _day,
      dayCheckin,
      plural: 'Daily check-ins',
      about: 'Energy, mood, water, a brain dump.',
    ),
    // Sections
    const PageKindInfo(
      'lined',
      'Lined',
      'pencil',
      _section,
      linedPage,
      plural: 'Lined pages',
    ),
    const PageKindInfo(
      'dotted',
      'Dotted',
      'pencil',
      _section,
      dottedPage,
      plural: 'Dotted pages',
    ),
    const PageKindInfo(
      'grid',
      'Grid',
      'pencil',
      _section,
      gridPage,
      plural: 'Grid pages',
    ),
    const PageKindInfo(
      'checklist',
      'Checklist',
      'check',
      _section,
      checklistPage,
      plural: 'Checklists',
    ),
    const PageKindInfo(
      'blank',
      'Blank',
      'pencil',
      _section,
      blankPage,
      plural: 'Blank pages',
    ),
    const PageKindInfo(
      'brain_dump',
      'Brain dump',
      'cloud',
      _section,
      brainDump,
      plural: 'Brain dumps',
      about: 'Everything on your mind.',
    ),
    const PageKindInfo(
      'task_breakdown',
      'Task breakdown',
      'list',
      _section,
      taskBreakdown,
      plural: 'Task breakdowns',
      about: 'A big task in tiny steps.',
    ),
    const PageKindInfo(
      'goal_dashboard',
      'Goal',
      'target',
      _section,
      goalDashboard,
      plural: 'Goal dashboards',
      about: 'Why, milestones by month, steps.',
    ),
    const PageKindInfo(
      'project_dashboard',
      'Project',
      'briefcase',
      _section,
      projectDashboard,
      plural: 'Project dashboards',
      about: 'Outcome, tasks and notes.',
    ),
    PageKindInfo(
      'quarter_review',
      'Quarter review',
      'chart',
      _section,
      quarterReview,
      plural: 'Quarterly reviews',
      prompts: const [],
      about: 'Step back every three months.',
    ),
    const PageKindInfo(
      'therapy_notes',
      'Therapy session',
      'cloud',
      _section,
      therapyNotes,
      plural: 'Therapy notes',
      about: 'Before, during and after a session.',
    ),
    const PageKindInfo(
      'anxiety_journal',
      'Anxiety journal',
      'leaf',
      _section,
      anxietyJournal,
      plural: 'Anxiety journal',
      about: 'Untangle a worry.',
    ),
    const PageKindInfo(
      'gratitude',
      'Gratitude',
      'heart',
      _section,
      gratitude,
      plural: 'Gratitude pages',
      about: 'Three good things, six days a page.',
    ),
    const PageKindInfo(
      'self_care_menu',
      'Self-care menu',
      'heart',
      _section,
      selfCareMenu,
      about: 'What helps, when you need it.',
    ),
    const PageKindInfo(
      'sleep_log',
      'Sleep log',
      'moon',
      _section,
      sleepLog,
      plural: 'Sleep logs',
    ),
    const PageKindInfo(
      'stress_tracker',
      'Stress tracker',
      'bolt',
      _section,
      stressTracker,
      plural: 'Stress trackers',
    ),
    const PageKindInfo(
      'course_dashboard',
      'Course',
      'book',
      _section,
      courseDashboard,
      plural: 'Course pages',
      about: 'Assignments, grades and notes.',
    ),
    const PageKindInfo(
      'exam_planner',
      'Exam plan',
      'cap',
      _section,
      examPlanner,
      plural: 'Exam plans',
    ),
    const PageKindInfo(
      'pomodoro',
      'Pomodoro log',
      'target',
      _section,
      pomodoro,
      plural: 'Pomodoro logs',
    ),
    const PageKindInfo(
      'gpa_tracker',
      'GPA tracker',
      'chart',
      _section,
      gpaTracker,
    ),
    const PageKindInfo(
      'reading_log',
      'Reading log',
      'book',
      _section,
      readingLog,
      plural: 'Reading logs',
    ),
    const PageKindInfo(
      'client_card',
      'Client',
      'people',
      _section,
      clientCard,
      plural: 'Client pages',
      about: 'Contact, project and invoices.',
    ),
    const PageKindInfo(
      'finance_overview',
      'Year overview',
      'coin',
      _section,
      financeOverview,
      about: 'Income, spending and saving by month.',
    ),
    const PageKindInfo(
      'bills_tracker',
      'Bills',
      'calendar',
      _section,
      billsTracker,
      about: 'Each bill, ticked off each month.',
    ),
    const PageKindInfo(
      'savings_goals',
      'Savings goals',
      'coin',
      _section,
      savingsGoals,
    ),
    const PageKindInfo(
      'debt_payoff',
      'Debt payoff',
      'chart',
      _section,
      debtPayoff,
    ),
    const PageKindInfo(
      'subscriptions',
      'Subscriptions',
      'list',
      _section,
      subscriptions,
    ),
    const PageKindInfo('wishlist', 'Wishlist', 'gift', _section, wishlist),
    const PageKindInfo(
      'cleaning_schedule',
      'Cleaning schedule',
      'home',
      _section,
      cleaningSchedule,
    ),
    const PageKindInfo(
      'meal_plan',
      'Meal plan',
      'leaf',
      _section,
      mealPlan,
      plural: 'Meal plans',
    ),
    const PageKindInfo(
      'trip_planner',
      'Trip',
      'plane',
      _section,
      tripPlanner,
      plural: 'Trip plans',
      about: 'Packing, itinerary, bookings, budget.',
    ),
  ])
    k.id: k,
};

PageKindInfo kindOf(String id) => pageKinds[id] ?? pageKinds['lined']!;
