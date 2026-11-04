# Bookscroll

Scroll through your own books like a social timeline. Bookscroll cuts DRM-free EPUB, PDF, plain
text, Markdown, HTML and RTF files, and text you paste, into posts and shows them in an endless vertical feed. Stop on any post and read on from
there in normal book layout.

Fully offline: no accounts, no server, no analytics, no network calls.

## Requirements

- Xcode 15.4 or later (Swift 5.9+), iOS 17 SDK or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- An iPhone or iPad with iOS 17+, or the iOS Simulator

## Build and run

```sh
brew install xcodegen
xcodegen generate            # creates Bookscroll.xcodeproj (not committed)
open Bookscroll.xcodeproj    # run the "Bookscroll" scheme
```

To run the tests from the command line:

```sh
xcodegen generate
xcodebuild test \
  -project Bookscroll.xcodeproj \
  -scheme Bookscroll \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO
```

Use any installed iPhone simulator name (`xcrun simctl list devices available`).

## Run on your own devices

Bookscroll is made for personal use: you build it and install it from Xcode. It is not on the
App Store.

1. Make `Support/Local.xcconfig` (git ignores it) with your team and a bundle id of your own:

   ```
   DEVELOPMENT_TEAM = ABCDE12345
   BASE_BUNDLE_ID = com.yourname.Bookscroll
   ```

   Your team id is in Xcode › Settings › Accounts (select the team; a free Apple ID gives a
   "Personal Team"). The widget extension (`<BASE_BUNDLE_ID>.Widgets`) and the app group
   (`group.<BASE_BUNDLE_ID>`) follow the bundle id.
2. `xcodegen generate`, open the project, pick your device, and run the **Bookscroll** scheme.

| Device | How it runs |
|---|---|
| iPhone, iPad (iOS 17+) | Native. |
| Mac with Apple silicon | Pick **My Mac (Designed for iPad)** as the run destination. Drag books from Finder onto the window; ⌘O imports. |
| Apple Vision Pro | Pick the Vision Pro **(Designed for iPad)** destination. It runs as an iPad app in a window. |

With a free Apple ID, an app installed from Xcode stops opening after 7 days; run it from Xcode
again to renew it (your library stays). A paid developer account renews it for a year. If the
app group cannot be made for your team, the app still runs; only the widgets show "No book in
progress".

CI (`.github/workflows/ci.yml`) runs `xcodegen generate` and `xcodebuild test` on a macOS
runner against the newest available iPhone simulator.

## Getting books in

Apple Books has no public API and its purchases are DRM-protected, so Bookscroll does not read
the Books library. Import DRM-free files instead:

| Way in | How |
|---|---|
| Files picker | Library tab → **+**, or **Import Books** on the empty Feed or Library screen. Pick one or more files from iCloud Drive, On My iPhone or any file provider. |
| Open in Bookscroll | In Files, Mail, Safari downloads or another app: Share → **Bookscroll**. The app opens on the Library tab and imports the file. |
| A folder | In the Files picker, pick a folder: every book file in it and its subfolders is queued. Books already in the library are skipped without an error. |
| Synced folder | Settings › **Synced folder** › **Choose Folder…**. Each new book file in that folder (and its subfolders) is imported when the app opens or comes back to the front, or on **Sync Now**. A file is imported once, by its path. Removing a file does not delete the book; a deleted book is not imported again. iCloud files that are not downloaded yet are asked to download and come in on the next sync. |
| Paste Text | Library toolbar → **Paste Text**. |

Bookscroll registers EPUB (`org.idpf.epub-container`), PDF (`com.adobe.pdf`), plain text
(`public.plain-text`), Markdown (`net.daringfireball.markdown`, declared as an imported type),
HTML (`public.html`) and RTF (`public.rtf`) as document types with rank *Alternate*, so it never replaces your default app for these files. A file
sent from another app arrives as a copy in `Documents/Inbox`; Bookscroll deletes that copy
after the import, and your original stays where it was.

Each file shows its progress while it imports. If you leave the app, the import asks iOS
for extra time to finish. Failed files show a clear reason:

