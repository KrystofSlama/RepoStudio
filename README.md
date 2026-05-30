# RepoDraft

RepoDraft is a macOS SwiftUI app for working with local Git repositories and
Markdown files in one place. It is designed for quick drafting and review
workflows: inspect repository status, open files, edit Markdown, and preview
changes side by side.

## Features

- Open and switch between local repositories.
- Browse tracked and untracked repository files.
- View Git changes grouped by status (added, modified, deleted, etc.).
- Filter by search text and file type.
- Edit Markdown with a formatting toolbar.
- Live Markdown preview with Editor / Preview / Split modes.
- Built-in diff rendering for changed text files.

<p align="center">
  <img src="Screenshots/Screenshot%202026-05-30%20at%202.43.58.png" width="32%" alt="RepoDraft screenshot 1" />
  <img src="Screenshots/Screenshot%202026-05-30%20at%202.44.10.png" width="32%" alt="RepoDraft screenshot 2" />
  <img src="Screenshots/Screenshot%202026-05-30%20at%202.45.12.png" width="32%" alt="RepoDraft screenshot 3" />
</p>

## Requirements

- macOS
- Xcode (recent version recommended)
- Git (or Xcode Command Line Tools)

## Getting Started

1. Clone this repository.
2. Open `macOS/RepoDraft/RepoDraft.xcodeproj` in Xcode.
3. Select the `RepoDraft` scheme.
4. Run the app.
5. In the app, choose a local Git repository to begin.

## Project Structure

- `macOS/RepoDraft/RepoDraft`: App source code.
- `macOS/RepoDraft/RepoDraftTests`: Unit test target.
- `macOS/RepoDraft/RepoDraftUITests`: UI test target.
- `icon`: Icon source assets.

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md)
before opening a pull request.

## License

This project uses a custom license:
[RepoDraft Community License v1.0](LICENSE)
