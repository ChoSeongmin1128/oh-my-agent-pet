# Privacy

Oh My Agent Pet is designed to observe local agent-task state and navigate back to the corresponding local task without collecting the contents of your work.

There is no installable release yet. This document describes the implemented Claude hook data boundary and the privacy contract for first-release features that are still in development.

## Data the app does not collect

- Prompt or response text
- Tool input or output
- Internal reasoning
- Usage analytics or telemetry
- Account credentials

## Local state

The app stores only the minimum local metadata needed for task identity, status, navigation, preferences, downloaded pets, and the small unseen-result indicator. User data is stored under the app's Application Support and preferences domains.

When Claude Code is connected, the local hook records only its event type, session identifier, working directory, receive time, and limited state labels such as source, notification type, and tool name. It does not store the transcript path, prompt, permission mode, tool input or output, notification message, error details, or assistant response. Hook events are appended to a local file readable only by the user account.

Optional card fields that are disabled do not trigger their additional parsing, requests, subscriptions, or UI timers.

## Diagnostics

The planned diagnostics feature will collect detailed diagnostics only after you open the separate debug window. They will remain in memory, stop when the window closes, and be cleared unless you explicitly export them.

An export will create local Markdown and JSONL files after showing what they contain. The app will never send an export automatically.

## Network access

The app may access the network for these purposes:

- Fetching the signed update feed and release notes
- Downloading a signed update archive after the user chooses to install it or enables automatic downloads
- Downloading a pet after an explicit user action

Update requests contain no product-specific user identifier, custom tracking parameter, or system profile. Automatic update checks and automatic downloads can be disabled independently.

## Permissions

The planned exact-navigation feature will request Automation permission for an individual target app only when you first use navigation to that target. Accessibility permission will not be a default requirement and will be requested only if an enabled feature actually needs it.

Refusing a permission will not stop local status observation. It will limit only the feature that requires that permission and provide a recovery path in Settings.

## Removal

The planned normal removal flow will delete the app's integrations, runtime state, caches, diagnostics, and unseen-result state while keeping downloaded pets and preferences. Removing all data will be a separate explicit action.

Other tools' hooks, settings, credentials, and files are not removed.
