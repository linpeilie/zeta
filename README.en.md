<div align="center">

<img src="assets/branding/zeta_logo.svg" alt="Zeta" width="96" />

# Zeta

Use AI coding assistants in one desktop window, with conversations, file changes and requests waiting for your response.

macOS · Windows · Linux

[![CI](https://github.com/linpeilie/zeta/actions/workflows/ci.yml/badge.svg?branch=dev)](https://github.com/linpeilie/zeta/actions/workflows/ci.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

English ｜ [中文](README.md)

</div>

## What you can do

Zeta connects the Codex, Grok or Claude Code assistant installed on your computer. Choose projects and past conversations on the left, talk to the assistant in the middle, and browse project files on the right.

- Read replies, operation records and file changes reported by the assistant.
- Respond to permission requests and questions, or ask for a plan first.
- Cancel a running task. Cancellation does not undo changes already made.
- Return from another project or the settings page with your draft and reading position preserved.
- Receive desktop notifications when a task ends or needs a response.
- View usage and plan limits supplied by each assistant.

Zeta does not include an AI model or a code editor. Install and sign in to at least one supported assistant first. Available controls differ by assistant; see the [feature comparison](docs/en/guide/agents.md).

## Get started

1. Set up Codex, Grok or Claude Code and check that it works on its own.
2. Download the package for your system from [Releases](https://github.com/linpeilie/zeta/releases) and follow that release's installation notes.
3. Open Zeta, choose “Open project folder”, and enter a task.

If no assistant is found, open “Settings → Agents” to review detection results. See [Installation and First Run](docs/en/guide/getting-started.md) for details.

## Permissions and data

Assistants can read or change files, run commands and access the network within the permissions you choose. Zeta displays confirmation requests sent by the assistant. If you allow some operations automatically, they may run without asking each time. Accepting a plan does not grant additional permissions.

Zeta saves settings and usage summaries locally, with no cloud conversation service or telemetry of its own. **The connected assistant may still send messages, images and file contents to its model service.** Check the data settings for your assistant and account before using private material.

Each assistant stores its own configuration and history. Zeta reads relevant data to connect, display history and show usage. Saving configuration changes writes to the assistant's configuration file. With Claude Code, Zeta may also update its existing sign-in information to keep it signed in. See [Data and Privacy](docs/en/guide/data-and-privacy.md).

## Documentation and feedback

- [User guide](docs/en/README.md): installation, conversations, approvals, settings and troubleshooting
- [Changelog](CHANGELOG.md) (Chinese)
- [Report an issue](https://github.com/linpeilie/zeta/issues/new/choose)
- [Contributing](CONTRIBUTING.en.md) and [developer documentation](docs/README.md)
- [Security policy](SECURITY.md) and [code of conduct](CODE_OF_CONDUCT.md)

Licensed under [GPL-3.0](LICENSE).