| Problem | Message |
|---|---|
| Not a supported format | "Bookscroll imports EPUB, PDF, plain text, Markdown, HTML and RTF files. This file is none of these." |
| Binary data in a `.txt`, `.md` or `.html` file | "The file could not be read. It does not contain text." |
| Empty text file or paste | "No readable text was found in this book." |
| Damaged archive, missing `container.xml` or OPF, missing file | "The file could not be read. …" |
| Apple FairPlay (`sinf.xml`), Adobe (`rights.xml`) or encrypted content in `encryption.xml` | "This book is DRM-protected. …" |
| PDF that needs a password | "This PDF is password-protected or encrypted. …" |
| PDF with no text layer (scan) | "This PDF has no text layer. …" |
| Same title, author and text as a book in the library | "“Title” is already in your library." |

Font obfuscation in `encryption.xml` is not DRM and is accepted.

### Text formats

| Format | Paragraphs | Chapters | Title and author |
|---|---|---|---|
| Plain text (`.txt`) | Blank lines separate paragraphs; the lines inside one are joined (hard-wrapped files). Without blank lines, one paragraph per line. UTF-8, UTF-16 with BOM, else Windows-1252. | A line on its own: Chapter, Part, Book, Prologue, Epilogue and similar words alone or with a number ("Chapter 2: The Flood", "Part Two", "Book I"), a number, or a Roman numeral. "Part of me knew." stays a paragraph. | File name. A Project Gutenberg file: its `Title:` and `Author:` lines; the licence before `*** START OF` and after `*** END OF` is removed. |
| Markdown (`.md`, `.markdown`) | As plain text; list items and code blocks are paragraphs; emphasis, links, images and quotes lose their markup. | `#` to `###` headings. | Front matter `title:` and `author:`; else a first `#` heading before any text is the title. |
| HTML (`.html`, `.htm`) | The same block rules as EPUB chapters. | `h1` to `h3`. | `<title>` and `<meta name="author">`. |
| RTF (`.rtf`, or any file that starts with `{\rtf`) | One per paragraph of the document. | As plain text. | File name. |
| Pasted text | As plain text. | As plain text. | What you type; else "Pasted text" and "Unknown author". |

**Paste Text** (Library toolbar) opens a sheet: title, author, the text (with a Paste button),
and a word count. **Add** queues it like a file import.

## Using the app

| Tab | What it does |
|---|---|
| Feed | The timeline. Toolbar left: **Mix all books**, a **Shelf**, or **One book**. Toolbar right: **Jump to** (One book mode), then **Paragraphs** or **Passages** and **Focus mode**. Pull to refresh reshuffles the mix. |
| Library | Import, see cover, title, author, format, progress and Mix status, swipe to delete. **Sort and filter** (toolbar left): sort by recently read, recently added, title, author or progress; show all books, reading, not started, finished or hidden from Mix; EPUB, PDF or text formats only. **Reading Stats** (toolbar left): reading time today and this week, words today, streak, a chart of the last 14 days, speed, total time, books finished this year, and the time left in each book you are reading. **Paste Text** (toolbar right) adds text as a book. Touch and hold a book for **Jump to…**, **Mark as Finished**, **Edit Details…** (with **Replace File…**: a new version of the book takes over its place, marks, details and shelves; where the text changed they go to the nearest matching words), **Hide from Mix**, **Snooze**, and **How often** (less, normal, more). **Search** finds books by title or author and paragraphs by their words (all words must match; the last word can be the start of a word). A paragraph opens the reader there. |
| Shelves | Your own groups of books (a book can be on more than one shelf). **New Shelf**, rename, reorder, delete (the books stay in the library). In a shelf: **Add or Remove Books…**, reorder, swipe to remove, and **Read as Feed**: a Mix of only the shelf's books. In the Library, touch and hold a book for **Add to Shelf**. |
| Saved | **Bookmarks** (your saved places, as a feed), **Likes**, and **Highlights**, newest first. A highlight shows the exact text; tap it to read around it. Touch and hold for Copy with citation, Share as image, Remove highlight. |
| Settings | Theme, accent colour, density, post and reader fonts, maximum words per post, focus mode, double-tap to like. **Synced folder** (see Getting books in). **Back Up and Restore**: export a JSON file with every book's place, finish date, Mix settings, title, author, avatar photo and marks, and the shelves (not the books or settings); restore it after importing the books again (books are found by title, author and length; marks are not added twice). **Storage**: total space, split into library, search index, and covers and photos; every book with its estimated size, largest first (its share of the library and index follows its length); swipe to delete. |

