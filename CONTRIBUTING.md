# Contributing

Thank you for helping a small robot be a good teammate.

- **Issues:** a bug (what you did, what happened, your macOS version and chat model), an idea, or a
  teammate file you made that others would enjoy.
- **Pull requests:** one change per pull request, with a test for the behaviour you changed.
  `swift test` must pass (no servers needed), and so must
  `swift format lint --strict --recursive Sources Tests Package.swift` and
  `swift build -Xswiftc -warnings-as-errors`. Logic belongs in `TeammateKit`, behind the protocols in
  `Services.swift`, where it can be tested; the app target only creates platform objects, shows state
  and calls the session.
- **Shared formats:** `settings.toml`, the teammate files and the expression table are shared with
  [humanoid-companion](https://github.com/YauhenBichel/humanoid-companion). A change to them needs the
  same change there; `Tests/TeammateKitTests/Fixtures` holds files written by the companion.
- **Checks stay:** replies are validated before they are shown or spoken, stop words never reach the
  model, and a failure gets an apology, not a crash.

By contributing you agree that your contribution is licensed under Apache-2.0.
