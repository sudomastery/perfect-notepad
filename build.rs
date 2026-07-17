use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    CxxQtBuilder::new()
        .qml_module(QmlModule {
            uri: "dev.pnotepad",
            rust_files: &["src/session.rs"],
            qml_files: &["qml/Main.qml"],
            ..Default::default()
        })
        .build();
}
