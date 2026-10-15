"""Money pages: expenses, savings goals, debt payoff, subscriptions and net
worth."""

from layouts.kit import *  # noqa: F401,F403


def expenses():
    p = page("Expenses", "Month  ________________")
    table(p, TOP - 40, [("Date", 0), ("What", 0.13), ("Category", 0.5), ("Paid with", 0.7), ("Amount", 0.86)], 22, row_h=27)
    xs, w = columns(p, LEFT, RIGHT, 3)
    for x, name in zip(xs, ("This page", "Month so far", "Budget left")):
        box(p, x, BOTTOM, w, 52, name)
    return p, "Expense tracker"


def savings_goals():
    p = page("Savings goals")
    bh = (TOP - 40 - BOTTOM - 2 * 14) / 3
    for i in range(3):
        y = TOP - 40 - (i + 1) * bh - i * 14
        box(p, LEFT, y, RIGHT - LEFT, bh, f"Goal {i + 1}")
        field(p, LEFT + 12, y + bh - 44, "For", LEFT + 260, size=9)
        field(p, LEFT + 276, y + bh - 44, "Target", LEFT + 400, size=9)
        field(p, LEFT + 416, y + bh - 44, "By", RIGHT - 12, size=9)
        # A row of 20 coins to fill in, each 5% of the goal.
        for k in range(20):
            cx = LEFT + 26 + k * ((RIGHT - LEFT - 40) / 20)
            circle(p, cx, y + bh - 86, 9, s().rule, fill=False, width=0.9)
        p.text(LEFT + 12, y + bh - 112, "Each coin is 5%", 8, rgb=s().soft)
        p.text(LEFT + 12, y + 22, "Saved so far", 9, rgb=s().soft, bold=True)
        bar(p, LEFT + 90, y + 16, RIGHT - LEFT - 102, 14, 20)
    return p, "Savings goals"


def debt_payoff():
    p = page("Debt payoff")
    bottom = table(p, TOP - 40, [("Debt", 0), ("Balance", 0.3), ("Rate", 0.48), ("Minimum", 0.6), ("Order", 0.76),
                                 ("Paid off", 0.88)], 6, row_h=28)
    label(p, LEFT, bottom - 26, "Payments")
    table(p, bottom - 36, [("Date", 0), ("Debt", 0.16), ("Paid", 0.5), ("New balance", 0.7)],
          int((bottom - 58 - BOTTOM) / 25), row_h=25)
    return p, "Debt payoff"


def subscriptions():
    p = page("Subscriptions")
    bottom = table(p, TOP - 40, [("Service", 0), ("Cost", 0.32), ("Every", 0.46), ("Renews", 0.6), ("Keep?", 0.78)],
                   18, row_h=28)
    xs, w = columns(p, LEFT, RIGHT, 2)
    for x, name in zip(xs, ("Per month", "Per year")):
        box(p, x, bottom - 76, w, 56, name)
    return p, "Subscription tracker"


def net_worth():
    p = page("Net worth", "As of  ________________")
    xs, w = columns(p, LEFT, RIGHT, 2, gap=16)
    top = TOP - 44
    for x, name, rows in ((xs[0], "Assets", ("Cash", "Savings", "Investments", "Retirement", "Home", "Car", "Other")),
                          (xs[1], "Debts", ("Mortgage", "Car loan", "Student loans", "Credit cards", "Other", "", ""))):
        table(p, top, [(name, 0), ("Amount", 0.62)], len(rows) + 3, row_h=30, x0=x, x1=x + w)
        for k, row in enumerate(rows):
            p.text(x + 6, top - 22 - (k + 1) * 30 + 10, row, 9.5)
        p.rect(x, top - 22 - (len(rows) + 3) * 30 - 40, w, 34, fill=tint(s().accent, 0.9))
        label(p, x + 8, top - 22 - (len(rows) + 3) * 30 - 28, f"Total {name.lower()}", 10)
    y = top - 22 - 10 * 30 - 70
    p.rect(LEFT, y - 56, RIGHT - LEFT, 56, stroke=s().accent, width=1.4)
    label(p, LEFT + 12, y - 24, "Net worth = assets - debts", 12)
    label(p, LEFT, y - 90, "Next time I'd like it to be")
    lines(p, LEFT, RIGHT, y - 114, 2)
    return p, "Net worth"


LAYOUTS = [expenses, savings_goals, debt_payoff, subscriptions, net_worth]
