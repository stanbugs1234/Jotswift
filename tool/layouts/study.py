"""Study pages: lectures, Cornell variants, vocabulary, labs, reading, exams,
semesters, grades, study sessions and flashcards."""

from layouts.kit import *  # noqa: F401,F403


def lecture_notes():
    p = page("Lecture", False)
    field(p, LEFT, TOP - 24, "Course", LEFT + 250)
    field(p, LEFT + 266, TOP - 24, "Date", RIGHT)
    field(p, LEFT, TOP - 50, "Topic", RIGHT)
    label(p, LEFT, TOP - 84, "Key points")
    lines(p, LEFT, RIGHT, TOP - 108, 17, gap=26)
    box(p, LEFT, BOTTOM, (RIGHT - LEFT) / 2 - 8, 130, "Questions")
    box(p, LEFT + (RIGHT - LEFT) / 2 + 8, BOTTOM, (RIGHT - LEFT) / 2 - 8, 130, "To review")
    return p, "Lecture notes"


def _cornell(title, cue_title, body):
    p = page(title, "Topic  ____________________   Date  __________")
    cue = LEFT + 150
    bottom = 150
    p.line(cue, TOP - 40, cue, bottom, rgb=s().accent, width=1)
    p.line(LEFT, bottom, RIGHT, bottom, rgb=s().accent, width=1)
    label(p, LEFT, TOP - 56, cue_title, 10)
    body(p, cue, bottom)
    label(p, LEFT, bottom - 20, "Summary", 10)
    lines(p, LEFT, RIGHT, bottom - 44, 3)
    return p


def cornell_grid():
    p = _cornell("Notes", "Cues", lambda p, cue, bottom: dots(p, cue + 14, bottom + 12, RIGHT - 4, TOP - 52, 18))
    return p, "Cornell notes (dot grid)"


def cornell_questions():
    def body(p, cue, bottom):
        y = TOP - 84
        while y > bottom + 40:
            p.text(LEFT, y, "Q", 10, rgb=s().accent, bold=True)
            p.line(LEFT + 12, y - 3, cue - 10, y - 3)
            lines(p, cue + 10, RIGHT, y - 3, 3, gap=24)
            y -= 96
            p.line(LEFT, y + 22, RIGHT, y + 22, rgb=tint(s().rule, 0.4), width=0.5)
    return _cornell("Q & A notes", "Questions", body), "Cornell notes (questions)"


def vocabulary():
    p = page("Vocabulary", "Subject  ________________")
    table(p, TOP - 40, [("Word", 0), ("Meaning", 0.28), ("In a sentence", 0.62)], 20, row_h=31)
    return p, "Vocabulary"


def lab_report():
    p = page("Lab report", False)
    field(p, LEFT, TOP - 24, "Experiment", LEFT + 300)
    field(p, LEFT + 316, TOP - 24, "Date", RIGHT)
    y = TOP - 60
    for name, n in (("Question", 2), ("Hypothesis", 2), ("Materials", 3), ("Method", 4)):
        label(p, LEFT, y, name)
        lines(p, LEFT, RIGHT, y - 22, n, gap=22)
        y -= 34 + n * 22
    label(p, LEFT, y, "Results")
    bottom = table(p, y - 10, [("Trial", 0), ("Measure", 0.15), ("Measure", 0.4), ("Notes", 0.65)], 6, row_h=22)
    label(p, LEFT, bottom - 22, "Conclusion")
    lines(p, LEFT, RIGHT, bottom - 46, int((bottom - 46 - BOTTOM) / 22) + 1, gap=22)
    return p, "Lab report"


def reading_notes():
    p = page("Reading notes", False)
    field(p, LEFT, TOP - 24, "Title", RIGHT)
    field(p, LEFT, TOP - 50, "Author", LEFT + 300)
    field(p, LEFT + 316, TOP - 50, "Pages", RIGHT)
    label(p, LEFT, TOP - 86, "Main ideas")
    numbered(p, LEFT, RIGHT, TOP - 110, 6)
    label(p, LEFT, TOP - 280, "Quotes")
    for i in range(3):
        y = TOP - 304 - i * 70
        p.rect(LEFT, y - 54, RIGHT - LEFT, 54, fill=tint(s().accent, 0.92))
        p.text(LEFT + 8, y - 16, '"', 20, rgb=s().accent, bold=True)
    label(p, LEFT, 150, "What I think")
    lines(p, LEFT, RIGHT, 126, 4)
    return p, "Reading notes"


