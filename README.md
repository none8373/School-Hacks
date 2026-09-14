# School Hacks (DictateBar)

A little helper that lives in your Mac's menu bar. You talk to it (or paste text), it looks at your Canvas classes, and it gives you back words to type, notes to study, a grade before your teacher sees it, and a heads-up every morning about what's due.

Speech never leaves your Mac. The "AI" part uses a ChatGPT or Claude account you already have. Nothing to pay for.

---

## What it can do

| You do | It does |
|---|---|
| Press **⌥R**, talk, press **⌥R** again | Turns what you said into clean text and shows it in the menu bar. As you type it into Google Docs, the next letter lights up and follows you. Spelling mistake? Hit space and it moves to the next word. |
| Turn on **Caps Lock** and mash any keys | It types the correct text for you, one letter per key. |
| Press **⌥N** | Study notes for whatever test or assignment is next in your class, built from the actual unit pages and PDFs in Canvas. |
| Press **⌥G** while in a doc | Grades your document with the teacher's rubric from Canvas, tells you what to fix. |
| Press **⌥C** when class starts, again when it ends | Records the whole class, writes neat notes, and pulls out the homework and test dates the teacher mentioned. **⌥P** pastes the notes anywhere. |
| Nothing | Every morning it writes a 5-minute brief: what's due today and tomorrow, and the exact pages to review if there's a quiz. |
| Look at the bar | `📌` next assignment · `📝` what the teacher asked for in class · `⏭` your next class and minutes left. **⌥W** writes the suggested assignment for you. |
| Press **⌥O** or click the mic | Opens the app: history, class notes, schedule, morning briefs, colours, settings. |

---

## Install (about 10 minutes, one time)

**You need:** a Mac on macOS 14 or newer, and either the **Codex** app signed in with your ChatGPT account, or **Claude Code** signed in with your Claude account.

1. Open **Terminal** (press ⌘Space, type `Terminal`, Enter).
2. Paste this and press Enter. It installs Apple's free developer tools if you don't have them (a dialog may pop up — click Install, then wait):
   ```bash
   xcode-select --install
   ```
3. Paste this and press Enter. It installs Homebrew, a tool that installs other tools:
   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```
4. Paste this and press Enter. It downloads School Hacks, builds it, and opens it:
   ```bash
   git clone https://github.com/none8373/School-Hacks.git ~/School-Hacks && cd ~/School-Hacks && scripts/build_app.sh
   ```
5. A **Set up DictateBar** window appears. Go down the list — each row has a button:
   - **Speech recognition** → *Install with Homebrew* (1–3 min)
   - **Speech model** → *Download* (150 MB)
   - **AI** → pick Codex or Claude → *Test*. If it says not signed in: open the Codex app and log in (or run `claude auth login` in Terminal).
   - **Canvas** → paste your school's Canvas address and a token. To get a token: Canvas → your picture → **Settings** → scroll to *Approved Integrations* → **+ New Access Token** → Generate → copy. Then *Save & sync courses*.
   - **Microphone / Accessibility / Calendar** → *Allow*. Accessibility opens System Settings — flip the switch next to DictateBar.
6. Click the mic icon in the menu bar → **Settings** → choose your class → done.

Press **⌥R** and say something.

### Set up your schedule (5 minutes, optional but worth it)
Click the mic → **Schedule**:
1. Type your school's name and state → **Look up calendar & bell schedule**. It searches the web for your no-school days and period times.
2. Pick **Today is Day …** (your rotation day). You only do this once; it counts forward from there.
3. **Edit which class is in each period** and pick your classes from the grid. Or *Import my timetable PDF*.

Now the bar shows your next class, you get a ping 5 minutes before each one, and recording a class files itself under the right course automatically.

---

## Keys

| Key | Does |
|---|---|
| ⌥R | record / stop |
| ⌥V | use copied text as the request |
| ⌥N | notes for the next test/assignment |
| ⌥G | grade the document I'm in |
| ⌥C | record class / stop |
| ⌥P | paste class notes |
| ⌥W / ⌥J / ⌥D | write the suggestion / next / done |
| ⌥Space | pause following my typing |
| ⌥H | hide / show the bar |
| ⌥← ⌥→ ⌥↑ ⌥↓ | move by word / sentence |
| ⌥O | open the app |

⌥← / ⌥→ normally jump words in text editors. If you miss that, switch the modifier to Control+Option in Settings.

---

## Where your stuff goes
Everything is in `~/Documents/DictateBar` — your synced Canvas material, class notes, briefs, and a `history.log` of every AI run. Your Canvas token sits in `.env` there. Nothing is uploaded anywhere except to the AI you chose, and it only sees your library folder read-only.

## Make it yours
Click the mic → **Appearance**: colours, font, size, background. The AI's instructions are plain text in the `prompts/` folder — edit them if you want a different voice or format.

## Something's off?
- Click the mic → **History** to see what the AI got and what it answered.
- Mic menu → **Setup…** re-checks everything.
- Recording says "whisper failed"? Setup → Speech model → Download again.
- Bar disappeared? **⌥H**.

## Fair use
This can write and grade schoolwork. What you hand in is on you; your school's rules apply. It's best as a way to get unstuck, study from your own materials, and stay on top of what's due.

MIT licensed. Built with [whisper.cpp](https://github.com/ggerganov/whisper.cpp), [Codex CLI](https://github.com/openai/codex) / [Claude Code](https://claude.ai/code), Swift.
