# DictateBar — spec

A macOS menu bar tool. You speak a request, it uses your school materials
(Canvas + Google Drive exports) to produce text, and that text appears as a
one-line guide in the menu bar that follows along as you type in Google Docs,
Chrome, or anywhere else.

Two parts, one shared document:

```
[Hotkey] → record audio → whisper.cpp (local) → transcript
        → Claude (your subscription, via `claude -p`) + context library
        → output/current.md
        → menu bar line shows it and tracks your typing
```

---

> Original design notes; the README describes the current behaviour. The app has grown since (class recording, notes, grading, suggestions, calendar, setup window) — see the README.

## 1. What you see

### Menu bar item
- **Icon**: mic glyph. Grey = idle, red = recording, spinning = thinking.
- **Text line** next to the icon: ~40 characters of the current output.
  - Already-typed characters are dimmed.
  - The next character to type is highlighted.
  - Scrolls like a ticker: typed text falls off the left.
- **Hidden state**: only the icon shows, no text. Recording still works.

### Dropdown (click the icon)
- ▶ Play / ⏸ Pause
- 👁 Hide / Show line
- 🎙 Record / Stop
- 🔄 Sync Canvas now (shows "last synced 2h ago")
- 📄 Open current output (opens the .md in your editor)
- 📁 Open library folder
- ⚙ Settings…
- Quit

### Global hotkeys (work in any app)
| Keys | Action |
|---|---|
| Option + R | Start / stop recording |
| Option + Space | Play / pause |
| Option + H | Hide / show line |
| Option + ← / → | Scroll back / forward one word |
| Option + ↑ / ↓ | Previous / next sentence |

⚠️ Option+←/→ conflicts with "jump by word" in Docs and most Mac apps.
Recommended alternative: Ctrl+Option+arrows. Changeable in Settings.

---

## 2. Play / Pause / typing behavior

- **Play**: the tool watches keystrokes system-wide (needs macOS
  *Accessibility* permission, granted once in System Settings → Privacy).
  - If you type the highlighted character, the marker advances.
  - If you type anything else, nothing happens (the text is a loose guide,
    not a test — you may skip parts or reword).
  - Backspace moves the marker back one.
  - Whitespace and punctuation are matched loosely (any space/newline = space;
    smart quotes = straight quotes).
- **Pause**: marker freezes. Type freely; use arrows to move the marker by hand.
- Arrow hotkeys work in both states.
- Keystrokes are only *observed*, never stored or sent anywhere.

---

## 3. Recording → transcript → cleaned output

1. **Option+R**: starts recording from the default mic (16 kHz mono WAV) into
   `recordings/YYYY-MM-DD_HH-MM-SS.wav`. Icon turns red.
2. **Option+R again**: stops. Icon spins.
3. **Transcribe** with whisper.cpp (`whisper-cli`, model `base.en` by default,
   `small.en` optional for better accuracy). Runs fully on your Mac.
4. **Clean + write** with Claude, run as a script through your subscription:
   `claude -p` with the library folder as its working directory, read-only
   file tools, and a fixed instruction file (`prompts/clean.md`) that tells it to:
   - Remove filler words (um, uh, like, you know).
   - Apply self-corrections ("no wait, scratch that…") — keep only the final version.
   - Drop side chatter / anything not addressed to the tool.
   - Follow spoken instructions ("make it formal", "two paragraphs") but don't
     include them in the output.
   - Look up relevant material in the library (assignments, linked textbook PDF,
     your Drive exports) when the request refers to a class, assignment, or reading.
   - Output **only** the final text to type — no preamble, no "Here's your…".
5. Result is written to `output/current.md`; the previous one is saved to
   `output/history/<timestamp>.md`.
6. Menu bar line reloads automatically, marker resets to the start, state = Play.

Failure cases show a macOS notification with the reason (no mic permission,
whisper missing, `claude` not logged in, etc.) and the previous output stays.

---

## 4. Context library

Folder: `~/Documents/DictateBar/library/`

```
library/
  canvas/
    <Course Name>/
      course.md          # name, teacher, syllabus text
      assignments.md     # every assignment: title, due date, description, rubric
      modules.md         # module list; pages/ holds module page text
      files/             # PDFs/docs linked from assignments or modules,
                         # including the textbook PDF if one is linked
      text/              # extracted text of each PDF (so Claude can grep it)
  drive/                 # you drop Google Drive exports here manually
  INDEX.md               # auto-generated table of contents Claude reads first
```

### Canvas sync (`sync_canvas.py`)
- Reads `CANVAS_URL` and `CANVAS_TOKEN` from `.env` (never committed).
- Pulls, for each active course: name, syllabus, all assignments
  (description, due date, rubric), and every file linked from an assignment
  or module page — this is how the textbook PDF gets picked up.
- Extracts PDF text to `text/<name>.txt` so it's searchable.
- Skips files already downloaded (by Canvas file id + updated timestamp).
- Runs when you click **Sync now** and automatically every 4 hours while the
  app is open.
- Library size target: under ~50 files, so no search index is needed —
  Claude reads `INDEX.md` then opens what it needs.

---

## 5. Settings (a small `config.json`, editable from the dropdown)
- Hotkey bindings
- Whisper model (`base.en` / `small.en`)
- Claude model (default: Sonnet 5 for speed; Opus 5 optional)
- Visible characters in the menu bar line (default 40)
- Sync interval (default 4h)
- Library folder path

---

## 6. Tech choices (and why)

| Piece | Choice | Why |
|---|---|---|
| Menu bar app, hotkeys, keystroke watching, mic | **Swift + SwiftUI** (native Mac app) | Only native code can sit in the menu bar and observe global keystrokes reliably. Xcode is free. |
| Transcription | **whisper.cpp** via Homebrew (`brew install whisper-cpp`) | Free, offline, good accuracy; you chose it. |
| AI cleanup + library lookup | **Claude Code CLI** (`claude -p`) | Uses your Claude subscription — no API key, no per-use bill. ChatGPT subscriptions can't be scripted, so not supported. |
| Canvas sync + PDF text extraction | **Python script** (`requests`, `pypdf`) | Canvas API + PDF parsing is a few dozen lines in Python; much more in Swift. |
| Storage | Plain files (`.md`, `.json`, `.wav`) | Easy to inspect and fix by hand. |

Secrets: only `.env` (`CANVAS_URL`, `CANVAS_TOKEN`). Listed in `.gitignore`.

Data folder: `~/Documents/DictateBar/`

---

## 7. Permissions you'll be asked for (once)
1. **Microphone** — to record.
2. **Accessibility** — to see keystrokes for the typing marker and global hotkeys.
3. **Notifications** — for error messages.

---

## 8. Build order
1. Menu bar app shell: icon, dropdown, hidden state, loads `output/current.md`.
2. Text line with ticker + arrow-key scrolling (no keystroke watching yet).
3. Global hotkeys.
4. Recording → whisper → transcript file.
5. Claude cleanup step → `current.md` → auto-reload.
6. Keystroke watching + Play/Pause marker.
7. Canvas sync script + Sync button + INDEX.md.
8. Settings UI.

Each step is testable on its own before moving to the next.

---

## 9. Not included (yet)
- ChatGPT support (no scriptable subscription access).
- A floating window view (you chose the one-line menu bar version).
- Google Drive live API sync (you drop exports into `library/drive/` by hand).
- Multi-line preview of the full output in the dropdown — easy to add later.
