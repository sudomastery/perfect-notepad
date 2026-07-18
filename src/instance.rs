//! Single-instance support: a Unix socket in the user's runtime dir. A new
//! launch first tries to hand its file list to a running instance; if none
//! answers, it binds the socket itself and serves later launches.

use std::io::Write;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;
use std::sync::{Mutex, OnceLock};

fn socket_path() -> PathBuf {
    dirs::runtime_dir()
        .unwrap_or_else(std::env::temp_dir)
        .join("pnote.sock")
}

/// Try to deliver `files` (absolute paths) to a running instance. Returns
/// true if one accepted; the caller should then exit. An empty list still
/// gets sent so the running window is raised. On Wayland the payload also
/// carries an xdg-activation token so the compositor lets that window
/// come to the front.
pub fn send_to_existing(files: &[String]) -> bool {
    let Ok(mut stream) = UnixStream::connect(socket_path()) else {
        return false;
    };
    let token = crate::activation::request_token();
    if std::env::var_os("PNOTE_DEBUG").is_some() {
        eprintln!("pnote: activation token: {token:?}");
    }
    let json = serde_json::json!({ "files": files, "token": token }).to_string();
    stream.write_all(json.as_bytes()).is_ok()
}

static LISTENER: OnceLock<Mutex<Option<UnixListener>>> = OnceLock::new();

/// Become the primary instance. Only called after `send_to_existing` failed,
/// so any socket file still on disk is stale and safe to replace.
pub fn bind() {
    let path = socket_path();
    let _ = std::fs::remove_file(&path);
    if let Ok(listener) = UnixListener::bind(&path) {
        let _ = LISTENER.set(Mutex::new(Some(listener)));
    }
}

pub fn take_listener() -> Option<UnixListener> {
    LISTENER.get()?.lock().ok()?.take()
}