def exam_planner():
    p = page("Exams", "Term  ________________")
    bottom = table(p, TOP - 40, [("Subject", 0), ("Date", 0.32), ("Time", 0.48), ("Room", 0.62), ("Topics", 0.76)], 8, row_h=28)
    label(p, LEFT, bottom - 26, "Study plan")
    xs, w = columns(p, LEFT, RIGHT, 2)
    top = bottom - 40
    for i, x in enumerate(xs):
        p.rect(x, BOTTOM, w, top - BOTTOM, stroke=s().rule)
        label(p, x + 10, top - 18, ("Weeks before", "Days before")[i], 10)
        checkbox_rows(p, x + 10, x + w - 10, top - 44, int((top - BOTTOM - 50) / 26))
    return p, "Exam planner"


def semester_overview():
    p = page("Semester", "Term  ________________")
    xs, w = columns(p, LEFT, RIGHT, 2, gap=16)
    bh = (TOP - 44 - BOTTOM - 2 * 14) / 3
    for i in range(6):
        x = xs[i % 2]
        y = TOP - 44 - (i // 2 + 1) * bh - (i // 2) * 14
        box(p, x, y, w, bh)
        field(p, x + 10, y + bh - 20, "Course", x + w - 10)
        for k, name in enumerate(("Teacher", "Room", "Times", "Email")):
            field(p, x + 10, y + bh - 46 - k * 24, name, x + w - 10, size=9)
        p.text(x + 10, y + 14, "Goal grade", 9, rgb=s().soft, bold=True)
        p.rect(x + 74, y + 8, 40, 18, stroke=s().rule)
    return p, "Semester overview"


def gpa_tracker():
    p = page("Grades", "Term  ________________")
    bottom = table(p, TOP - 40, [("Course", 0), ("Credits", 0.46), ("Grade", 0.62), ("Points", 0.78)], 12, row_h=28)
    xs, w = columns(p, LEFT, RIGHT, 3)
    for x, name in zip(xs, ("Total credits", "Total points", "GPA")):
        box(p, x, bottom - 90, w, 66, name)
    label(p, LEFT, bottom - 120, "Assignments and tests")
    table(p, bottom - 130, [("What", 0), ("Course", 0.4), ("Score", 0.65), ("Weight", 0.82)],
          int((bottom - 152 - BOTTOM) / 24), row_h=24)
    return p, "GPA tracker"


def study_log():
    p = page("Study log", "Week of  ________________")
    bottom = table(p, TOP - 40, [("Date", 0), ("Subject", 0.14), ("What I studied", 0.38), ("Time", 0.78), ("Focus", 0.88)],
                   16, row_h=28)
    label(p, LEFT, bottom - 24, "Hours this week")
    bar(p, LEFT, bottom - 56, RIGHT - LEFT, 18, 20)
    return p, "Study session log"


def flashcards():
    p = page("Flashcards", "Subject  ________________   Cut or fold on the dashed lines")
    xs, w = columns(p, LEFT, RIGHT, 2, gap=0)
    h = (TOP - 40 - BOTTOM) / 4
    for r in range(4):
        y = TOP - 40 - (r + 1) * h
        for c, x in enumerate(xs):
            p.color(s().soft, stroke=True)
            p.ops.append(f"[4 3] 0 d 0.8 w {x:.1f} {y:.1f} {w:.1f} {h:.1f} re S [] 0 d")
            p.text(x + 10, y + h - 16, "Front" if c == 0 else "Back", 8, rgb=s().soft, bold=True)
    return p, "Flashcards (8)"


LAYOUTS = [lecture_notes, cornell_grid, cornell_questions, vocabulary, lab_report, reading_notes,
           exam_planner, semester_overview, gpa_tracker, study_log, flashcards]
