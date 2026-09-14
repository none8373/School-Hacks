# School Hacks

**A menu bar study assistant for Mac students.** Say what you need — "write my reply to the discussion post", "notes for the unit 3 test", "grade this" — and DictateBar turns it into text that lives in your menu bar and follows along as you type it into Google Docs, Canvas, or anywhere else.

It reads your own Canvas courses (assignments, rubrics, modules, readings, the textbook PDF), can record and organize a whole class, keeps a to-do suggestion in the bar, and puts everything on an iCloud calendar. Speech recognition runs on your Mac; the AI runs on a ChatGPT or Claude account you already have — no API keys, no subscriptions to anything new.

## What it does

| | |
|---|---|
| **Type-along line** | The text to type sits in the menu bar. The next letter is highlighted; typed letters dim. Space always jumps to the next word, so typos never trap you. **Caps Lock** turns on auto-type: every key you press becomes the next correct character. |
| **Record** `⌥R` | Speak a request. Filler words, "no wait, scratch that", and side chatter are removed; spoken instructions ("make it formal") are followed, not typed. |
| **Clipboard prompt** `⌥V` | Same thing from copied text. |
| **Notes** `⌥N` | Finds the selected class's current test or assignment on Canvas, works out which units it covers, and builds study notes from those modules' pages and files. |
| **Grade** `⌥G` | Copies the document you're in and grades it against the assignment's Canvas rubric at your grade level: score per criterion, three fixes, what's missing. |
| **Record class** `⌥C` | Records the whole period, transcribes it, writes organized notes, pulls out homework and test dates the teacher mentioned, and saves what was said about each Canvas assignment. `⌥P` pastes the notes anywhere. |
| **Suggestion** | The next thing worth doing (from class + Canvas work due soon) sits at the right of the line. `⌥W` writes it, `⌥J` next, `⌥D` done. |
| **Morning brief** | Every morning (time of your choice) it reads the latest class notes, to-dos and Canvas due dates, finds things like "reading quiz tomorrow on pages 40–80", pulls those pages from the synced PDF text, and writes a five-minute review. Its own page in the app; past briefs kept. |
| **Calendar** | A "DictateBar" iCloud calendar gets due dates, class sessions with notes, and to-dos. |
| **Language classes** | Essays and prompts come out in the target language; notes give vocabulary with English meanings. |
| **Usage meter** | Tokens and runs per AI, today and this week, in the menu. |
| **App window** `⌥O` | Home (live text you can edit, one-click actions, next suggestion), History of every run, Class notes, Suggestions, **Appearance** (text / typed / highlight / suggestion colors, font, size, plain / blurred / solid background, opacity, corner radius, width) and Settings. |

Everything the AI produces is logged to `~/Documents/DictateBar/output/history.log`.

## Install

Requirements: macOS 14+, [Xcode Command Line Tools](https://developer.apple.com/xcode/resources/) (`xcode-select --install`), [Homebrew](https://brew.sh).

```bash
git clone https://github.com/none8373/DictateBar.git
cd DictateBar
scripts/build_app.sh
```

That builds the app into `~/Applications/DictateBar.app` and opens it. A **Setup** window walks you through the rest, with a button for each step:

1. **whisper.cpp** — installed with Homebrew (speech recognition, on-device).
2. **Speech model** — a ~150 MB download.
3. **AI** — pick Codex (uses the ChatGPT account you're signed into in the Codex app) or Claude (`claude auth login` once). Click *Test*.
4. **Canvas** (optional) — paste your school's Canvas address and an access token (Canvas → Account → Settings → *New Access Token*). Courses sync in the background and every few hours after that.
5. **Permissions** — Microphone, Accessibility (for hotkeys and following your typing), Calendar (optional).

Then choose your class in **Settings…** and press `⌥R`.

## Hotkeys

`⌥R` record · `⌥C` record class · `⌥P` paste class notes · `⌥V` clipboard prompt · `⌥N` notes · `⌥G` grade · `⌥W` write suggestion · `⌥J` / `⌥D` next / done · `⌥Space` play / pause · `⌥H` hide · `⌥←` `⌥→` word · `⌥↑` `⌥↓` sentence

`⌥←/→` normally jumps by word in text editors; switch the modifier to Control+Option in Settings if that bothers you.

## Where things live

```
~/Documents/DictateBar/          your data (never leaves your Mac except to the AI you chose)
  library/canvas/<course>/        synced assignments, modules, pages, files, extracted text
  library/classes/<course>/       class transcripts and notes
  library/drive/                  drop Google Drive exports here
  output/current.md               what the menu bar shows — edit it by hand any time
  output/history.log              every AI run
  .env                            your Canvas token (chmod 600)
~/Library/Application Support/DictateBar/models/   whisper model
```

Prompts the AI follows are in [`prompts/`](prompts) — edit them to change the voice, format, or rules.

## How it works

Swift menu bar app (no Xcode project — `swift build`) · [whisper.cpp](https://github.com/ggerganov/whisper.cpp) for transcription · [Codex CLI](https://github.com/openai/codex) or [Claude Code](https://claude.ai/code) run non-interactively with read-only access to your library folder · a small Python script for the Canvas API · EventKit for the calendar. The menu bar line is a transparent panel floating over the bar; it measures the free space with Accessibility and never pushes other icons out.

See [SPEC.md](SPEC.md) for the design.

## A note on use

DictateBar can write and grade schoolwork. What you hand in is your call, and your school's rules apply. It's most useful as a way to get unstuck, study from your own materials, and keep track of what's due.

## License

MIT
