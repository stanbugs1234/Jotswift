"""Budget spreads: the monthly budget, expenses, bills, savings jars, debt
payoff, sinking funds, subscriptions and the year in money."""

from spreads.kit import *  # noqa: F401,F403
from spreads.plan import _fill_in


def ledger(p, x0, x1, y_top, height, title, cols, row_h=15, check=False):
    """A titled table filling [height]: [cols] is (name, start fraction)."""
    top = panel(p, x0, y_top, x1 - x0, height, title)
    rows = max(1, int((top - (y_top - height) - 20) / row_h))
    table(p, top - 2, cols, rows, row_h=row_h, x0=x0 + 4, x1=x1 - 4, check=check)


def budget(sp, n=1):
    """The month's money: income and bills on the left; expenses, savings,
    debts and a summary on the right."""
    p = sp.page
    _fill_in(p, sp.left[0] + 160, TOP + 10, "Month")
    x0, x1 = sp.left
    ledger(p, x0, x1, TOP - 4, 150, "Income", [("Source", 0), ("Expected", 0.55), ("Actual", 0.78)])
    ledger(p, x0, x1, TOP - 160, TOP - 160 - BOTTOM, "Bills",
           [("Paid", 0), ("Bill", 0.08), ("Due", 0.5), ("Expected", 0.64), ("Actual", 0.82)], check=True)
    rx0, rx1 = sp.right
    (ax0, ax1), (bx0, bx1) = split(rx0, rx1, 1, 1, gap=8)
    ledger(p, ax0, ax1, TOP - 4, 300, "Expenses", [("Category", 0), ("Budget", 0.5), ("Actual", 0.75)])
    ledger(p, bx0, bx1, TOP - 4, 145, "Savings", [("Goal", 0), ("Amount", 0.62)])
    ledger(p, bx0, bx1, TOP - 155, 145, "Debts", [("Debt", 0), ("Payment", 0.62)])
    top = panel(p, rx0, TOP - 310, rx1 - rx0, TOP - 310 - BOTTOM, "Summary")
    table(p, top - 2, [("", 0), ("Expected", 0.45), ("Actual", 0.72)], 7, row_h=16, x0=rx0 + 4, x1=rx1 - 4)
    for i, name in enumerate(("Income", "Bills", "Expenses", "Savings", "Debts", "Total out", "Left over")):
        p.text(rx0 + 10, top - 2 - 22 - (i + 1) * 16 + 5, name, 7.5, rgb=S().ink, bold=i == 6)


def expenses(sp, n=1):
    """Every purchase of the month, across both pages."""
    p = sp.page
    _fill_in(p, sp.left[0] + 160, TOP + 10, "Month")
    cols = [("Date", 0), ("Description", 0.14), ("Category", 0.55), ("Paid by", 0.74), ("Amount", 0.86)]
    for x0, x1 in (sp.left, sp.right):
        ledger(p, x0, x1, TOP - 4, TOP - 4 - BOTTOM, "Expenses", cols, row_h=16)


def bills(sp):
    """Bills by day of the month, and a year of paid boxes."""
    p = sp.page
    x0, x1 = sp.left
    top = panel(p, x0, TOP - 4, x1 - x0, TOP - 4 - BOTTOM, "Bill calendar")
    rh = (top - BOTTOM - 6) / 31
    for d in range(31):
        y = top - (d + 1) * rh
        p.text(x0 + 6, y + rh / 2 - 2, str(d + 1), 6.5, rgb=S().accent, bold=True)
        p.line(x0 + 22, y, x1 - 6, y, rgb=S().rule, width=0.4)
        p.line(x0 + (x1 - x0) * 0.7, y, x0 + (x1 - x0) * 0.7, y + rh, rgb=S().rule, width=0.4)
    rx0, rx1 = sp.right
    top = panel(p, rx0, TOP - 4, rx1 - rx0, TOP - 4 - BOTTOM, "Paid this year")
    name_w = (rx1 - rx0) * 0.3
    cw = (rx1 - rx0 - name_w - 8) / 12
    for m in range(12):
        p.text(rx0 + name_w + m * cw + cw / 2, top - 10, "JFMAMJJASOND"[m], 6.5, rgb=S().soft, bold=True, center=True)
    rows = 18
    rh = (top - 16 - BOTTOM - 4) / rows
    for r in range(rows):
        y = top - 16 - (r + 1) * rh
        p.line(rx0 + 6, y + 2, rx0 + name_w - 4, y + 2, rgb=S().rule, width=0.5)
        for m in range(12):
            s = min(cw, rh) - 4
            p.rect(rx0 + name_w + m * cw + (cw - s) / 2, y + (rh - s) / 2, s, s, stroke=S().rule, width=0.5)


def _jar(p, x, y, w, h):
    """A jar outline with ten bands to colour in."""
    p.rect(x + w * 0.2, y + h - 10, w * 0.6, 10, fill=S().tab, stroke=S().soft, width=0.7)
    p.rect(x, y, w, h - 14, stroke=S().soft, width=0.9)
    for i in range(1, 10):
        yy = y + i * (h - 14) / 10
        p.line(x + 3, yy, x + w - 3, yy, rgb=S().rule, width=0.4)
        p.text(x + w + 3, yy - 2, f"{i * 10}%", 5, rgb=S().soft)


