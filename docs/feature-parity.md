# Feature parity plan (October 2026)

What GoodNotes, Noteshelf 3 and Notability offer that Jotswift doesn't, and the order to build it.

## Where Jotswift already leads

- A built-in calendar with 10 templates, colour-coded calendars and month-flip animations
- Tasks and reminders
- Notebook skins
- A store with about 190 items and colourway planners

Competitors only offer these as PDF planners.

## Gaps

| Area | Competitors have | Jotswift today |
|---|---|---|
| **Lasso** | Lasso handwriting to move, resize, recolour, copy/paste, or turn into text | Select works on stickers, photos and text only |
| **Shapes** | Draw and hold to get a straight line, circle or arrow; a ruler | None |
| **Pens** | Fountain, ball, brush and pencil textures; any colour; saved favourites | Pen and highlighter, a fixed palette, 3 sizes |
| **Eraser** | Whole-stroke or partial erase; erase highlighter only | Stroke eraser |
| **Pencil** | Double-tap and squeeze actions, hover preview, laser pointer | Palm rejection, finger toggle |
| **Import** | Import a PDF, Word or PowerPoint file, or images, and write on it | Store templates only |
| **Export** | Export a page or notebook as PDF or image; print; share sheet | None |
| **Pages** | Thumbnail grid with drag-to-reorder; duplicate; copy to another notebook; bookmarks; outlines and links; vertical scrolling | Add, delete and rename pages, sections, page by page; bookmarks, a Go to page list, and planners open on today or where you left off |
| **Search** | Search inside handwriting and PDFs; convert handwriting to text | Notebook titles only |
| **Organising** | Tags, favourites, recents | Categories, groups, Trash |
| **Privacy** | Passcode or Face ID lock per notebook | None |
| **Backup** | Auto-backup to iCloud Drive, Google Drive or Dropbox; version history | Cloud sync only |
| **Audio** | Record while writing, tap ink to hear that moment, transcripts in 99 languages | None |
| **Capture** | Document scanner; several photos at once | One photo at a time |
| **AI** | Summaries, Q&A over notes, handwriting spellcheck, flashcards, quizzes, generated diagrams | None |
| **Study** | Flashcards, tape to hide answers, study timer | None |
| **Sharing** | Share links, real-time collaboration, object locking | Only on your own account |
| **Platforms** | Writing on web, Android and Windows; Mac app; widgets; iPad split view | Web is view-only for handwriting |
| **Canvas** | Whiteboard (infinite canvas) | Fixed pages |

## Phases

Each phase ships as its own TestFlight build. Sizes are rough: S is days, M is about a week, L is two weeks or more.

### 1. Writing that feels right (before launch)

**Done** in build 0.1.0+8 (October 2026).

| Feature | Size |
|---|---|
| Lasso for handwriting: move, resize, rotate, recolour, copy/cut/paste, duplicate, delete | L |
| Shape snapping by draw-and-hold: line, arrow, rectangle, circle, triangle; plus a ruler | M |
| More pen types (ballpoint, fountain, brush, pencil), any size, a colour picker, saved pen favourites | M |
| Partial eraser, "erase highlighter only", and auto-switch back to the pen | S |
| Apple Pencil double-tap and squeeze settings, and a laser pointer | S |

### 2. Documents in and out (before launch)

| Feature | Size |
|---|---|
| Import a PDF or images as a new notebook, or insert pages into a notebook; files picker and share-sheet "Open in Jotswift" | L |
| Export a page, section or notebook as PDF or PNG; share and print | M |
| Page manager: thumbnail grid, drag to reorder, duplicate, move or copy to another notebook (bookmarks are done) | M |
| Vertical scrolling as an option beside page-by-page | M |
| Your own links and outline entries within a notebook | S |

### 3. Find and protect

| Feature | Size |
|---|---|
| On-device handwriting recognition (ML Kit Digital Ink); search inside notes and PDFs; convert handwriting to text | L |
| Tags, favourite notebooks, Recents | S |
| Notebook lock with a passcode or Face ID (`local_auth`) | S |
| Automatic backup of PDFs to Files, iCloud Drive or Google Drive | M |
| Version history per page | M |

### 4. Audio and capture

| Feature | Size |
|---|---|
| Record audio while writing; tap any stroke to play from that moment; replay writing | L |
| Transcription (on-device Speech, or a Cloud Function) | M |
| Document scanner (VisionKit, or the ML Kit scanner on Android); several photos at once | S |

### 5. AI and study (Pro, or an AI add-on)

| Feature | Size |
|---|---|
| Summarise a page or notebook; ask questions about your notes. Uses Claude through a Cloud Function that runs on the recognised text | M |
| Handwriting spellcheck and tidy-up | M |
| Flashcards and quizzes from notes; tape tool to hide answers | M |
| Study timer that writes sessions into the Jotswift calendar | S |

### 6. Together and everywhere

| Feature | Size |
|---|---|
| Share a notebook by link (view only), then live collaboration using the existing Firestore sync | L |
| Handwriting on the web, with mouse and pen | M |
| Whiteboard notebooks (infinite canvas) | L |
| Home-screen widgets (favourites, today's agenda), Shortcuts, iPad multi-window | M |

## Recommendation

Do phases 1 and 2 before the App Store launch. Reviewers and switchers test lasso, shapes, PDF import and export first, and their absence is a deal-breaker for most of them. Phase 3 search and lock come next. Audio, AI and collaboration are the paid differentiators, and they build on the handwriting recognition in phase 3.
