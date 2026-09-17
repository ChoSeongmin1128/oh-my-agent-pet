# Privacy

Oh My Agent Pet is designed to observe local agent-task state and navigate back to the corresponding local task without collecting the contents of your work.

There is no installable release yet. This document describes the implemented Claude and Codex hook data boundary and the privacy contract for first-release features that are still in development.

## Data the app does not collect

- Prompt or response text
- Tool input or output
- Internal reasoning
- Usage analytics or telemetry
- Account credentials

## Local state

The app stores only the minimum local metadata needed for task identity, status, navigation, preferences, downloaded pets, and the small unseen-result indicator. User data is stored under the app's Application Support and preferences domains.

Installed pets are copied into `~/Library/Application Support/Oh My Agent Pet/Pets`. Each copy keeps the original `pet.json` and image files and adds an install record with the install time, the source kind (folder name, archive file name, or the codex-pets.net page link), content fingerprints, and any license name, URL, attribution, or notice file the package declared. The current pet selection is stored next to the library in `selection.json`. Nothing about the source folder or archive beyond its name is recorded, and source files are never modified or removed.

When Claude Code or Codex is connected, the local hook records only the provider, event type, session and optional turn identifier, working directory, receive time, and limited state labels such as source, notification type, and tool name. For exact navigation it may also store a known application bundle identifier, a normalized desktop or terminal surface, the iTerm session identifier, and the controlling TTY. It never stores the rest of the process environment. It does not store the transcript path, prompt, permission mode, tool input or output, notification message, error details, or assistant response. Hook events are appended to a local file readable only by the user account. Existing schema-1 and schema-2 records remain readable after the shared schema-3 migration.

For Codex, the app reads local session-index titles plus rollout session identity, working directory, and only the structural lifecycle fields needed to distinguish a started, completed, or interrupted turn. It does not decode or copy user messages, agent responses, tool contents, or reasoning records. Connecting Codex through Settings or `omapet setup connect codex` adds marked command hooks to `hooks.json` and stores only their exact current trust hashes under `hooks.state` in `config.toml`. Disconnecting removes those marked hooks and trust entries. Rollout files and the session index remain read-only.

For Claude Desktop Code navigation, the app reads only `sessionId`, `cliSessionId`, `isArchived`, and `lastActivityAt` from bounded local session metadata files. Other fields in those files are not decoded or copied.

Optional card fields that are disabled do not trigger their additional parsing, requests, subscriptions, or UI timers.

## Diagnostics

The planned diagnostics feature will collect detailed diagnostics only after you open the separate debug window. They will remain in memory, stop when the window closes, and be cleared unless you explicitly export them.

An export will create local Markdown and JSONL files after showing what they contain. The app will never send an export automatically.

## Network access

The app may access the network for these purposes:

- Fetching the signed update feed and release notes
- Downloading a signed update archive after the user chooses to install it or enables automatic downloads
- Downloading a pet from `https://codex-pets.net` after an explicit user action

Pet downloads happen only when you continue from a pasted codex-pets.net link in Settings or run `omapet pet inspect` or `omapet pet install` with such a link. The app requests the pet's metadata and its archive from `codex-pets.net` over HTTPS only, follows at most three redirects that stay on that host, rejects archives above the documented size limits, and sends no cookies, identifiers, or tracking parameters. From the metadata response it reads only the download URL and the owner handle, which is stored as attribution.

Update requests contain no product-specific user identifier, custom tracking parameter, or system profile. Automatic update checks and automatic downloads can be disabled independently.

## Permissions

The planned exact-navigation feature will request Automation permission for an individual target app only when you first use navigation to that target. Accessibility permission will not be a default requirement and will be requested only if an enabled feature actually needs it.

Refusing a permission will not stop local status observation. It will limit only the feature that requires that permission and provide a recovery path in Settings.

## Removal

The planned normal removal flow will delete the app's integrations, runtime state, caches, diagnostics, and unseen-result state while keeping downloaded pets and preferences. Removing all data will be a separate explicit action.

Other tools' hooks, settings, credentials, and files are not removed.
