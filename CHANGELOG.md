# Changelog

## 0.1.0 (2026-11-01)

First release.

- **Disk use per AI tool:** Claude Code, the Claude app, Codex, Ollama, LM Studio and Hugging Face, split into models, caches, logs, transcripts and installed versions, with the biggest things in each folder.
- **Processes for each tool,** with their memory, how long they've run, and what keeps them running: an app, a terminal, a login item, another tool, or nothing.
- **MCP servers,** recognized from `npx`, `uvx`, Docker and scripts, with the tool that started them. Orphaned servers whose app has quit are flagged.
- **Login items** each tool installed, and when they run.
- **Update receipts:** when a tool updates, installs itself, or adds or removes a login item, a receipt lists the version change, the disk each folder gained or lost, and the login items that came or went.
- **Copy Stop Command** for any process or login item, shown before it's copied. AI Footprint itself never stops or deletes anything.
- **Show in Finder** for every folder, executable and login item.
- **Optional notifications** for each receipt, off until you turn them on.
- **A window** with every tool at once and the full list of receipts.
- **Open at login**, on by default and easy to turn off.
- Runs in the App Sandbox with no network access and read-only access to the tools' folders, listed one by one so their tokens, keys and settings stay out of reach.
