//! Requests an xdg-activation token from the Wayland compositor. The token
//! lets the primary instance raise its window despite focus stealing
//! prevention. Returns None on X11 or when the compositor lacks the protocol.

use wayland_client::protocol::wl_registry;
use wayland_client::{Connection, Dispatch, QueueHandle};
use wayland_protocols::xdg::activation::v1::client::{
    xdg_activation_token_v1::{self, XdgActivationTokenV1},
    xdg_activation_v1::{self, XdgActivationV1},
};

#[derive(Default)]
struct State {
    activation: Option<XdgActivationV1>,
    token: Option<String>,
}

impl Dispatch<wl_registry::WlRegistry, ()> for State {
    fn event(
        state: &mut Self,
        registry: &wl_registry::WlRegistry,
        event: wl_registry::Event,
        _: &(),
        _: &Connection,
        qh: &QueueHandle<Self>,
    ) {
        if let wl_registry::Event::Global {
            name, interface, ..
        } = event
        {
            if interface == "xdg_activation_v1" {
                state.activation = Some(registry.bind(name, 1, qh, ()));
            }
        }
    }
}

impl Dispatch<XdgActivationV1, ()> for State {
    fn event(
        _: &mut Self,
        _: &XdgActivationV1,
        _: xdg_activation_v1::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<XdgActivationTokenV1, ()> for State {
    fn event(
        state: &mut Self,
        _: &XdgActivationTokenV1,
        event: xdg_activation_token_v1::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        if let xdg_activation_token_v1::Event::Done { token } = event {
            state.token = Some(token);
        }
    }
}

/// KDE fallback: KWin only grants real activation tokens to clients with a
/// recent input serial, which a headless CLI process never has. Its
/// scripting interface is exempt from focus stealing prevention, so ask it
/// to activate the pnote window directly. Silently does nothing outside KDE.
pub fn kwin_raise() {
    use std::process::Command;
    let script = r#"
var list = typeof workspace.windowList === "function" ? workspace.windowList() : workspace.clientList();
for (var i = 0; i < list.length; ++i) {
    var w = list[i];
    if (w.resourceClass == "pnote") {
        w.minimized = false;
        if ("activeWindow" in workspace) workspace.activeWindow = w;
        else workspace.activeClient = w;
        break;
    }
}
"#;
    let dir = dirs::runtime_dir().unwrap_or_else(std::env::temp_dir);
    let path = dir.join(format!("pnote-raise-{}.js", std::process::id()));
    if std::fs::write(&path, script).is_err() {
        return;
    }
    let loaded = Command::new("busctl")
        .args([
            "--user",
            "call",
            "org.kde.KWin",
            "/Scripting",
            "org.kde.kwin.Scripting",
            "loadScript",
            "s",
        ])
        .arg(&path)
        .output();
    let id = loaded
        .ok()
        .filter(|out| out.status.success())
        .and_then(|out| String::from_utf8(out.stdout).ok())
        .and_then(|s| s.trim().rsplit(' ').next().map(str::to_string));
    if let Some(id) = id {
        // The script object path moved between KWin versions.
        for object in [format!("/Scripting/Script{id}"), format!("/{id}")] {
            let ran = Command::new("busctl")
                .args(["--user", "call", "org.kde.KWin", &object, "org.kde.kwin.Script", "run"])
                .output()
                .map(|out| out.status.success())
                .unwrap_or(false);
            if ran {
                std::thread::sleep(std::time::Duration::from_millis(200));
                let _ = Command::new("busctl")
                    .args(["--user", "call", "org.kde.KWin", &object, "org.kde.kwin.Script", "stop"])
                    .output();
                break;
            }
        }
    }
    let _ = std::fs::remove_file(&path);
}

pub fn request_token() -> Option<String> {
    let conn = Connection::connect_to_env().ok()?;
    let mut queue = conn.new_event_queue();
    let qh = queue.handle();
    conn.display().get_registry(&qh, ());
    let mut state = State::default();
    queue.roundtrip(&mut state).ok()?;
    let activation = state.activation.take()?;
    let request = activation.get_activation_token(&qh, ());
    request.set_app_id("pnote".to_string());
    request.commit();
    queue.roundtrip(&mut state).ok()?;
    request.destroy();
    state.token
}