On a post:

| Action | Result |
|---|---|
| Tap | **Read in context**: the book around the post, the post highlighted. Select text there for **Highlight** (or **Remove highlight**), **Look Up** (system dictionary), Copy or Translate. |
| Double tap | Like, with a heart (it never unlikes). Can be turned off in Settings. |
| Touch and hold | **Context peek**: two paragraphs before and after the post. Menu: Like, Bookmark, Highlight, Copy with citation, Look up a word, Read in context, Continue from here. |
| **⋯** | Show more or less from this book, snooze it for a day or a week, hide it from Mix. |
| Share | Copy text, copy with citation ("— Title, Author · Chapter 3 · 42%"), share as text, or **Share as image**: a card in the **Post**, **Quote** or **Minimal** style, in Light, Dark or Sepia colours, with a preview. The last choice is remembered. |

**Jump to** (feed toolbar in One book mode, the reader, or a book in the Library) goes to the
start, a percent, or a chapter. Chapters you have reached are ticked, and the chapter you are
in is marked.

**Library order.** Title sort ignores a leading "The", "A" or "An"; author sort uses the
surname ("Jane Austen" files under A; "Austen, Jane" is read as surname first; for several
authors the first counts). Ties fall back to the title and then a fixed id, so the order never
changes between redraws. Books never opened sort after the ones you read, newest import first.

**Finished** books leave Mix (One book mode still shows them), show "Finished" and the date in
the Library, and count as complete in the progress sort. **Mark as Not Finished** brings a book
back. Finishing is a Library action only.

**Covers and avatars.** The avatar of a book is its cover: the EPUB cover image (the
`cover-image` item, else `<meta name="cover">`, else an image named "cover") or the first page
of a PDF. **Edit Details** can set a photo instead, remove it, or show the first letter on the
book's colour. Images are stored as JPEG files of at most 360 pixels in
`Application Support/Covers`, outside the database. Edit Details also changes the title and
author the app shows (the file is not changed) and shows the file name, file size, detected
language, and the added, last read and finished dates.

**Reading stats and time left.** The feed counts the text it moves past (a book's place moving
forward; a move of more than 20,000 characters at once is a jump and does not count). Time
counts between two such moves when they are at most 2 minutes apart, so time with the app open
but unused does not count, and the first move after the app goes to the background adds no
time. Your speed is the counted text over the counted time, after 10 minutes of reading; until
then the app uses 200 words a minute (a word is 6 characters). Each book in the Library shows
"N% read · about X left" at that speed (rounded to 5 minutes, or 1 minute under 10 minutes).
Stats are kept per day in `Application Support/ReadingStats.json`, outside the database and
the backup.

**Widgets, Live Activity, Spotlight, Shortcuts, Focus.**

| Feature | What it does |
|---|---|
| Current Book widget | Home Screen (small, medium) and Lock Screen (circular, rectangular, inline): the book you read last that is not finished, how far you are, the time left, today's reading time and streak; the medium size also shows the start of the next paragraph. Tap to continue that book. The app writes what the widget shows to the app group folder when it goes to the background and after the library changes. |
| Live Activity | While you read, the book, percent, time left and today's minutes show on the Lock Screen and in the Dynamic Island. When you leave the app it shows "Paused" for an hour; tap it to continue. Coming back removes it. Settings › Lock Screen turns it off. |
| Spotlight | Every book (title, author, percent) and your newest 500 highlights. A book opens in One book mode at your place; a highlight opens the reader around it. |
| Shortcuts and Siri | **Continue Reading**, **Open Book** (choose a book), **Reading Today** ("You read 25 min today. Streak: 4 days."). They also show in Spotlight and the Shortcuts app with no setup. |
| Focus filter | Settings › Focus › (a Focus) › Add Filter › Bookscroll: while that Focus is on, the feed shows one shelf. The Feed mode menu says so; choosing another mode there ends it until the Focus changes. |
| Drag and drop | Drop EPUB, PDF, text, Markdown, HTML or RTF files anywhere on the app to import them (iPad, Mac, Vision Pro). Drag a post to another app to drop its text with the citation. |
| Links | `bookscroll://continue`, `bookscroll://book/<id>`, `bookscroll://highlight/<id>` (used by the widgets, the Live Activity and Spotlight). |

