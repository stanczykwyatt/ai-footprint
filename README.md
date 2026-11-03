<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="AI Footprint icon">
</p>

<h1 align="center">AI Footprint</h1>

<p align="center">
  <b>See what AI coding tools leave on your Mac.</b><br>
  A free, open-source menu bar app that shows the disk space, background processes, MCP servers and login items your AI tools add, and what each update changed.
</p>

<p align="center">
  <a href="https://github.com/stanczykwyatt/ai-footprint/releases/latest/download/AI-Footprint.zip"><b>Download for Mac</b></a>
  &nbsp;·&nbsp;
  <a href="https://stanczykwyatt.github.io/ai-footprint/">Website</a>
  &nbsp;·&nbsp;
  <a href="https://github.com/users/stanczykwyatt/projects/1">Roadmap</a>
  &nbsp;·&nbsp;
  <a href="https://github.com/stanczykwyatt/ai-footprint/discussions">Discussions</a>
</p>

<p align="center">
  <a href="https://github.com/stanczykwyatt/ai-footprint/actions/workflows/ci.yml"><img src="https://github.com/stanczykwyatt/ai-footprint/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/stanczykwyatt/ai-footprint/releases/latest"><img src="https://img.shields.io/github/v/release/stanczykwyatt/ai-footprint" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-111" alt="macOS 14 or later">
  <img src="https://img.shields.io/badge/network%20access-none-2ea44f" alt="No network access">
  <img src="https://img.shields.io/badge/file%20access-read--only-2ea44f" alt="Read-only file access">
  <img src="https://img.shields.io/badge/dependencies-0-2ea44f" alt="No dependencies">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/stanczykwyatt/ai-footprint" alt="MIT License"></a>
</p>

<p align="center">
  <img src="docs/demo.gif" width="720" alt="Demo: a made-up AI tool called Driftwood Code updates itself in Terminal. A dot appears on the AI Footprint menu bar icon, and its menu shows the update's receipt: 3.1.4 to 3.2.0, logs grew by 1.9 GB, and it added a login item that starts at login and restarts if it quits.">
</p>

---

AI coding tools are great, and they're also busy. They download models, keep every session's transcript, write logs, unpack virtual machines, and start MCP servers and background services. Most of it is reasonable. Some of it isn't: a log that grows by gigabytes, a server that keeps running after you quit, a login item added by an update you didn't watch install.

AI Footprint shows you all of it in one place. For each tool it lists what's on disk, what's running and what starts at login. When a tool updates, installs itself or adds a login item, you get a receipt with what changed, so nothing piles up out of sight.

It only looks. It never deletes, stops or changes anything: Show in Finder and Copy Stop Command leave every decision to you. It has no internet access, and it's open source, so you can check exactly what it reads.

