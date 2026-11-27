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
runner against the newest available iPhone simulator. It runs only when you start it
(Actions › CI › Run workflow), so it does not use the private repository's macOS minutes on
every push.

## Install with AltStore (Windows PC, free)

No Mac and no paid account. A free Apple ID and a Windows PC on the same Wi-Fi as the iPhone.
`.github/workflows/altstore.yml` builds `Bookscroll.ipa` on a GitHub macOS runner and puts it on
the release **altstore** of this repository. AltStore signs it with your Apple ID.

**Build the app file (GitHub app or github.com):** Actions › AltStore build › Run workflow
(branch `main`). It takes about 10 to 15 minutes. Then Releases › **Bookscroll for AltStore**
holds `Bookscroll.ipa`.

**On the Windows PC (one time):**

1. Install **iTunes** and **iCloud** from apple.com (the download links on Apple's pages, not
   the Microsoft Store versions).
2. Install **AltServer** from altstore.io and start it. Its icon is in the system tray (click
   the ^ arrow near the clock).
3. Connect the iPhone with a cable. Unlock it and tap **Trust**. In iTunes, select the phone
   and turn on **Sync with this iPhone over Wi-Fi**, then **Apply**.
4. AltServer tray icon › **Install AltStore** › your iPhone. Sign in with your Apple ID.

**On the iPhone (one time):**

5. Settings › General › VPN & Device Management › your Apple ID › **Trust**.
6. Settings › Privacy & Security › **Developer Mode** › On. The phone restarts; confirm
   **Turn On**.

**Install Bookscroll:**

7. In Safari, sign in to github.com, open this repository › Releases › Bookscroll for AltStore,
   and tap **Bookscroll.ipa**. Tap **Download**.
8. Open **AltStore** › My Apps › **+** (top left) › Downloads › `Bookscroll.ipa`. Wait until
   it shows in My Apps, then open Bookscroll from the home screen.

| Fact | Detail |
|---|---|
| 7-day renewal | A free Apple ID signs apps for 7 days. AltStore renews them in the background when the PC is on, AltServer runs, and the phone is on the same Wi-Fi. In AltStore › My Apps you see the days left; tap **Refresh All** to renew by hand. |
| If it expires | Bookscroll does not open until you refresh it. Your library stays. |
| App limit | A free Apple ID allows 3 sideloaded apps at a time. AltStore is one; Bookscroll and its widget extension may count as two. |
| Widgets | The app finds the app group that AltStore makes (`group.<bundle id>.<team id>`). If the widgets still show "No book in progress", the rest of the app works the same. |
| Update the app | Run the workflow again, download the new `Bookscroll.ipa`, and open it in AltStore. Your library stays. |
| Not checked | AltStore and the iPhone install cannot be tested in CI. The build and the `.ipa` are. |

**SideStore** (sidestore.io) installs the same `.ipa` and renews it from the phone itself, so the
PC is needed only once for setup. Its setup has more steps.

## Install with TestFlight (no Mac)

`.github/workflows/testflight.yml` builds, signs and uploads the app on a GitHub macOS runner
with the newest release Xcode (26 or later; App Store Connect refuses older builds). You
install it on your iPhone with Apple's TestFlight app. You need a paid Apple Developer Program
membership (99 USD a year). You can do all steps from a phone browser and the GitHub app.

The workflow also runs by itself on the 1st of every odd month. With automatic distribution
(step 8) and automatic updates (step 9), a new build installs before the old one expires, so you
never refresh the app by hand.

1. **Put the workflows on `main`.** GitHub shows "Run workflow" and runs schedules only for
   workflows on the default branch. Open a pull request from `claude/new-session-c3goac` to
   `main` and merge it.
2. **Join the Apple Developer Program.** Use the Apple Developer app on iPhone, or
   developer.apple.com/programs/enroll. Approval can take up to 48 hours.
3. **Find your Team ID.** developer.apple.com/account › Membership details › Team ID
   (10 characters, like `ABCDE12345`).
4. **Make an App Store Connect API key.** appstoreconnect.apple.com › Users and Access ›
   Integrations › App Store Connect API › Team Keys › **+**. Name: `GitHub`. Access: **Admin**
   (the upload uses a cloud-managed distribution certificate, which needs Admin). Download the
   `.p8` file; Apple lets you download it one time only. Write down the **Key ID** and the
   **Issuer ID** (above the key list).