**Language** is detected once per book from the first 6,000 characters (`NaturalLanguage`,
shown only at 50% confidence or more).

**Highlights** are marks like bookmarks: a book and a character range. Highlights that overlap
or touch merge into one. They show on a marker colour in the feed and the reader (text on it
keeps at least 7:1 contrast). VoiceOver users highlight a whole paragraph with the
"Highlight paragraph" action in the reader, or a whole post with the "Highlight" action.

## Appearance

The post layout follows X: avatar, bold title with the author in grey, chapter and percent,
the text, and a grey action bar. X's typeface (Chirp) belongs to X and cannot be bundled, so
posts use the system font (SF Pro) in X's sizes and colours. Text follows the system Dynamic
Type size.

| Setting | Choices (default first) |
|---|---|
| Theme | Night (pure black), Light, Sepia, System |
| Accent colour | X's six: blue, yellow, pink, purple, orange, green. Each has a bright shade for dark themes and a deep shade for light and sepia themes, so accent text reaches 4.5:1. |
| Density | Comfortable, Compact |
| Post font | Sans (X style), Serif |
| Reader font | Serif, Sans |
| Maximum words per post | Auto, Off, 60, 80, 120, 200 |
| Focus mode | Off. On: posts show only their text. |
| Double-tap to like | On |

`PaletteHex` holds every text and background colour; a unit test checks each text colour
against each background it is used on (WCAG AA, 4.5:1).

## Design notes

### Post styles

| Style | One post = |
|---|---|
| Paragraphs (default) | One paragraph. Never merged. Split only by the word limit (below). |
| Passages | About 80 words cut on sentence boundaries (NLTokenizer): close at ~80, never over 130 unless one sentence is, close at a paragraph end once at 40+. Passages never span a chapter change. |

### Word limit and split posts

A post over the limit continues in the next post: part one takes as many whole sentences as
fit, part two continues from there, and so on ("1/3", "2/3", "3/3" after the percent). A
sentence longer than the limit is cut between words. In One book mode the parts form a
thread. Parts are offset ranges that tile the segment, so likes, bookmarks, the reading
position and resume work inside a paragraph: if you stop after part 2, the feed resumes at
part 3.

**Auto** (the default) uses each book's own limit: the smallest length that fits 95% of its
paragraphs, at least 40 words. It is computed at import (and once in the background for books
imported before this setting existed). A post that is still taller than 10 lines collapses
with "Show more".

### Chapter starts

The first post of each chapter shows "New chapter · Chapter 3" in the accent colour (in One
book mode, in the chapter row above it). Resuming in the middle of a chapter does not show it.

### Mix filters

Mix leaves out books that are hidden, snoozed (until the snooze ends) or finished, and picks
books in proportion to their weight (less 0.5, normal 1, more 2). One book mode and shelf
feeds ignore the filters (the reader chose those books); a shelf feed still uses the weights.
Hiding or snoozing a book removes its unseen posts at once; posts you already saw stay. Mix
opens on the book of the last post you had at the top, so a mode switch or a relaunch
returns to the same place.

In One book mode, consecutive posts from the same chapter form a thread joined by a line
through the avatars; a chapter change breaks the thread and shows a chapter row. In Mix mode
each post has "Show thread", which opens read in context.

### Positions are offsets, not post indices