If it helps you find something, [starring the repo](https://github.com/stanczykwyatt/ai-footprint/stargazers) helps other people find it.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/screenshot-dark.png">
  <img src="docs/screenshot-light.png" width="980" alt="The AI Footprint window: AI tools use 14 GB. An orphaned MCP server at the top, then each tool with its folders and sizes, its processes and what started them, and its login items.">
</picture>

## Features

- **Disk use per tool,** split into models, caches, logs, transcripts and installed versions, each with the biggest things inside and a Show in Finder button.
- **Background processes,** with what started each one: an app, a terminal, a login item, another tool, or nothing at all.
- **MCP servers,** named by package or script, with the tool that started them. **Orphaned servers** whose app has quit are flagged, since they do nothing but use memory.
- **Login items** each tool installed, with when they run: at login, again whenever they quit, or on a timer.
- **Update receipts.** When a tool updates, installs itself, or adds or removes a login item, AI Footprint writes down the version change, how much disk each folder gained or lost, and which login items came or went. Optional notifications, off until you turn them on.
- **Copy Stop Command** for any process or login item: the exact `kill`, `launchctl bootout` or quit command to paste into Terminal, shown before you copy it.
- **Read-only and offline.** No internet access, no permissions to grant, nothing deleted or changed. Free, with no account, subscription, tracking or dependencies.

### What it looks for

| Tool | On disk | Running |
|---|---|---|
| **Claude Code** | Session transcripts, file checkpoints, shell snapshots, debug logs, plugins, installed versions, and the cache that holds MCP logs | `claude` sessions, and the MCP servers they start |
| **Claude app** | Its virtual machine, built-in Claude Code, web and script caches, logs and MCP logs | The app and its helpers, and Claude Code sessions it starts |
| **Codex** | Session transcripts, archived sessions, logs and prompt history | `codex` sessions and servers, and the app if installed |
| **Ollama** | Models and logs | The app and `ollama serve` |
| **LM Studio** | Models, runtimes and server logs | The app and `lms` |
| **Hugging Face** | Downloaded models, datasets and the download cache | `hf` and `huggingface-cli` |
| **MCP servers** | | Any process run as an MCP server, from `npx`, `uvx`, Docker or a script, wherever it came from |

It finds login items for these tools in `~/Library/LaunchAgents`, `/Library/LaunchAgents` and `/Library/LaunchDaemons`. Want another tool covered? [Suggest it](https://github.com/stanczykwyatt/ai-footprint/discussions).

## How receipts work

Every 15 minutes, and whenever you choose Check Now, AI Footprint measures each tool's folders, reads its version and lists its login items. It compares that with the last check:

| What happened | Receipt |
|---|---|
| The version changed | **Updated**, from the old version to the new one |
| A tool appeared that wasn't there before | **Installed** |
| A tool's login items changed with no update | **Added** or **removed a login item** |
| A tool is gone | **Removed** |

Each receipt says how much disk the tool used before and after, which folders grew or shrank by a megabyte or more, and which login items were added or removed. Disk use changing on its own isn't worth a receipt, since tools write logs and caches all the time.

The comparison is with the previous check, not the moment before the update, so a receipt can include a little ordinary growth from in between. It says when that check was.

<img src="docs/screenshot-updates.png" width="980" alt="The Updates tab: Driftwood Code 3.1.4 to 3.2.0, disk 711 MB to 2.6 GB, logs grew by 1.9 GB, and it added a login item that starts at login and again if it quits. Below it, Ollama 0.12.2 to 0.12.3, plus 4 MB.">

## Install

1. [Download **AI-Footprint.zip**](https://github.com/stanczykwyatt/ai-footprint/releases/latest/download/AI-Footprint.zip) and unzip it.
2. Move **AI Footprint** to your Applications folder and open it.
3. The window opens once so you can see what it found. After that it lives in your menu bar and opens at login. Turn that off from its menu.

> **About the security warning:** The first time you open AI Footprint, macOS may say Apple couldn't verify that it's free of malware. It shows up because the app isn't notarized yet: Apple charges developers $99 a year for that, and this project hasn't paid the fee. The code is fully open source, so you can read every line or build the app yourself. To open it, go to **System Settings → Privacy & Security** and click **Open Anyway**.

> **Can't see the icon?** On a MacBook with a camera notch, menu bar icons that don't fit are hidden behind it. Hold ⌘ and drag the icon to the right, or quit a menu bar app you don't need.

### Build from source

You need macOS 14 or later and Swift 6, which comes with Xcode 16 or the Command Line Tools.

```bash
git clone https://github.com/stanczykwyatt/ai-footprint.git
cd ai-footprint
scripts/build-app.sh
open "build/AI Footprint.app"
```

## How to use it

| To | Do this |
|---|---|
| See how much each tool uses | Click the menu bar icon |
| See what's inside a tool's folders | Hover the tool, then a folder |
| See everything at once | Menu → Open AI Footprint… |
| Find a folder, executable or login item on disk | Hover it → Show in Finder |
| Stop a process or login item | Hover it → Copy Stop Command, then paste it into Terminal |
| Find orphaned MCP servers | Menu → MCP Servers, or Left Running |
| See what an update changed | Menu → Recent Updates |
| Get a notification for each update | Menu → Notify Me About Updates |
| Measure again right now | Menu → Check Now (⌘R) |
| Stop it opening at login | Menu → turn off Open at Login |

The icon gets a dot when there's a receipt you haven't seen, and goes back to normal once you've looked.

### Why Copy Stop Command, and not a Stop button?

The App Sandbox, which keeps AI Footprint from reaching anything it doesn't need, also keeps it from stopping other apps' processes. Rather than ask for more access, it gives you the exact command and shows it first. That's often the better fix anyway: a process a login item keeps alive comes straight back after a `kill`, so for those the command is `launchctl bootout`, which stops the login item too until you next log in.

## Privacy and security

AI Footprint is built so it *can't* misuse your data, not just so it promises not to.

- **Read-only.** It can read only the folders listed in [What it looks for](#what-it-looks-for) and your login items, and the macOS App Sandbox blocks it from writing to any of them. Its own history goes in its sandbox container.
- **Sizes and dates, not contents.** It measures files without opening them. The only files it opens are login items' property lists and apps' `Info.plist`, for their labels and versions.
- **Keys and settings out of reach.** Each tool's folders are listed one by one, so files that hold sign-in tokens, API keys and settings stay outside what it may open, like `~/.codex/auth.json`, `~/.cache/huggingface/token` and Ollama's private key. A test checks the app's entitlements against that list. Some folders it can read, like transcripts and file checkpoints, can still contain secrets you pasted or edited, which is why it measures them without ever opening them.
- **Command lines stay private.** It reads processes' command lines to recognize tools and MCP servers, keeps only their names, and never saves or shows the arguments, which can hold API keys. The environment variables that come with a command line are dropped unread.
- **No internet access.** The app has no network entitlement, so it can't send anything anywhere. CI checks every build for this.
- **Changes nothing.** It can't delete files or stop processes. Every change is yours to make. The one thing it adds is itself as a login item on first launch, which you can turn off from its menu.
- **No dependencies.** Every line that runs is in this repository.

Check the app's permissions yourself with `codesign -d --entitlements - "/Applications/AI Footprint.app"`. The full details are in [SECURITY.md](SECURITY.md).

## FAQ

**How much disk space do AI coding tools use on a Mac?**
It varies a lot: a few hundred megabytes for a coding assistant's transcripts and logs, several gigabytes for a virtual machine or a bundled runtime, and tens of gigabytes for local models. AI Footprint adds it up per tool and per folder, so you can see where it goes.

**Is it a cleaner?**
No. It never deletes anything. It shows you what's there and where, and Show in Finder takes you to it. Deleting is up to you, ideally with the tool's own settings, so the tool doesn't break or download it all again.

**What is an orphaned MCP server?**
An MCP server is a small program an AI tool starts to give it extra abilities, like reading files or searching the web. It normally quits with the tool. If the tool crashes or is closed the wrong way, the server can keep running with nothing connected to it. AI Footprint flags those, and gives you the command to stop them.

**Why does it say a process was "left running on its own"?**
Nothing that's still open started it: no app, terminal or login item. Some tools leave a server running on purpose so it starts faster next time. AI Footprint doesn't judge, it just tells you so you can decide.

**Does it slow down my Mac?**
No. A check takes about a second every 15 minutes, at low priority. Opening the menu only looks at the list of running processes, which takes about 10 milliseconds.

**Does it track my AI usage or costs?**
No. It doesn't read your prompts, transcripts or accounts, and it has no internet access. It only sees how big the files are.

**Does it work on Intel Macs?**
Yes. The download runs on Apple silicon and Intel Macs with macOS 14 Sonoma or later.

## More free tools

**Mac apps**

- **[Show Desktop](https://github.com/stanczykwyatt/show-desktop):** hide every window with one click or ⌃⇧D, then bring them all back exactly as they were.
- **[Copy 2FA](https://github.com/stanczykwyatt/copy-2fa):** copy 2FA codes from Mail, Messages or a built-in authenticator with one keyboard shortcut.
- **[Who Stole My Focus](https://github.com/stanczykwyatt/who-stole-my-focus):** find out which app keeps jumping in front of your work.
- **[Memo Export](https://github.com/stanczykwyatt/memo-export):** export your Voice Memos transcripts as Markdown, with the audio.
- **[Podcast Export](https://github.com/stanczykwyatt/podcast-export):** export your Apple Podcasts shows as OPML, and your listening history.
- **[Reading List Export](https://github.com/stanczykwyatt/reading-list-export):** export your Safari Reading List as Markdown, bookmarks and CSV.
- **[Unblock Eject](https://github.com/stanczykwyatt/unblock-eject):** see what's keeping your disk from ejecting, and quit it politely.
- **[Next Departures](https://github.com/stanczykwyatt/next-departures):** your stop's next bus and train, live, in the menu bar.
- **[Right Folder](https://github.com/stanczykwyatt/right-folder):** Open and Save dialogs, in the right folder. A free Default Folder X alternative.
- **[Tonecap](https://github.com/stanczykwyatt/tonecap):** design your keyboard's sound, with no recordings, and hear it as you type.
- **[SciLook](https://github.com/stanczykwyatt/scilook):** Quick Look for NWB, HDF5, MATLAB and NumPy files on your Mac.

**Windows**

- **[Who Stole My Focus for Windows](https://github.com/stanczykwyatt/who-stole-my-focus-windows):** the focus-thief finder as a Windows tray app (preview).

**For coding agents**

- **[mulligan](https://github.com/stanczykwyatt/mulligan):** undo for coding agents: snapshots at every prompt and tool call, for macOS and Linux.
- **[symbolhop](https://github.com/stanczykwyatt/symbolhop):** go-to-definition and find-references for coding agents, from your language servers.

**For neuroscience data**

- **[brainhound](https://github.com/stanczykwyatt/brainhound):** search and read public neuroscience data from your coding agent or terminal.
- **[dropslice](https://stanczykwyatt.github.io/dropslice/):** open NWB, HDF5, MATLAB, NumPy and Zarr files in your browser.

**On the web**

- **[Openfume](https://stanczykwyatt.github.io/openfume/):** an open fragrance database you can search by notes and accords.

Next Departures fetches only the transit feeds you pick, brainhound reads only public neuroscience archives, and dropslice and Openfume are web pages that never upload your files. The rest have no internet access.

## Contributing

Contributions are welcome, especially new tools to look for and processes it got wrong. See [CONTRIBUTING.md](CONTRIBUTING.md), and the [roadmap](https://github.com/users/stanczykwyatt/projects/1) for what's planned. Ideas go in [Discussions](https://github.com/stanczykwyatt/ai-footprint/discussions).

## License

AI Footprint is released under the [MIT License](LICENSE) and is provided as is, without warranty of any kind.

AI Footprint is an independent project. It isn't affiliated with, endorsed by or sponsored by Apple Inc., Anthropic, OpenAI, Ollama, Element Labs, Hugging Face or any other company whose tools it looks for. Apple, Mac and macOS are trademarks of Apple Inc., registered in the U.S. and other countries. Claude and Claude Code are trademarks of Anthropic, PBC. Codex is a trademark of OpenAI. Ollama, LM Studio and Hugging Face are trademarks of their respective owners. Other product names belong to their owners and are used only to say which tools the app looks for. Driftwood Code, its login item and the orphaned `notes-mcp` server in the screenshots and demo are made up; the other tools there show typical sizes, not anyone's real Mac.
