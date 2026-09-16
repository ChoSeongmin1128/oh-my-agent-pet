# Privacy

Oh My Agent Pet is designed to observe local agent-task state and navigate back to the corresponding local task without collecting the contents of your work.

## Data the app does not collect

- Prompt or response text
- Tool input or output
- Internal reasoning
- Usage analytics or telemetry
- Account credentials

## Local state

The app stores only the minimum local metadata needed for task identity, status, navigation, preferences, downloaded pets, and the small unseen-result indicator. User data is stored under the app's Application Support and preferences domains.

Optional card fields that are disabled do not trigger their additional parsing, requests, subscriptions, or UI timers.

## Diagnostics

Detailed diagnostics are collected only after you open the separate debug window. They remain in memory, stop when the window closes, and are cleared unless you explicitly export them.

An export creates local Markdown and JSONL files after showing what they contain. The app never sends an export automatically.

## Network access

The app may access the network for these purposes:

- Checking the fixed GitHub Releases endpoint for an update
- Downloading a pet after an explicit user action

Update requests contain no product-specific user identifier. Automatic update checks can be disabled.

## Permissions

The app requests Automation permission for an individual target app only when you first use exact navigation to that target. Accessibility permission is not a default requirement and is requested only if a future enabled feature actually needs it.

Refusing a permission does not stop local status observation. It limits only the feature that requires that permission and provides a recovery path in Settings.

## Removal

Normal removal deletes the app's integrations, runtime state, caches, diagnostics, and unseen-result state while keeping downloaded pets and preferences. Removing all data is a separate explicit action.

Other tools' hooks, settings, credentials, and files are not removed.