Each book has one normalized text: its paragraphs joined by a blank line. All offsets (reading
position, segment ranges, likes and bookmarks) are UTF-16 offsets into that text. Both styles
are computed once at import and stored. Each style's segments tile the text exactly (each range
includes the separator after it), so any offset falls in exactly one segment of each style.
Switching style resumes at the segment that contains the saved offset.

A post's like or bookmark is stored as a text range. A post shows as liked when its range
overlaps a liked range, so marks carry over between styles.

A book's position moves only when a post is actually shown: when it reaches the top of the
screen or is scrolled past. It never moves backward during scrolling; only "Continue in feed
from here" can move it back.

### Storage and scale

SwiftData models: `Book`, `Segment`, `Mark` (`Book` cascades to its segments and marks).
Each `Segment` has two unique integer keys, `ordinal << 33 | style << 32 | index` and
`ordinal << 33 | style << 32 | charStart`. SQLite keeps a unique index on each (checked by a
test that reads the store's schema and query plans), so:

- the feed loads 20 segments at a time with a key range query and `fetchLimit`;
- "which segment contains offset X" is one indexed query (`key <= X`, descending, limit 1).

No code path loads all segments of a book for display. iOS 17 has no `#Index` macro; the
unique keys give the same effect.

### Data safety

- An import writes the book and all its segments in one save. If the app stops during an
  import, nothing is left behind.
- Delete hides the book at once (`deletionPending`) and removes it in the background in one
  save (the cascade rule removes its segments and marks). If the app stops first, the
  deletion runs again at the next launch.
- A new book's ordinal is above every ordinal used by any book or segment, so its keys can
  never collide with old rows.
- Reading positions save while you scroll (at most every 5 seconds), when you use "Continue
  in feed from here", and when the app leaves the foreground. A crash loses at most a few
  seconds of position.
- The store opens through a versioned schema and a migration plan (`BookscrollMigrationPlan`,
  `Models/Schema.swift`). V1 and V2 are frozen copies of the models; V3 (finished and last read
  dates, language, source file, cover choice, and the `Shelf` entity) uses the live models.
  Tests open an unversioned V1 library, a V1 library and a V2 library with the current app.
  A model change adds a schema and a migration stage, so an update never needs to delete the
  library.
- `PrivacyInfo.xcprivacy` declares no tracking, no collected data, and the two required-reason
  APIs the app uses: UserDefaults (CA92.1, settings) and file timestamps (C617.1, clean-up of
  old import copies).

### Search index

SwiftData has no full-text search, so Bookscroll keeps a second SQLite file,
`Application Support/Search.sqlite` (`Search/SearchIndex.swift`). It holds every paragraph in an
FTS5 table (unicode61 tokenizer, accents ignored; FTS4 if FTS5 is missing). Queries keep only
words, so typed text can never act as a query operator; the last word matches as a prefix.
Results come ranked with a snippet around the match.

The index is a cache of the library. After each import or delete, and at launch, the app
compares it with the library in the background: it adds books it does not hold (reading
segments 2,000 at a time) and drops books that are gone. If the file is lost, it is rebuilt.
The file is excluded from device backups because it only repeats text the library holds.
The search screen comes in a later phase; this part is the engine.

### Text pipeline

- **EPUB**: `META-INF/container.xml` → OPF metadata (title, creators), manifest and linear
  spine. XHTML in spine order, with relative and percent-encoded paths resolved. `head`,
  `script` and `style` removed. Each block element (`p`, `div`, `blockquote`, `li`, `h1`–`h6`,
  and structural containers) is one paragraph; `br` is a line break inside it, so poetry keeps
  its lines. Named and numeric entities are decoded. Spine items under 40 words (cover, contents)
  are skipped. Chapter label: first `h1`–`h3` of the document, otherwise the EPUB 3 navigation
  document (or the EPUB 2 NCX). Every heading updates the label for the paragraphs after it;
  headings are never posts.
- **PDF**: PDFKit line selections with their geometry. A new paragraph starts on a vertical gap
  over 1.5 × the page's median line spacing, an indented line, or after a line that ends in
  terminal punctuation and is shorter than 80% of the median line width. Hyphenated line ends are
  rejoined; other hard wraps become spaces. Lines that recur at the same position in the top or
  bottom 15% of most pages (digits ignored, so page numbers match) are removed. If paragraphs
  average more than 300 words, the book uses Passages style only and the Library says so. The
  PDF outline, when present, gives the chapter labels.
  - Two columns: when at least three lines sit in each half of a page and together hold 70%
    of its lines, the page is read as title, left column, right column; a paragraph can run on
    from one column to the next.
  - Headings: a short line (15 words or fewer) set at least 1.3 × the median line height starts
    a new paragraph. Without an outline, each heading starts a chapter and is not a post; with
    an outline, a heading that repeats its chapter's label is dropped. If more than a third of
    the paragraphs look like headings, type size is ignored.
  - A drop cap (one capital at least 1.8 × the line height) is joined to its word, and the
    lines beside it are not taken as indented.
  - Ligature characters (such as “ﬁ”) become plain letters.

### Dependency: ZIPFoundation

EPUBs are ZIP files, and Foundation on iOS has no public unzip API. Bookscroll uses
[ZIPFoundation](https://github.com/weichsel/ZIPFoundation) (MIT, pure Swift, no transitive
dependencies) only to read archive entries. Readium Swift Toolkit was rejected: it brings a full
publication model, navigator and many modules, while Bookscroll needs its own text pipeline
(paragraph extraction, labels, offsets) and only needs to read files out of a ZIP.

The tests build their EPUB fixtures with a small independent ZIP writer, so the reader is also
checked against archives it did not write.

### Model naming

The spec asked for a `paragraphsOnly` flag that is "true when Passages style was forced". The
property is named `passagesOnly` because that is what it means.

## Tests

`BookscrollTests` (XCTest, 218 tests):

| Area | File |
|---|---|
| Paragraph segmentation, passage chunker, tiling, style switch, marks | `SegmentationTests.swift` |
| HTML to text | `HTMLTextTests.swift` |
| EPUB paths, OPF/NCX/nav parsing, end-to-end import into SwiftData, DRM and error cases | `EPUBTests.swift` |
| PDF paragraph detection on a generated PDF (headers, footers, hyphenation, page break, outline), scanned PDF, two-column order, headings by type size, drop caps, ligatures | `PDFTests.swift` |
| Feed: no repeats, never stalls, position advances only when shown, one-book mode, threads | `FeedEngineTests.swift` |
| Store key queries, position clamping, chunked deletion, duplicates, ordinals | `StoreTests.swift` |
| Files picker, staging, Open in Bookscroll, import queue | `ImportTests.swift` |
| Text anchors (same text, moved text, lost text, nearest of several), Replace File (place, marks, details, shelves), backup and restore (no copies on a second restore, missing books), matching rules, file errors | `ReadingStateTests.swift` |
| Folder scan (subfolders, hidden files, iCloud placeholders), synced folder (each file once, kept across launches, stop, missing folder), quiet duplicates, folder import | `FolderSyncTests.swift` |
| Storage totals, write-ahead log, per-book shares that add up to the total, order, missing files | `StorageTests.swift` |
| Plain text (hard wraps, chapter headings, Gutenberg frame, encodings), Markdown, HTML, RTF by magic bytes, pasted text and its queue job | `TextFormatTests.swift` |
| Reader window and paging, like/bookmark, deletion, position saving, reading counted once | `AppFlowTests.swift` |
| Links (round trip, bad links; opening the last book, a book, a highlight, a missing one), widget content (book read last, day change, streak, file), the app's widget data after reading, Spotlight entries, Live Activity update rules, Focus filter shelf before your own choice, dropped files (copy, name, text is not a file) | `PlatformTests.swift` |
| Reading time only for short gaps, jumps ignored, pause, measured speed after 10 minutes, time left, streak, last 14 days, week, saving and loading, duration formats | `ReadingStatsTests.swift` |
| 50 books: key queries use an index, page and delete timings | `ScaleTests.swift` |
| Schema V1–V3, unversioned V1 store, V1 and V2 migrations with backfill, privacy manifest, save throttle | `FoundationTests.swift` |
| FTS5 search index: query escaping, add/search/remove, backup exclusion, backfill | `SearchIndexTests.swift` |
| Settings defaults and storage, palette and accent contrast (WCAG), citation | `AppearanceTests.swift` |
| Word-limit splitting, Auto limit, resume inside a split paragraph, chapter starts, Mix filters and weights, Jump to, peek | `SplitAndFilterTests.swift` |
| Highlights (exact range, merge, remove, across paragraphs, delete), Saved lists, Library search, share card styles and themes | `MarksAndSearchTests.swift` |
| Library sort and filter, title and author filing, finished books and Mix, language detection, cover storage and cache, EPUB and PDF covers, file facts, edit details, avatar photos, shelves and the shelf feed | `LibraryTests.swift` |

`BookscrollUITests` (XCUITest, 18 tests) drive the app on a simulator with a seeded in-memory
library:

- Empty library, Files picker, like and bookmark, Saved tab, read in context, Continue in feed,
  post style and One book thread, swipe to delete.
- Settings: theme, accent and focus mode change the feed.
- A long paragraph splits into numbered parts; double tap likes a post.
- Jump to a chapter; long press shows the peek and "Look up a word".
- Highlight a post, find it in Saved › Highlights and open it in the reader; search the
  Library text and open a result; the share card sheet in each style.
- Mark a book as finished, filter the Library to finished books, and rename a book in Edit
  Details (with audits of the filtered Library and the details sheet).
- Make a shelf, add a book, and read the shelf as a feed.
- Paste text as a book; it shows in the Library and in the Feed mode menu (with an audit of
  the Paste Text sheet).
- `performAccessibilityAudit()` on the feed, library, Shelves, Saved, Settings, Storage, Synced folder, Back Up and Restore, and reader screens in the
  Light, Night and Sepia themes, and in Compact density with focus mode and the serif font.
- The largest accessibility text size.

## Verification status

CI on GitHub Actions runs every test on two configurations:

| Runner | Xcode | Simulator |
|---|---|---|
| `macos-15` | newest installed | iPhone, newest iOS (26.2) |
| `macos-14` | 15.4 | iPhone, iOS 17.5 (the deployment target family) |

Measured in CI (50 books, about 100,000 segments per style, newest iOS simulator): a feed page
takes about 12.5 ms on average; deleting one book takes about 0.6 s; a key lookup takes about
6 ms.

Not verified:

- No run on a physical device, a Mac or Apple Vision Pro.
- The widgets, the Live Activity, Spotlight results, Shortcuts and the Focus filter are drawn or
  run by the system. CI compiles them and tests the data and rules behind them, but cannot
  show them on a simulator Lock Screen or in Settings › Focus.
- Share sheets, the Files picker contents, haptics and the system Look Up panel are shown by
  the system; the tests check that they open, not what they contain.
- PDF paragraph detection is tested on generated PDFs and synthetic line geometry (two
  columns, headings, drop caps). Real PDFs with three or more columns, text in boxes, or
  footnotes can still give worse paragraphs.

## Accessibility

Every control has a VoiceOver label. Each post is its own element; posts inside a thread start
with "Continues thread"; split posts say "Part n of m"; the first post of a chapter says "New
chapter". Like, bookmark and Copy with citation are VoiceOver actions on each post. Text uses
Dynamic Type styles up to accessibility sizes. Liked and bookmarked states use filled icons and
VoiceOver values, not only colour. Like and bookmark give haptic feedback. Every theme and
accent passes a WCAG contrast test (4.5:1 for text), and the UI tests run Apple's accessibility
audit on each theme.

Audit policy: every finding fails the UI test except a short list of known false positives
(see `isKnownFalsePositive` in the UI tests). Findings that the audit reports without an
element cannot be located or judged; they are printed (`AUDIT: ignored`) with a screenshot of
the screen (`audit-<screen>`) but do not fail. On iOS 26 they come from the glass tab bar over
scrolled content (contrast); on iOS 17 from rows that VoiceOver reads as one element (Dynamic
Type, clipping). The largest-text-size test saves pictures of the feed, Library and Settings
for a visual check.
