# Security

AI Footprint looks at what AI tools keep on your Mac, so it's built to do that with as little access as possible, and to change nothing.

## Reporting a vulnerability

Please report security problems privately through **Security → Report a vulnerability** on this repository, not in a public issue. You'll get a reply within a few days.

## What AI Footprint can access

| | |
|---|---|
| **The tools' folders, read-only** | Each folder in `Resources/AIFootprint.entitlements`, listed one by one, like `~/.ollama/models` and `~/.codex/log`. It measures the files in them by size and date and never opens them. macOS blocks it from writing to any of them. |
| **Login items** | `~/Library/LaunchAgents` read-only, plus `/Library/LaunchAgents` and `/Library/LaunchDaemons`, which any app can read. It opens their property lists for each item's label, what it runs and when. |
| **App versions and icons** | The `Info.plist` of each tool's app in `/Applications`, which any app can read, and the app's icon, which macOS looks up for it. |
| **Your processes** | Their names, where they run from, their memory, when they started and what started them, which macOS tells any app about your own processes. It reads command lines to recognize tools and MCP servers, keeps only their names, and never saves or shows the arguments. The environment variables macOS hands over with a command line are dropped unread. |
| **Its own history and settings** | The last check and up to 200 receipts, stored in the app's sandbox container. |
| **Notifications** | Optional, off until you turn them on, and macOS asks you first. |

## What it can't access

- **The internet.** The app runs in the App Sandbox without a network entitlement, so macOS blocks every connection. CI checks every build for this, and that the app never opens a URL or starts another program, which could send something out another way.
- **Tokens, keys and settings.** The tools' folders are listed one by one so that files like `~/.codex/auth.json`, `~/.cache/huggingface/token`, `~/.ollama/id_ed25519`, `~/.claude.json` and the Claude app's cookies and local storage are outside what it may open. A test fails if a whole tool folder is ever added.
- **The rest of your files.** Documents, downloads, desktop, code and everything else are blocked by the sandbox.
- **Other apps.** It has no Apple Events entitlement and no Accessibility permission, so it can't read or control other apps.
- **Stopping or deleting anything.** The sandbox doesn't let it signal other processes or quit other apps, and its file access is read-only. Copy Stop Command puts a command on the clipboard for you to read and run yourself.

macOS can grant read access to a folder, but not "sizes only". So the app *could* read the files in the folders it lists. It doesn't: apart from its own history file and asking macOS for app icons, the only files it opens are property lists, all in one file, `Sources/AIFootprint/SystemReader.swift`. CI fails if any other file in the app reads one. Some of the folders it can read, like transcripts and file checkpoints, can contain secrets you pasted or edited, so this matters, and it's why they're only ever measured.

Check it yourself on any copy of the app:

```bash
codesign -d --entitlements - "/Applications/AI Footprint.app"
```

The only entitlements are `com.apple.security.app-sandbox` and the read-only folder list.

## How it handles things

- Login item labels and bundle IDs come from other apps' files, so they're treated as untrusted text. Copy Stop Command quotes labels for the shell, and won't put a bundle ID with anything but letters, digits, dots and hyphens into a quit command.
- Property lists over a megabyte, and anything that isn't a regular file, are skipped.
- A server's name is the word that made it one, like `serve`, and an MCP server's name never comes from the value after a flag like `--api-key`, so an argument can't end up on screen.
- Control characters in a label are written out as `\xHH` in Copy Stop Command, so nothing can hide in the command you paste.
- Folders are measured without following symbolic links, so a link can't send it outside the folders it's allowed to read.
- A history file that can't be read, whether damaged or written by a newer version, is moved aside rather than overwritten.
- It has no dependencies. Every line that runs is in this repository.
