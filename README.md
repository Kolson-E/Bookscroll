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
the Books library. Import DRM-free files from the Files picker instead (iCloud Drive, On My
iPhone, or any file provider): Library tab → **+**. You can pick several files at once.

Each file shows its progress while it imports. Failed files show a clear reason:

| Problem | Message |
|---|---|
| Not a ZIP/PDF, damaged archive, missing `container.xml` or OPF | "The file could not be read. …" |
| Apple FairPlay (`sinf.xml`), Adobe (`rights.xml`) or encrypted content in `encryption.xml` | "This book is DRM-protected. …" |
| PDF that needs a password | "This PDF is password-protected or encrypted. …" |
| PDF with no text layer (scan) | "This PDF has no text layer. …" |

Font obfuscation in `encryption.xml` is not DRM and is accepted.

## Using the app

| Tab | What it does |
|---|---|
| Feed | The timeline. Toolbar left: **Mix all books** or **One book**. Toolbar right: **Paragraphs** or **Passages** (remembered). Pull to refresh reshuffles the mix. |
| Library | Import, see title, author, format and progress, swipe to delete (removes the book, all its posts and marks). |
| Saved | Liked and bookmarked posts, newest first, filter All / Liked / Bookmarked. |

Tap a post or its avatar to open **read in context**: the book around the post, the post
highlighted and centred, more paragraphs loading as you scroll either way. **Continue in feed
from here** moves the book's position to the top paragraph on screen.

Share offers the post as quoted text followed by "Title by Author", or as an image card.

## Design notes

### Post styles

| Style | One post = |
|---|---|
| Paragraphs (default) | Exactly one paragraph. Never merged, never split. Long ones collapse after 10 lines with "Show more". |
| Passages | About 80 words cut on sentence boundaries (NLTokenizer): close at ~80, never over 130 unless one sentence is, close at a paragraph end once at 40+. Passages never span a chapter change. |

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
`ordinal << 33 | style << 32 | charStart`. Unique attributes are indexed by SQLite, so:

- the feed loads 20 segments at a time with a key range query and `fetchLimit`;
- "which segment contains offset X" is one indexed query (`key <= X`, descending, limit 1).

No code path loads all segments of a book, so 50 books with about 100,000 segments per style
stay smooth. iOS 17 has no `#Index` macro; the unique keys give the same effect.

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

`BookscrollTests` (XCTest):

| Area | File |
|---|---|
| Paragraph segmentation, passage chunker, tiling, style switch, marks | `SegmentationTests.swift` |
| HTML to text | `HTMLTextTests.swift` |
| EPUB paths, OPF/NCX/nav parsing, end-to-end import into SwiftData, DRM and error cases | `EPUBTests.swift` |
| PDF paragraph detection on a generated PDF (headers, footers, hyphenation, page break, outline), scanned PDF | `PDFTests.swift` |
| Feed: no repeats, never stalls, position advances only when shown, one-book mode, threads | `FeedEngineTests.swift` |

## Verification status

Verified by CI on GitHub Actions (`macos-15` runner, Xcode 16.4, iPhone 17 Pro simulator with
iOS 26.2): the project generates with XcodeGen, the app and tests build, and all 59 tests pass.

Not verified:

- No run on a physical device, and no run on an iOS 17 simulator (the deployment target is
  iOS 17.0 and the code uses only iOS 17 APIs, but CI tests on the newest runtime).
- The SwiftUI layer has no UI tests. Scrolling, the thread line, "Show more", read in context
  centring and paging, share sheets, the Files picker, haptics, VoiceOver and Dynamic Type
  behaviour were not exercised by automation.
- Performance with 50 books and about 100,000 segments per style was not measured. The design
  relies on SQLite indexing the unique key columns; the queries are bounded, but no benchmark
  was run.
- PDF paragraph detection is tested on generated PDFs. Real PDFs (multi-column layouts,
  unusual fonts, ligatures) can give worse paragraphs.

## Accessibility

Every control has a VoiceOver label. Each post is its own element; posts inside a thread start
with "Continues thread". Text uses Dynamic Type styles (serif body) up to accessibility sizes.
Liked and bookmarked states use filled icons and VoiceOver values, not only colour. Like and
bookmark give haptic feedback. Light and dark mode follow the system; dark mode uses a pure
black background.
