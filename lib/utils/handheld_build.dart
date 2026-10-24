/// Whether this is a build for handheld firmware (NeOS), set at build time
/// with `--dart-define=NEOS_PLATFORM=handheld`.
///
/// Handheld builds run full-screen under flutter-pi, which draws straight to
/// the display without a window manager and cannot load plugins written
/// against the GTK embedder (window_manager, fullscreen_window, fvp, ...).
/// `Platform.isLinux` is still true there, so code that needs one of those
/// plugins on Linux has to check this as well.
const bool isHandheldBuild =
    String.fromEnvironment('NEOS_PLATFORM') == 'handheld';
