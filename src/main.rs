mod instance;
mod naming;
mod session;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QUrl};

fn main() {
    for arg in std::env::args().skip(1) {
        match arg.as_str() {
            "-h" | "--help" => {
                println!(
                    "pnote {}\n\
                     Fast native notepad with automatic session restore\n\n\
                     Usage: pnote [FILE...]\n\n\
                     Opens the given files as tabs. With no arguments, restores\n\
                     the previous session.\n\n\
                     Options:\n  \
                     -h, --help     Show this help\n  \
                     -V, --version  Show version",
                    env!("CARGO_PKG_VERSION")
                );
                return;
            }
            "-V" | "--version" => {
                println!("pnote {}", env!("CARGO_PKG_VERSION"));
                return;
            }
            _ => {}
        }
    }

    // If an instance is already running, hand it our files and exit.
    if instance::send_to_existing(&session::resolve_cli_files()) {
        return;
    }
    instance::bind();

    let mut app = QGuiApplication::new();
    let mut engine = QQmlApplicationEngine::new();

    if let Some(engine) = engine.as_mut() {
        engine.load(&QUrl::from("qrc:/qt/qml/dev/pnotepad/qml/Main.qml"));
    }

    if let Some(app) = app.as_mut() {
        app.exec();
    }
}