5. **Add the secrets to GitHub.** In this repository: Settings › Secrets and variables › Actions.

   | Kind | Name | Value |
   |---|---|---|
   | Secret | `APP_STORE_CONNECT_KEY_ID` | Key ID from step 4 |
   | Secret | `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID from step 4 |
   | Secret | `APP_STORE_CONNECT_KEY` | All the text of the `.p8` file, including the `BEGIN` and `END` lines |
   | Secret | `APPLE_TEAM_ID` | Team ID from step 3 |
   | Variable (Variables tab) | `BUNDLE_ID` | A bundle id of your own, like `com.yourname.bookscroll` |

   On a phone, open the `.p8` file in the Files app, select all, copy, and paste it into the
   secret.
6. **Run the workflow.** Actions › TestFlight › Run workflow › branch `main`. The first run
   registers the bundle ids (`BUNDLE_ID`, `BUNDLE_ID.Widgets`) and the app group
   (`group.BUNDLE_ID`) in your account. If App Store Connect has no app for the bundle id yet,
   the upload step fails with "has no app with the bundle id". This is expected.
7. **Make the app record.** appstoreconnect.apple.com › Apps › **+** › New App. Platform: iOS.
   Name: any name not used on the App Store (for example `Bookscroll <your initials>`).
   Language: yours. Bundle ID: pick the one from step 5. SKU: any text, like `bookscroll`.
   User access: Full Access. Then run the workflow again. When it succeeds, Apple processes the
   build (usually 5 to 30 minutes).
8. **Make the tester group.** App Store Connect › your app › TestFlight › Internal Testing ›
   **+**. Name it, turn on **Enable automatic distribution**, add yourself as a tester, and add
   the build if it is not added already. Apple emails you an invite.
9. **Install.** On the iPhone, install **TestFlight** from the App Store and sign in with the
   same Apple ID. Open the invite email (or the TestFlight app) and tap **Accept**, then
   **Install**. In TestFlight › Bookscroll, turn on **Automatic Updates**.

To get a new build at any time, run the workflow again. Each run uses the UTC date and time as
the build number, so builds always go up.

| Fact | Detail |
|---|---|
| Review | Internal testing (up to 100 members of your team) needs no App Review. |
| Expiry | A TestFlight build stops opening after 90 days. The schedule makes a new one every 2 months or less. Your library stays through updates. |
| Encryption question | Not asked: `ITSAppUsesNonExemptEncryption` is `NO`. |
| Certificates | Signing makes an "Apple Development" certificate on the runner. The last step revokes it through the API, so certificates do not pile up (the limit is small). |
| Secrets | The key is written to the runner's temp folder only for the run and is removed at the end. |
| Actions minutes | In a private repository, macOS minutes use your Actions allowance at a higher rate than Linux. One TestFlight run takes about 10 to 20 minutes. |
| Failures | GitHub emails you when a scheduled run fails. Run it again by hand; the old build still has about a month left. |

If the Archive step fails with a signing or provisioning error about the app group:
developer.apple.com/account › Identifiers › App Groups › **+**, add `group.<BUNDLE_ID>`. Then
open the App IDs `<BUNDLE_ID>` and `<BUNDLE_ID>.Widgets`, turn on **App Groups**, select
that group, save, and run the workflow again.

Status: the workflow cannot run in CI without your Apple account, so its first real test is
your first run. CI checks the same Release build for a device with the same Xcode when you run
it (job "Release build"), without signing.

## Getting books in

Apple Books has no public API and its purchases are DRM-protected, so Bookscroll does not read
the Books library. Import DRM-free files instead:

| Way in | How |
|---|---|
| Find Books on This iPhone | Library tab → **+** → **Find Books on This iPhone**, or the same button on the empty Feed or Library screen. iOS lets an app read only the folders you pick, and no app can search the whole iPhone, so you allow a folder once (for example Downloads, iCloud Drive or On My iPhone; you can allow several). Each time Find Books opens it lists every EPUB, PDF, text, Markdown, HTML and RTF file in those folders and their subfolders, grouped by folder, with format, size and subfolder. Search by file name, tick files or **Select All**, then **Import**. Books whose file name is already in the library are marked and cannot be ticked. Files still in iCloud are listed and download when imported. Swipe left on a folder to stop looking in it. |
| Files picker | Library tab → **+** → **Choose Files**, or **Import Books** on the empty Feed or Library screen. Pick one or more files from iCloud Drive, On My iPhone or any file provider. The picker's **Recents** and search also find book files. |
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
| Feed | The timeline. Toolbar left: **Mix all books**, **Choose books…** (tick any set of books: two or more are mixed, one is read straight through; **Select All** and **Save as Shelf** are in the sheet; the menu then shows **Chosen books (n)…**), a **Shelf**, or **One book**. Toolbar right: **Jump to** (One book mode), then **Paragraphs** or **Passages** and **Focus mode**. Pull to refresh reshuffles the mix. |
| Library | Import, see cover, title, author, format, progress and Mix status, swipe to delete. **Sort and filter** (toolbar left): sort by recently read, recently added, title, author or progress; show all books, reading, not started, finished or hidden from Mix; EPUB, PDF or text formats only. **Reading Stats** (toolbar left): reading time today and this week, words today, streak, a chart of the last 14 days, speed, total time, books finished this year, and the time left in each book you are reading. **Paste Text** (toolbar right) adds text as a book. Touch and hold a book for **Jump to…**, **Mark as Finished**, **Edit Details…** (with **Replace File…**: a new version of the book takes over its place, marks, details and shelves; where the text changed they go to the nearest matching words), **Hide from Mix**, **Snooze**, and **How often** (less, normal, more). **Search** finds books by title or author and paragraphs by their words (all words must match; the last word can be the start of a word). A paragraph opens the reader there. |
| Shelves | Your own groups of books (a book can be on more than one shelf). **New Shelf**, rename, reorder, delete (the books stay in the library). In a shelf: **Add or Remove Books…**, reorder, swipe to remove, and **Read as Feed**: a Mix of only the shelf's books. In the Library, touch and hold a book for **Add to Shelf**. |
| Saved | **Bookmarks** (your saved places, as a feed) and **Highlights**, newest first. Under Bookmarks, colour chips (All, No highlight, Yellow, Red, Blue, each with its count) show only the bookmarks of one colour. A highlight shows the exact text; tap it to read around it. Touch and hold for Copy with citation, Share as image, Remove highlight. |
| Settings | Theme, accent colour, density, post and reader fonts, maximum words per post, focus mode, double-tap to bookmark. **Synced folder** (see Getting books in). **Back Up and Restore**: export a JSON file with every book's place, finish date, Mix settings, title, author, avatar photo and marks, and the shelves (not the books or settings); restore it after importing the books again (books are found by title, author and length; marks are not added twice). **Storage**: total space, split into library, search index, and covers and photos; every book with its estimated size, largest first (its share of the library and index follows its length); swipe to delete. |

On a post:

| Action | Result |
|---|---|
| Tap | **Read in context**: the book around the post, the post highlighted. Select text there for **Highlight** (or **Remove highlight**), **Look Up** (system dictionary), Copy or Translate. |
| Double tap | Bookmark, with no highlight, and open the colour bubble (it never removes a bookmark). Can be turned off in Settings. |
| Touch and hold | **Context peek**: two paragraphs before and after the post. Menu: Bookmark, Highlight, Copy with citation, Look up a word, Read in context, Continue from here. |
| **Bookmark** (top right) | On a post with no bookmark: bookmark it with no highlight, and a small bubble opens beside it. On a bookmarked post: open the bubble. The bubble has No highlight, Yellow, Red, Blue and Remove bookmark; it closes after 5 seconds, when you pick, or when you tap outside it (that tap does nothing else). A coloured bookmark puts that colour behind the post's text, in the feed, the peek and the reader. Touch and hold a post for the same choices under **Bookmark colour**. |
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

**Pictures in books.** An EPUB's pictures show under the post they follow, as on X: the post's
text, then the picture at full width with rounded corners (a picture taller than 4:5 is cut to
4:5 in the feed; the whole picture opens with a tap). Its height is known before it loads, so the
feed does not jump. Tap a picture to see it full screen on black, laid out as X's media viewer:
a back button and "⋯" (read in context, copy the text with its citation, copy the picture) at the
top, and under the picture the post's avatar, title and author and its first two lines, with
capsule buttons to read it in context, bookmark it and share the picture. X's reply field is left
out, because nothing in the app takes replies. "ALT" shows the picture's description. Pinch or
double-tap to zoom, swipe sideways between the pictures of one post, tap to show or hide the
buttons, and swipe up or down (or tap back) to go back. The reader shows the same pictures under
their paragraphs; there the viewer shows the description in place of the post. VoiceOver reads a
picture's description.

**Covers and avatars.** The avatar of a book is its cover: the EPUB cover image (the
`cover-image` item, else `<meta name="cover">`, else an image named "cover", else the picture on
the cover page: the guide's cover page or the first spine page, even when it is not linear, if it
holds an `<img>` or SVG `<image>` and at most 60 words) or the first page of a PDF. Text,
Markdown, HTML and RTF files have no cover and show the first letter. A book imported before a
cover could be found gets it with **Replace File…** (same file). **Edit Details** can set a photo instead, remove it, or show the first letter on the
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

The post layout follows X: avatar, bold title with the author in grey, the chapter,
and the text. The percent shows only on the first post of a chapter ("Book 1 · 0%"); later posts
show the chapter name only. To save space there is no action bar under the text: the bookmark sits beside
"⋯" at the top right, and read in context and share sit under the avatar. X's typeface
(Chirp) belongs to X and cannot be bundled, so posts use the system font (SF Pro) with x.com's
proportions: the title (bold), author (grey) and text share one size, lines are 1.25 times the
text size, and the chapter line is 13/15 of the text size. **Post text size** sets that size in
points: type a number or use − and +, in steps of 0.5 (10 to 40). The default, 16.5 pt, comes
from an iPhone screenshot of the X app: its post glyphs are 45 px tall at 3x where SF Pro at
15 pt is 41 px, and its lines are 62 px (20.6 pt) apart. (x.com on the web uses 15 px text on
20 px lines, which is smaller.) The iOS accessibility text sizes still enlarge posts.

**Fonts.** Ten reading fonts, all built into iOS, so nothing is downloaded: the X-style sans
(SF Pro), New York, and the book faces Apple Books offers (Georgia, Charter, Iowan Old Style,
Palatino, Athelas, Seravek) plus Baskerville and Hoefler Text. Studies find no single best font
for reading (individual reading speed differs by up to 35% between fonts), so the list gives
several well-tested serifs and two sans-serifs. Each font name in the list shows in its own
font. Rounded and Monospaced were removed; a stored choice of either falls back to the default.

**Themes and brightness.** Each theme has a brightness slider under the theme list (Settings >
Appearance), from its darkest shade to its lightest: for example Sepia goes from mid brown to
very light cream, and Night from pure black to dark grey. Each theme keeps its own value; Reset
returns to the default. Between the end points every colour is mixed, then any text, accent,
icon or highlight colour that would miss its contrast target (primary text 7:1, secondary text
and accents 4.5:1, icons 3:1, primary text on highlights 7:1) is moved just far enough to reach it.

| Setting | Choices (default first) |
|---|---|
| Theme | Night (pure black), Light, Sepia, Dark sepia, Sage, Dusk, System |
| Brightness | Per theme, 0–100% (not for System). Defaults: Night 0% (pure black), Light 100% (white), Sepia 80% (the earlier sepia), Dark sepia 40%, Sage 75%, Dusk 40%. |
| Accent colour | White (the default), then X's six: blue, yellow, pink, purple, orange, green. White is white on dark themes and X's near-black on light themes, where white could not be seen. "Show more" stays X's blue with every accent; with White, switches stay iOS green because a switch's knob is white. The six each have a bright shade for dark themes and a deep shade for light themes; at other brightness levels the shade moves only as far as needed, so accent text always reaches 4.5:1. |
| Density | Comfortable, Compact |
| Post font | Sans (X style), New York, Georgia, Charter, Iowan Old Style, Palatino, Athelas, Baskerville, Hoefler Text, Seravek |
| Post text size | 16.5 pt (10–40, steps of 0.5) |
| Reader font | New York, then the same list (Sans first in the list) |
| Maximum words per post | Auto, Off, 60, 80, 120, 200 |
| Focus mode | Off. On: posts show only their text. |
| Double-tap to bookmark | On |
| Scroll back through the book | Off. On: in One book mode, scrolling up past the first post loads earlier posts, a page at a time, back to the start of the book. Your place stays at the furthest post you read, so the feed still opens there and reading time is not counted again. |

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
fit, part two continues from there, and so on ("1/3", "2/3", "3/3" after the chapter). A
sentence longer than the limit is cut between words. In One book mode the parts form a
thread. Parts are offset ranges that tile the segment, so bookmarks, highlights, the reading
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

In One book mode, consecutive posts from the same chapter form a thread, with no divider
between them; a chapter change breaks the thread and shows a chapter row. One book mode
always gives the book in order: every post follows the one before it, with nothing skipped.
In Mix mode and Saved, tapping a post (or its book button) opens it in context.

**Reading list.** Put books in sets, like a playlist (Shelves › Reading List, or the feed
menu › Reading list). In Reading list mode the feed mixes the books of the first set that has
a book still to finish. The next set starts only when every book in the set is finished, and
its posts follow in the same timeline, so the list can go on from book to book. Scrolling
past a book's last post (in any mode) marks it finished; you can also mark books finished or
not finished in the Library or the reading list. Sets can be renamed, moved up or down,
changed or deleted; books can be reordered or taken out. A book is in one set only. The
reading list is in backups (`Shelves/ReadingList.swift`, `ReadingListView.swift`).

As on X, the tab bar is solid in the theme's background (black on Night, white on Light) with
a hairline on top, not iOS's grey blur.

As on X, the feed's navigation bar and the tab bar move away while you read down and come
back when you scroll up. They move point for point with the content, never faster or slower
than your finger; when a scroll stops part-way they ease to the nearer end on a critically
damped spring (it starts from rest, so the bars do not pop into motion when the content stops,
never overshoots, and settles in about 0.3 seconds), and they always show at the top of the
feed. During a flick the feed lays out posts as they come; the bars keep following the content
in those frames when it moves on smoothly, and ignore only sudden jumps (the feed correcting
its position) and scrolls the app makes itself. The bars move by their layers' sublayer
transform, which UIKit's own layout never sets, so a layout pass cannot knock them out of
place. When the app leaves the front (Home Screen, app switcher) the bars come back first, so
the app comes back with them shown: a tab bar sent to the background while moved away stops
selecting tabs on iOS 26. With VoiceOver on they stay in place (`ScrollChrome.swift`).

### Positions are offsets, not post indices

Each book has one normalized text: its paragraphs joined by a blank line. All offsets (reading
position, segment ranges, bookmarks and highlights) are UTF-16 offsets into that text. Both styles
are computed once at import and stored. Each style's segments tile the text exactly (each range
includes the separator after it), so any offset falls in exactly one segment of each style.
Switching style resumes at the segment that contains the saved offset.

A post's bookmark is stored as a text range with a colour. A post shows as bookmarked when its
range overlaps a bookmarked range (the newest one gives the colour), so marks carry over between
styles. Likes from earlier versions became bookmarks with no highlight (data model version 4).

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
  give no text. Chapter label: first `h1`–`h3` of the document, otherwise the EPUB 3 navigation
  document (or the EPUB 2 NCX). Every heading updates the label for the paragraphs after it;
  headings are never posts.
- **EPUB pictures** (`img` and SVG `image`): each picture goes after the paragraph it is in or
  follows, so its post shows the text and then the picture, and the next post goes on with the
  book. A Passages post ends at a picture. A picture before any text follows the first
  paragraph; a page with only a picture (under 40 words) adds its picture after the last
  paragraph before it. Left out: the cover (the cover image and a short cover page), inline
  `data:` images, files that are missing or that ImageIO cannot read (SVG files), pictures under
  40 pixels on a side (rules, ornaments), and any picture used three times or more (chapter
  ornaments). Pictures over 2048 pixels or 2 MB are scaled down (JPEG, or PNG with
  transparency); others keep their bytes. They are files in
  `Application Support/BookImages/<book id>/`, with `images.json` listing each picture's place
  (the end of the text before it), size and alternative text, so the database does not grow.
  Other formats have no pictures. A book imported before pictures were supported gets them with
  **Replace File…** (same file).
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

### String Catalogs

The app's text is in `Bookscroll/Resources/Localizable.xcstrings` and the widgets' text in
`BookscrollWidgets/Localizable.xcstrings` (English only). Counts use plural forms ("1 book",
"3 books"). Xcode adds new strings to the catalogs when you build in Xcode; CI runs
`xcodebuild -exportLocalizations` and prints the catalogs it makes (step "Export strings"), so
the files in git can be compared with them. To add a language, add it in the project's Info
tab and translate in the catalogs. Text the app builds in code (for example the restore
summary and the time-left lines) is English only.

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

`BookscrollTests` (XCTest, 277 tests):

| Area | File |
|---|---|
| Paragraph segmentation, passage chunker, tiling, style switch, marks | `SegmentationTests.swift` |
| HTML to text | `HTMLTextTests.swift` |
| Pictures: images after their block's text, placement after the paragraph before (dropped paragraphs, pictures before any text), Passages end at a picture, only the last part of a split post shows it, scaling and format, the cache's range lookup and decoding, an EPUB with a cover, a tiny picture, a missing file, a repeated ornament and a picture page, stored files under exactly one post in both styles, deletion | `BookImageTests.swift` |
| EPUB paths, OPF/NCX/nav parsing, end-to-end import into SwiftData, DRM and error cases | `EPUBTests.swift` |
| PDF paragraph detection on a generated PDF (headers, footers, hyphenation, page break, outline), scanned PDF, two-column order, headings by type size, drop caps, ligatures | `PDFTests.swift` |
| Feed: no repeats, never stalls, position advances only when shown, one-book mode, threads | `FeedEngineTests.swift` |
| Store key queries, position clamping, chunked deletion, duplicates, ordinals | `StoreTests.swift` |
| Files picker, staging, Open in Bookscroll, import queue | `ImportTests.swift` |
| Find Books (files in allowed folders and subfolders, iCloud files, library matches, remembered folders) and the feed's chosen books | `FindAndChooseTests.swift` |
| Text anchors (same text, moved text, lost text, nearest of several), Replace File (place, marks, details, shelves), backup and restore (no copies on a second restore, missing books), matching rules, file errors | `ReadingStateTests.swift` |
| Folder scan (subfolders, hidden files, iCloud placeholders), synced folder (each file once, kept across launches, stop, missing folder), quiet duplicates, folder import | `FolderSyncTests.swift` |
| Storage totals, write-ahead log, per-book shares that add up to the total, order, missing files | `StorageTests.swift` |
| Plain text (hard wraps, chapter headings, Gutenberg frame, encodings), Markdown, HTML, RTF by magic bytes, pasted text and its queue job | `TextFormatTests.swift` |
| Reader window and paging, bookmarks and their colours, likes becoming bookmarks, deletion, position saving, reading counted once | `AppFlowTests.swift` |
| Links (round trip, bad links; opening the last book, a book, a highlight, a missing one), widget content (book read last, day change, streak, file), the app's widget data after reading, Spotlight entries, Live Activity update rules, Focus filter shelf before your own choice, dropped files (copy, name, text is not a file), String Catalog plural forms, the default New Shelf name | `PlatformTests.swift` |
| Reading time only for short gaps, jumps ignored, pause, measured speed after 10 minutes, time left, streak, last 14 days, week, saving and loading, duration formats | `ReadingStatsTests.swift` |
| 50 books: key queries use an index, page and delete timings | `ScaleTests.swift` |
| Schema V1–V3, unversioned V1 store, V1 and V2 migrations with backfill, privacy manifest, save throttle | `FoundationTests.swift` |
| FTS5 search index: query escaping, add/search/remove, backup exclusion, backfill | `SearchIndexTests.swift` |
| Settings defaults and storage, the ten fonts (installed, fallback), themes and per-theme brightness, palette and accent contrast at every brightness (WCAG), citation | `AppearanceTests.swift` |
| Word-limit splitting, Auto limit, resume inside a split paragraph, chapter starts, Mix filters and weights, Jump to, peek | `SplitAndFilterTests.swift` |
| Highlights (exact range, merge, remove, across paragraphs, delete), Saved lists, Library search, share card styles and themes | `MarksAndSearchTests.swift` |
| Bars that hide on scroll: point-for-point movement, ends, jumps ignored, 20,000 random scrolls, the ease at 30/60/120 fps (gentle start, no overshoot, no turning back, no jumps, exact end), smooth flick frames with layout count and sudden ones do not | `ScrollChromeTests.swift` |
| Reading list: sets read in order, finished books and done sets skipped, scrolling past a book's last post finishes it, set order and one set per book, statuses, backups | `ReadingListTests.swift` |
| Library sort and filter, title and author filing, finished books and Mix, language detection, cover storage and cache, EPUB covers (declared or from the cover page) and PDF covers, file facts, edit details, avatar photos, shelves and the shelf feed | `LibraryTests.swift` |

`BookscrollUITests` (XCUITest, 28 tests) drive the app on a simulator with a seeded in-memory
library:

- Empty library, Files picker, Find Books (its folder picker, from the + menu and the empty Library), bookmark, bookmark colours in Saved, Saved tab, read in context, Continue in feed,
  post style and One book thread, swipe to delete.
- Settings: theme, accent and focus mode change the feed. White is the default accent, and the tab bar is solid black on Night.
- The navigation and tab bars hide while you read down the feed and come back when you
  scroll up. Four more tests drag, flick and turn back again and again (also at the largest
  text size, after the Home Screen and after another tab); the app records every frame and
  the tests check that the tab bar never moved faster than the content, never jumped while
  easing, eased to the nearer end, and came back exactly to its place. The bars come back shown
  after the Home Screen, and the tabs work after it, with and without bar hiding. Drags and
  flicks past the top come to rest with the bars shown.
- Make a reading list with two sets and read it in the feed.
- A book's picture shows under its post at full width and in its shape, opens full screen with
  a tap with the post, bookmark, share and "⋯" under and over it and no reply field, bookmarks and
  unbookmarks the post, hides and shows its buttons with a tap, closes with a swipe down, a swipe
  up, and the back button, and "Read" opens the post in the reader.
- A long paragraph splits into numbered parts; double tap bookmarks a post.
- Jump to a chapter; long press shows the peek and "Look up a word".
- Highlight a post, find it in Saved › Highlights and open it in the reader; search the
  Library text and open a result; the share card sheet in each style.
- Mark a book as finished, filter the Library to finished books, and rename a book in Edit
  Details (with audits of the filtered Library and the details sheet).
- Make a shelf, add a book, and read the shelf as a feed.
- Choose books: tick two books for a mixed feed, Select None and Select All, Save as Shelf.
- Paste text as a book; it shows in the Library and in the Feed mode menu (with an audit of
  the Paste Text sheet).
- `performAccessibilityAudit()` on the feed, library, Shelves, Saved, Settings, Storage, Synced folder, Back Up and Restore, and reader screens in the
  Light, Night and Sepia themes, and in Compact density with focus mode and the serif font.
- The largest accessibility text size.

## Verification status

CI on GitHub Actions runs every test on this configuration:

| Runner | Xcode | Simulator |
|---|---|---|
| `macos-15` | newest installed | iPhone, newest iOS (26.2) |

The iOS 17.5 job (`macos-14`, Xcode 15.4) was removed in November 2026: GitHub no longer
supports that runner. The deployment target stays iOS 17, but CI no longer tests on iOS 17.

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
chapter". Bookmark, each bookmark colour and Copy with citation are VoiceOver actions on each post. Text uses
Dynamic Type styles up to accessibility sizes. Bookmarked states use filled icons and
VoiceOver values ("Bookmarked, red highlight"), not only colour. Bookmarking gives haptic feedback. Every theme, at every
brightness from 0% to 100% in steps of 5%, and every accent pass a WCAG contrast test (4.5:1 for text), and the UI tests run Apple's accessibility
audit on each theme.

Audit policy: a finding fails the UI test when a second audit one second later reports it again (contrast samples taken while a row redraws vary between runs), except a short list of known false positives
(see `isKnownFalsePositive` in the UI tests). Findings that the audit reports without an
element cannot be located or judged; they are printed (`AUDIT: ignored`) with a screenshot of
the screen (`audit-<screen>`) but do not fail. On iOS 26 they come from the glass tab bar over
scrolled content (contrast); on iOS 17 from rows that VoiceOver reads as one element (Dynamic
Type, clipping). The largest-text-size test saves pictures of the feed, Library and Settings
for a visual check.
