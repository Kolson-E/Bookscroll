# Bookscroll

Scroll through your own books like a social timeline. Bookscroll cuts DRM-free EPUB and PDF
files into posts and shows them in an endless vertical feed. Stop on any post and read on from
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
To run on a device, set your team under Signing & Capabilities in Xcode.

CI (`.github/workflows/ci.yml`) runs `xcodegen generate` and `xcodebuild test` on a macOS
runner against the newest available iPhone simulator.

## Getting books in

Apple Books has no public API and its purchases are DRM-protected, so Bookscroll does not read
the Books library. Import DRM-free files instead:

| Way in | How |
|---|---|
| Files picker | Library tab → **+**, or **Import Books** on the empty Feed or Library screen. Pick one or more files from iCloud Drive, On My iPhone or any file provider. |
| Open in Bookscroll | In Files, Mail, Safari downloads or another app: Share → **Bookscroll**. The app opens on the Library tab and imports the file. |

Bookscroll registers EPUB (`org.idpf.epub-container`) and PDF (`com.adobe.pdf`) as document
types with rank *Alternate*, so it never replaces your default app for these files. A file
sent from another app arrives as a copy in `Documents/Inbox`; Bookscroll deletes that copy
after the import, and your original stays where it was.

Each file shows its progress while it imports. If you leave the app, the import asks iOS
for extra time to finish. Failed files show a clear reason:

| Problem | Message |
|---|---|
| Not an EPUB or PDF | "This is not an EPUB or PDF file." |
| Damaged archive, missing `container.xml` or OPF, missing file | "The file could not be read. …" |
| Apple FairPlay (`sinf.xml`), Adobe (`rights.xml`) or encrypted content in `encryption.xml` | "This book is DRM-protected. …" |
| PDF that needs a password | "This PDF is password-protected or encrypted. …" |
| PDF with no text layer (scan) | "This PDF has no text layer. …" |
| Same title, author and text as a book in the library | "“Title” is already in your library." |

Font obfuscation in `encryption.xml` is not DRM and is accepted.

## Using the app

| Tab | What it does |
|---|---|
| Feed | The timeline. Toolbar left: **Mix all books** or **One book**. Toolbar right: **Jump to** (One book mode), then **Paragraphs** or **Passages** and **Focus mode**. Pull to refresh reshuffles the mix. |
| Library | Import, see title, author, format, progress and Mix status, swipe to delete. Touch and hold a book for **Jump to…**, **Hide from Mix**, **Snooze**, and **How often** (less, normal, more). **Search** finds books by title or author and paragraphs by their words (all words must match; the last word can be the start of a word). A paragraph opens the reader there. |
| Saved | **Bookmarks** (your saved places, as a feed), **Likes**, and **Highlights**, newest first. A highlight shows the exact text; tap it to read around it. Touch and hold for Copy with citation, Share as image, Remove highlight. |
| Settings | Theme, accent colour, density, post and reader fonts, maximum words per post, focus mode, double-tap to like. |

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

Mix leaves out books that are hidden or snoozed (until the snooze ends) and picks books in
proportion to their weight (less 0.5, normal 1, more 2). One book mode ignores the filters.
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
- The store opens through a versioned schema (`BookscrollSchemaV1`) and a migration plan
  (`BookscrollMigrationPlan`, `Models/Schema.swift`). A test opens a library made before the
  plan existed. A future model change adds a V2 schema and a migration stage, so an update
  never needs to delete the library.
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

`BookscrollTests` (XCTest, 137 tests):

| Area | File |
|---|---|
| Paragraph segmentation, passage chunker, tiling, style switch, marks | `SegmentationTests.swift` |
| HTML to text | `HTMLTextTests.swift` |
| EPUB paths, OPF/NCX/nav parsing, end-to-end import into SwiftData, DRM and error cases | `EPUBTests.swift` |
| PDF paragraph detection on a generated PDF (headers, footers, hyphenation, page break, outline), scanned PDF | `PDFTests.swift` |
| Feed: no repeats, never stalls, position advances only when shown, one-book mode, threads | `FeedEngineTests.swift` |
| Store key queries, position clamping, chunked deletion, duplicates, ordinals | `StoreTests.swift` |
| Files picker, staging, Open in Bookscroll, import queue | `ImportTests.swift` |
| Reader window and paging, like/bookmark, deletion, position saving | `AppFlowTests.swift` |
| 50 books: key queries use an index, page and delete timings | `ScaleTests.swift` |
| Schema V1 and V2, unversioned V1 store, V1 to V2 migration with backfill, privacy manifest, save throttle | `FoundationTests.swift` |
| FTS5 search index: query escaping, add/search/remove, backup exclusion, backfill | `SearchIndexTests.swift` |
| Settings defaults and storage, palette and accent contrast (WCAG), citation | `AppearanceTests.swift` |
| Word-limit splitting, Auto limit, resume inside a split paragraph, chapter starts, Mix filters and weights, Jump to, peek | `SplitAndFilterTests.swift` |
| Highlights (exact range, merge, remove, across paragraphs, delete), Saved lists, Library search, share card styles and themes | `MarksAndSearchTests.swift` |

`BookscrollUITests` (XCUITest, 15 tests) drive the app on a simulator with a seeded in-memory
library:

- Empty library, Files picker, like and bookmark, Saved tab, read in context, Continue in feed,
  post style and One book thread, swipe to delete.
- Settings: theme, accent and focus mode change the feed.
- A long paragraph splits into numbered parts; double tap likes a post.
- Jump to a chapter; long press shows the peek and "Look up a word".
- Highlight a post, find it in Saved › Highlights and open it in the reader; search the
  Library text and open a result; the share card sheet in each style.
- `performAccessibilityAudit()` on the feed, library, Saved, Settings and reader screens in the
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

- No run on a physical device.
- Share sheets, the Files picker contents, haptics and the system Look Up panel are shown by
  the system; the tests check that they open, not what they contain.
- PDF paragraph detection is tested on generated PDFs. Real PDFs (multi-column layouts,
  unusual fonts, ligatures) can give worse paragraphs.

## Accessibility

Every control has a VoiceOver label. Each post is its own element; posts inside a thread start
with "Continues thread"; split posts say "Part n of m"; the first post of a chapter says "New
chapter". Like, bookmark and Copy with citation are VoiceOver actions on each post. Text uses
Dynamic Type styles up to accessibility sizes. Liked and bookmarked states use filled icons and
VoiceOver values, not only colour. Like and bookmark give haptic feedback. Every theme and
accent passes a WCAG contrast test (4.5:1 for text), and the UI tests run Apple's accessibility
audit on each theme.