def savings(sp):
    """Three savings jars to fill, and a savings log."""
    p = sp.page
    x0, x1 = sp.left
    cols = split(x0, x1, 1, 1, 1, gap=10)
    for c0, c1 in cols:
        top = panel(p, c0, TOP - 4, c1 - c0, TOP - 4 - BOTTOM, "Saving for")
        p.line(c0 + 6, top - 18, c1 - 6, top - 18, rgb=S().rule, width=0.6)
        caps(p, c0 + 6, top - 34, "Goal  ______", 6, rgb=S().soft)
        caps(p, c0 + 6, top - 48, "By  ______", 6, rgb=S().soft)
        _jar(p, c0 + 14, BOTTOM + 14, c1 - c0 - 44, top - 70 - BOTTOM - 14)
    rx0, rx1 = sp.right
    ledger(p, rx0, rx1, TOP - 4, TOP - 4 - BOTTOM, "Savings log",
           [("Date", 0), ("Goal", 0.16), ("Added", 0.56), ("Total", 0.78)], row_h=16)


def debt(sp):
    """Debts in payoff order, with progress bars and a payment log."""
    p = sp.page
    x0, x1 = sp.left
    ledger(p, x0, x1, TOP - 4, 180, "My debts",
           [("Order", 0), ("Debt", 0.12), ("Balance", 0.48), ("Rate", 0.66), ("Minimum", 0.8)])
    top = panel(p, x0, TOP - 190, x1 - x0, TOP - 190 - BOTTOM, "Progress")
    for i in range(6):
        y = top - 22 - i * 52
        p.line(x0 + 6, y, x0 + 120, y, rgb=S().rule, width=0.5)
        bar(p, x0 + 6, y - 24, x1 - x0 - 12, 12, 20)
    rx0, rx1 = sp.right
    ledger(p, rx0, rx1, TOP - 4, TOP - 4 - BOTTOM, "Payments",
           [("Date", 0), ("Debt", 0.16), ("Paid", 0.56), ("Left", 0.78)], row_h=16)


def funds(sp):
    """Sinking funds: six goals with a box per month."""
    p = sp.page
    for x0, x1 in (sp.left, sp.right):
        rh = (TOP - 4 - BOTTOM) / 3
        for r in range(3):
            top = panel(p, x0, TOP - 4 - r * rh, x1 - x0, rh - 8, "Sinking fund")
            caps(p, x0 + 6, top - 14, "For  ________________   Goal  ________   By  ________", 6.5, rgb=S().soft)
            cw = (x1 - x0 - 12) / 12
            for m in range(12):
                x = x0 + 6 + m * cw
                p.rect(x + 1, top - 64, cw - 2, 38, stroke=S().rule, width=0.5)
                p.text(x + cw / 2, top - 22 - 0, "JFMAMJJASOND"[m], 6, rgb=S().soft, bold=True, center=True)
            caps(p, x0 + 6, top - 80, "Saved so far", 6, rgb=S().soft)
            bar(p, x0 + 70, top - 86, x1 - x0 - 76, 10, 20)


def subscriptions(sp):
    """Subscriptions and what they cost a month and a year."""
    p = sp.page
    x0, x1 = sp.left
    ledger(p, x0, x1, TOP - 4, TOP - 4 - BOTTOM, "Subscriptions",
           [("Service", 0), ("Cost", 0.4), ("Every", 0.56), ("Renews", 0.72), ("Keep", 0.88)], row_h=16)
    rx0, rx1 = sp.right
    ledger(p, rx0, rx1, TOP - 4, 260, "Cancelled", [("Service", 0), ("Saved a year", 0.6)])
    (ax0, ax1), (bx0, bx1) = split(rx0, rx1, 1, 1, gap=8)
    for (c0, c1), name in (((ax0, ax1), "Per month"), ((bx0, bx1), "Per year")):
        panel(p, c0, TOP - 274, c1 - c0, 80, name)
    top = panel(p, rx0, TOP - 364, rx1 - rx0, TOP - 364 - BOTTOM, "Notes")
    ruled(p, rx0 + 5, rx1 - 5, top, BOTTOM + 2, 15)


def year_money(sp):
    """The year in money: a row per month and a chart to colour."""
    p = sp.page
    _fill_in(p, sp.left[0] + 180, TOP + 10, "Year")
    x0, x1 = sp.left
    top = panel(p, x0, TOP - 4, x1 - x0, TOP - 4 - BOTTOM, "Month by month")
    row_h = (top - 30 - BOTTOM) / 13
    table(p, top - 2, [("Month", 0), ("Income", 0.22), ("Spent", 0.42), ("Saved", 0.62), ("Net", 0.82)], 13,
          row_h=row_h, x0=x0 + 4, x1=x1 - 4)
    names = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
             "October", "November", "December", "Total"]
    for i, name in enumerate(names):
        p.text(x0 + 10, top - 2 - 22 - (i + 1) * row_h + row_h / 2 - 3, name, 7.5, rgb=S().ink, bold=i == 12)
    rx0, rx1 = sp.right
    top = panel(p, rx0, TOP - 4, rx1 - rx0, 300, "Saved each month")
    base, left = top - 270, rx0 + 30
    p.line(left, base, rx1 - 10, base, rgb=S().soft, width=0.8)
    p.line(left, base, left, top - 14, rgb=S().soft, width=0.8)
    cw = (rx1 - 10 - left) / 12
    for m in range(12):
        p.rect(left + m * cw + cw * 0.2, base, cw * 0.6, top - 24 - base, stroke=S().rule, width=0.4)
        p.text(left + m * cw + cw / 2, base - 10, "JFMAMJJASOND"[m], 6, rgb=S().soft, bold=True, center=True)
    top = panel(p, rx0, TOP - 310, rx1 - rx0, TOP - 310 - BOTTOM, "What I learned this year")
    ruled(p, rx0 + 5, rx1 - 5, top, BOTTOM + 2, 15)


TITLES = {
    budget: "Monthly budget",
    expenses: "Expense tracker",
    bills: "Bills",
    savings: "Savings",
    debt: "Debt payoff",
    funds: "Sinking funds",
    subscriptions: "Subscriptions",
    year_money: "Year in money",
}
