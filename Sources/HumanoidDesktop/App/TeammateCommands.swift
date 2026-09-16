/// What the window and the menu bar item can ask the app to do. One set, so both offer the same choices, and
/// neither knows about panels, files or the application object.
struct TeammateCommands {
    var isTeammateVisible: () -> Bool
    var toggleTeammate: () -> Void
    var hideTeammate: () -> Void
    var typeMessage: () -> Void
    var openSettings: () -> Void
    var reload: () -> Void
    var quit: () -> Void
}
