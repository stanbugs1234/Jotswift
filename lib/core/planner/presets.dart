import 'pages.dart' show Prompt;
import 'pdf_ops.dart';
import 'recipe.dart';

/// The looks of Jotswift's collections (tool/collections.json), by
/// collection id: what a planner in that collection is drawn in.
final collectionLooks = <String, (String, PlannerStyle)>{
  'botanical': (
    'Botanical',
    _look(
      '#2B2B2B',
      '#7D8577',
      '#CFD8C8',
      '#4F7B5A',
      '#EEF1E8',
      '#FFFFFF',
      '#FBF8F1',
      'hand',
      'swash',
      'leaves',
      false,
    ),
  ),
  'dark_academia': (
    'Dark Academia',
    _look(
      '#2B1D14',
      '#7A6656',
      '#D9CBB4',
      '#6E2233',
      '#EDE2CC',
      '#F7EFE0',
      '#F4EAD7',
      'double',
      'underline',
      'dots',
      true,
    ),
  ),
  'coquette': (
    'Coquette',
    _look(
      '#3D2C36',
      '#9B7F8C',
      '#F0D5DF',
      '#B04A6E',
      '#FCE8EF',
      '#FFFFFF',
      '#FFF8FA',
      'stitched',
      'banner',
      'hearts',
      false,
    ),
  ),
  'boho_sunset': (
    'Boho Sunset',
    _look(
      '#3A2A22',
      '#93776A',
      '#EBD7C6',
      '#A84E2A',
      '#F6E6D7',
      '#FFFFFF',
      '#FCF4EA',
      'hand',
      'swash',
      'sun',
      false,
    ),
  ),
  'scandi': (
    'Scandi Minimal',
    _look(
      '#24282A',
      '#7F8789',
      '#DDE0DE',
      '#4E5A5C',
      '#F0F1EF',
      '#FFFFFF',
      '#FAFAF7',
      'none',
      'underline',
      'none',
      false,
    ),
  ),
  'celestial': (
    'Celestial',
    _look(
      '#EEE7D4',
      '#9AA3C2',
      '#3A4468',
      '#D9B44A',
      '#252E52',
      '#1B2340',
      '#1B2340',
      'double',
      'plain',
      'stars',
      true,
    ),
  ),
  'ocean': (
    'Ocean',
    _look(
      '#1F2D3A',
      '#6E8496',
      '#CFE0EA',
      '#21689A',
      '#E4F0F6',
      '#FFFFFF',
      '#F7FBFC',
      'dashed',
      'swash',
      'waves',
      false,
    ),
  ),
  'autumn': (
    'Autumn',
    _look(
      '#2E2219',
      '#8B7461',
      '#E5D3BF',
      '#9C4221',
      '#F4E6D4',
      '#FFFFFF',
      '#FBF4EA',
      'hand',
      'underline',
      'leaves',
      true,
    ),
  ),
  'retro': (
    'Retro 70s',
    _look(
      '#3A2414',
      '#8E6B52',
      '#EBD5BC',
      '#B4471C',
      '#F7E3C8',
      '#FFFFFF',
      '#FDF3E3',
      'none',
      'banner',
      'sun',
      false,
    ),
  ),
  'kawaii': (
    'Kawaii',
    _look(
      '#3B3045',
      '#9488A3',
      '#EADFF2',
      '#8E5BB5',
      '#F3EAFA',
      '#FFFFFF',
      '#FFFBFE',
      'stitched',
      'banner',
      'stars',
      false,
    ),
  ),
};

/// Plain looks in one accent colour, for planners outside a collection.
final plainLooks = <String, (String, PlannerStyle)>{
  'navy': ('Navy', PlannerStyle.hex(accent: '#2B4A7D', tab: '#E8EEF7')),
  'teal': (
    'Teal',
    PlannerStyle.hex(accent: '#2F6F6A', tab: '#E6F0EE', paper: '#FBFBF8'),
  ),
  'terracotta': (
    'Terracotta',
    PlannerStyle.hex(accent: '#A9553A', tab: '#F5E8E1', paper: '#FFFCF8'),
  ),
  'plum': (
    'Plum',
    PlannerStyle.hex(accent: '#5E5A9C', tab: '#ECEAF6', paper: '#FCFBFE'),
  ),
  'blue': ('Blue', PlannerStyle.hex(accent: '#2C5BA6', tab: '#E5EDF9')),
  'charcoal': (
    'Charcoal',
    PlannerStyle.hex(accent: '#2F343B', tab: '#ECEAE4', paper: '#FFFEFB'),
  ),
  'rose': (
    'Rose',
    PlannerStyle.hex(accent: '#B04A6E', tab: '#FCE8EF', paper: '#FFF8FA'),
  ),
  'forest': (
    'Forest',
    PlannerStyle.hex(accent: '#4F7B5A', tab: '#EEF1E8', paper: '#FBF8F1'),
  ),
};

