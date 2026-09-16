# Changelog

## Unreleased

- Close the teammate from a × on hover or a right-click menu (which also switches teammates, opens
  settings, reloads and quits).
- Fixed: an answer that arrives after switching teammates no longer appears in the new teammate's bubble.
- Fixed: a quick tap on ⌥Space released before microphone permission no longer leaves recording on.
- Fixed: the mouth keeps moving while a menu is open; a taken ⌥Space is reported instead of ignored.
- Restructured along SOLID lines: an `@Observable` session behind small protocols, an actor
  conversation, typed Codable clients, a pure character painter with a painter per accessory; Swift 6
  language mode, swift-format in CI, 34 tests.

## 0.1.0 (unreleased)

First version.

- A floating robot teammate on the Mac desktop, with a menu bar item: switch, hide, open settings, reload.
- Byte (computer science) and Tempo (music), and your own teammates from TOML files shared with
  humanoid-companion.
- Talk by typing or by holding ⌥Space; answers with face, speech bubble and voice, over OpenAI-compatible
  chat, speech and transcription servers.
- `scripts/build-app.sh --install` builds an ad-hoc-signed app into ~/Applications.
