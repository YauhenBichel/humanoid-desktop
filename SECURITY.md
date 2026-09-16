# Security policy

Please report a vulnerability privately through GitHub's
[private vulnerability reporting](https://github.com/YauhenBichel/humanoid-desktop/security/advisories/new),
not in a public issue. You will get an answer within a week.

In scope: handling of the chat, speech and transcription servers' responses, the settings and teammate
files, microphone recordings (made only while ⌥Space is held, sent only to the configured transcription
server, deleted right after), and the global hot key.

Keep API keys in the environment (`HUMANOID_LLM_API_KEY`), never in `settings.toml`, a teammate file or
an issue.