PlannerStyle _look(
  String ink,
  String soft,
  String rule,
  String accent,
  String tab,
  String onAccent,
  String paper,
  String border,
  String header,
  String motif,
  bool serif,
) => PlannerStyle.hex(
  ink: ink,
  soft: soft,
  rule: rule,
  accent: accent,
  tab: tab,
  onAccent: onAccent,
  paper: paper,
  border: border,
  header: header,
  motif: motif,
  serif: serif,
);

SectionRecipe notesSection([int n = 20, String title = 'Notes']) =>
    SectionRecipe(
      key: 'notes',
      title: title,
      icon: 'pencil',
      blurb: 'Lined pages for anything.',
      runs: [PageRun('lined', 'Note', n)],
    );

SectionRecipe _series(
  String key,
  String title,
  String icon,
  String kind,
  String name,
  int n,
  String blurb,
) => SectionRecipe(
  key: key,
  title: title,
  icon: icon,
  blurb: blurb,
  runs: [PageRun(kind, name, n)],
);

/// A dated or undated planner in the standard layout: the year, each
/// month's calendar, goals, habits and notes, each week and each day, then
/// Notes and Lists. What New notebook's Build your own starts from, and
/// what a catalog planner without its own recipe is customised as.
PlannerRecipe standardRecipe({
  String title = 'My Planner',
  PlannerStyle? style,
  String? collectionId,
  DateTime? start,
  int months = 12,
}) => PlannerRecipe(
  title: title,
  subtitle: start == null ? 'Fill in your own dates' : 'Planner',
  style: style ?? plainLooks['navy']!.$2,
  collectionId: collectionId,
  start: start,
  months: months,
  front: const [KindRef('year_goals'), KindRef('year_pixels')],
  month: const [
    KindRef('month_calendar'),
    KindRef('month_goals'),
    KindRef('month_habits'),
  ],
  week: const [KindRef('week_plan')],
  day: const [KindRef('day_life')],
  sections: [
    notesSection(),
    const SectionRecipe(
      key: 'lists',
      title: 'Lists',
      icon: 'list',
      blurb: 'Checklists for everything else.',
      runs: [
        PageRun('reading_log', 'Books to read'),
        PageRun('checklist', 'Movies & shows'),
        PageRun('checklist', 'Groceries'),
        PageRun('wishlist', 'Wishlist'),
        PageRun('checklist', 'Gift ideas'),
        PageRun('checklist', 'Places to go'),
      ],
    ),
  ],
);

/// An empty undated notebook of sections, to build from nothing.
PlannerRecipe sectionsRecipe({
  String title = 'My Notebook',
  PlannerStyle? style,
}) => PlannerRecipe(
  title: title,
  subtitle: 'Notebook',
  style: style ?? plainLooks['navy']!.$2,
  sections: [notesSection(40)],
);

