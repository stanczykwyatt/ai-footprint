# Contributing

Thanks for helping out! Bug reports, ideas and pull requests are all welcome.

## Suggesting a tool

The most useful contribution is another AI tool to look for, or a folder an existing tool keeps that AI Footprint misses. [Open a feature request](https://github.com/stanczykwyatt/ai-footprint/issues/new?template=feature.yml) with:

- where the tool keeps its files, and what each folder holds,
- which of those hold sign-in tokens, keys or settings, so they can be left out,
- what its processes and login items are called.

## Reporting a process it got wrong

If a process is missing, belongs to the wrong tool, or is called orphaned when it isn't, open a [bug report](https://github.com/stanczykwyatt/ai-footprint/issues/new?template=bug.yml) with the process's name, how you started it, and the tool it belongs to. Leave out its arguments if they hold anything private.

## Getting started

You need macOS 14 or later and Swift 6 (Xcode 16 or the Command Line Tools).

```bash
swift test                # run the tests
scripts/build-app.sh      # build "AI Footprint.app" into ./build
open "build/AI Footprint.app"
```

What each tool leaves behind, how processes and MCP servers are recognized, receipts and all the wording live in `Sources/FootprintCore`, with tests in `Tests/FootprintCoreTests`. Adding a tool means adding it to `Catalog.swift` and its folders to `Resources/AIFootprint.entitlements`; a test checks the two match. Changes to how processes are sorted belong in `Processes.swift`, with a test in `ProcessTests.swift` that describes the situation.

The menu bar app, the system reader, the menu and the window are in `Sources/AIFootprint`, tested in `Tests/AIFootprintTests` with a made-up Mac and windows that are never shown. The only tests that touch the real system start a `sleep` of their own and look for it. No test reads your tools' folders, stops a process, or puts anything on screen.

To redraw the art: `swift scripts/make-icon.swift`, `swift scripts/make-art.swift`, and `SCREENSHOT_DIR=docs swift test --filter Window` for the screenshots.

## Ground rules

- **No network access, ever.** Pull requests that add a network entitlement or third-party analytics won't be merged.
- **Read-only.** AI Footprint never deletes, moves, stops or changes anything. Features that act should hand the action to the user, like Show in Finder and Copy Stop Command do.
- **Least access.** New folders are listed one by one, read-only. Never add a folder that holds tokens, keys or settings, and never a whole tool folder when part of it will do.
- **Sizes, not contents.** Don't open files in the tools' folders. Don't save or show command-line arguments, and never read a process's environment.
- **No new dependencies** without a very good reason. The app has none today, which keeps it easy to audit.
- **No real tool shown misbehaving** in screenshots, art or tests. Use made-up tools like Driftwood Code for that.
- Run `swift test` before opening a pull request, and add tests for changes to `FootprintCore`.
- Keep commits small, with a short message saying what changed and why.

## Security issues

Please don't open public issues for vulnerabilities. See [SECURITY.md](SECURITY.md).