/// Jotswift's bestseller-style planners (tool/make_life_planners.py), by
/// series key.
final lifePlannerRecipes = <String, PlannerRecipe Function()>{
  'focus': () => PlannerRecipe(
    title: 'Focus Planner',
    subtitle: 'An ADHD-friendly planner: one thing at a time.',
    style: plainLooks['teal']!.$2,
    front: const [
      KindRef('year_goals'),
      KindRef('year_pixels'),
      KindRef('routines'),
      KindRef('rewards_menu'),
    ],
    month: const [
      KindRef('month_calendar'),
      KindRef('month_habits', group: 'habits'),
      KindRef('month_review'),
    ],
    week: const [
      KindRef('week_plan', group: 'weeks'),
      KindRef('week_review'),
    ],
    day: const [
      KindRef('day_focus', group: 'days'),
      KindRef('day_checkin', group: 'checkin'),
    ],
    sections: [
      _series(
        'dumps',
        'Brain dumps',
        'cloud',
        'brain_dump',
        'Brain dump',
        12,
        'Empty your head, then sort it out.',
      ),
      _series(
        'breakdowns',
        'Task breakdowns',
        'list',
        'task_breakdown',
        'Task',
        12,
        'Big, scary tasks broken into tiny steps.',
      ),
      notesSection(),
    ],
  ),
  'wellness': () => PlannerRecipe(
    title: 'Wellness Planner',
    subtitle: 'Check in with yourself, every day.',
    style: plainLooks['plum']!.$2,
    front: const [
      KindRef('year_pixels'),
      KindRef('year_goals', name: 'Intentions'),
    ],
    month: const [
      KindRef('month_calendar'),
      KindRef('month_mental_health'),
      KindRef('month_habits'),
      KindRef(
        'month_review',
        name: 'Reflect',
        prompts: <Prompt>[
          ('Highs', 'star', null),
          ('Lows', 'cloud', null),
          ('What helped', 'leaf', null),
          ('Boundaries', 'check', null),
          ('Joy', 'sun', null),
          ('Next month I need', 'heart', null),
        ],
      ),
    ],
    week: const [
      KindRef('week_plan'),
      KindRef('week_review', name: 'Check-in'),
    ],
    day: const [KindRef('day_journal')],
    sections: [
      _series(
        'therapy',
        'Therapy notes',
        'cloud',
        'therapy_notes',
        'Session',
        24,
        'Before, during and after each session.',
      ),
      _series(
        'anxiety',
        'Anxiety journal',
        'leaf',
        'anxiety_journal',
        'Entry',
        12,
        'Untangle a worry, one question at a time.',
      ),
      const SectionRecipe(
        key: 'toolkit',
        title: 'Toolkit',
        icon: 'heart',
        blurb: 'What helps, when you need it.',
        runs: [
          PageRun('self_care_menu', 'Self-care menu'),
          PageRun('sleep_log', 'Sleep log', 2),
          PageRun('stress_tracker', 'Stress tracker', 2),
        ],
      ),
      _series(
        'gratitude',
        'Gratitude',
        'star',
        'gratitude',
        'Gratitude',
        12,
        'Three good things.',
      ),
      notesSection(),
    ],
  ),
  'life': () => PlannerRecipe(
    title: 'Life Planner',
    subtitle: 'Plan the days, grow the life.',
    style: plainLooks['terracotta']!.$2,
    front: const [
      KindRef('year_goals'),
      KindRef('vision_board'),
      KindRef('year_pixels'),
    ],
    month: const [
      KindRef('month_calendar'),
      KindRef('month_goals'),
      KindRef('vision_board', name: 'Vision'),
      KindRef('month_habits'),
      KindRef('month_budget'),
      KindRef('wins'),
      KindRef('month_review', name: 'Reflect'),
    ],
    week: const [
      KindRef('week_plan'),
      KindRef('meals_movement'),
      KindRef('week_review'),
    ],
    day: const [KindRef('day_life')],
    sections: const [
      SectionRecipe(
        key: 'finance',
        title: 'Finance',
        icon: 'coin',
        blurb: 'Your money, month by month.',
        runs: [
          PageRun('finance_overview', 'Year overview'),
          PageRun('bills_tracker', 'Bills'),
          PageRun('savings_goals', 'Savings goals'),
          PageRun('debt_payoff', 'Debt payoff'),
          PageRun('subscriptions', 'Subscriptions'),
          PageRun('wishlist', 'Wishlist'),
        ],
      ),
      SectionRecipe(
        key: 'health',
        title: 'Health',
        icon: 'leaf',
        blurb: 'Eat, move, rest.',
        runs: [
          PageRun('meal_plan', 'Meal plan'),
          PageRun('sleep_log', 'Sleep log'),
          PageRun('reading_log', 'Reading log'),
        ],
      ),
      SectionRecipe(
        key: 'home',
        title: 'Home',
        icon: 'home',
        blurb: 'Keep the house running.',
        runs: [
          PageRun('cleaning_schedule', 'Cleaning schedule'),
          PageRun('checklist', 'Groceries'),
          PageRun('checklist', 'Projects'),
          PageRun('checklist', 'Gift ideas'),
        ],
      ),
      SectionRecipe(
        key: 'travel',
        title: 'Travel',
        icon: 'plane',
        blurb: 'Plan every getaway.',
        runs: [PageRun('trip_planner', 'Trip', 4)],
      ),
    ],
  ).withNotes(),
  'goals': () => PlannerRecipe(
    title: 'Goals & Projects',
    subtitle: "From a dream to this week's next step.",
    style: PlannerStyle.hex(accent: '#1F3D63', tab: '#E6ECF4'),
    front: const [KindRef('goal_roadmap'), KindRef('year_goals')],
    month: const [
      KindRef('month_calendar'),
      KindRef('milestones'),
      KindRef('month_review'),
    ],
    week: const [KindRef('week_plan'), KindRef('week_review')],
    day: const [KindRef('day_goals')],
    sections: [
      _series(
        'goals',
        'Goals',
        'target',
        'goal_dashboard',
        'Goal',
        12,
        'One dashboard per goal: why, milestones, steps.',
      ),
      _series(
        'projects',
        'Projects',
        'briefcase',
        'project_dashboard',
        'Project',
        12,
        'Outcome, tasks and notes.',
      ),
      const SectionRecipe(
        key: 'quarters',
        title: 'Quarters',
        icon: 'chart',
        blurb: 'Step back every three months.',
        runs: [
          PageRun('quarter_review', 'Q1 review'),
          PageRun('quarter_review', 'Q2 review'),
          PageRun('quarter_review', 'Q3 review'),
          PageRun('quarter_review', 'Q4 review'),
        ],
      ),
      notesSection(),
    ],
  ),
  'student': () => PlannerRecipe(
    title: 'Student Planner',
    subtitle: 'Classes, deadlines and study time.',
    style: plainLooks['blue']!.$2,
    front: const [KindRef('class_schedule'), KindRef('year_goals')],
    month: const [
      KindRef('month_calendar'),
      KindRef('assignment_tracker'),
      KindRef('month_review'),
    ],
    week: const [KindRef('week_plan'), KindRef('week_review')],
    day: const [KindRef('day_student')],
    sections: [
      _series(
        'courses',
        'Courses',
        'book',
        'course_dashboard',
        'Course',
        8,
        'One page per class: assignments, grades, notes.',
      ),
      _series(
        'exams',
        'Exams',
        'cap',
        'exam_planner',
        'Exam plan',
        3,
        'Plan your revision.',
      ),
      const SectionRecipe(
        key: 'study',
        title: 'Study',
        icon: 'target',
        blurb: 'Focus sessions, grades and reading.',
        runs: [
          PageRun('pomodoro', 'Pomodoro log', 2),
          PageRun('gpa_tracker', 'GPA tracker'),
          PageRun('reading_log', 'Reading log'),
        ],
      ),
      notesSection(30, 'Notes'),
    ],
  ),
  'business': () => PlannerRecipe(
    title: 'Business Planner',
    subtitle: 'Strategy, clients and money, in one place.',
    style: plainLooks['charcoal']!.$2,
    front: const [
      KindRef('year_review'),
      KindRef('business_strategy'),
      KindRef('marketing_plan'),
      KindRef('year_goals'),
    ],
    month: const [
      KindRef('month_calendar'),
      KindRef('content_calendar'),
      KindRef('income_expenses'),
      KindRef('month_review'),
    ],
    week: const [KindRef('week_plan'), KindRef('week_review')],
    day: const [KindRef('day_business')],
    sections: [
      _series(
        'clients',
        'Clients',
        'people',
        'client_card',
        'Client',
        20,
        'Contacts, projects and invoices.',
      ),
      _series(
        'projects',
        'Projects',
        'briefcase',
        'project_dashboard',
        'Project',
        12,
        'Outcome, tasks and notes.',
      ),
      const SectionRecipe(
        key: 'finance',
        title: 'Finance',
        icon: 'coin',
        blurb: "The year's numbers.",
        runs: [
          PageRun('finance_overview', 'Year overview'),
          PageRun('subscriptions', 'Subscriptions'),
          PageRun('savings_goals', 'Savings goals'),
        ],
      ),
      notesSection(),
    ],
  ),
};

extension on PlannerRecipe {
  PlannerRecipe withNotes() =>
      copyWith(sections: [...sections, notesSection()]);
}
