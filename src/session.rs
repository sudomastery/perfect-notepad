//! Session persistence: every open tab is continuously mirrored to disk so the
//! app can close without prompts and restore exactly where the user left off.

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU32, Ordering};

use serde::{Deserialize, Serialize};

use crate::naming;

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    unsafe extern "RustQt" {
        #[qobject]
        #[qml_element]
        type SessionManager = super::SessionManagerRust;

        #[qinvokable]
        fn load_session(self: &SessionManager) -> QString;

        #[qinvokable]
        fn save_tab(
            self: &SessionManager,
            id: &QString,
            file_path: &QString,
            content: &QString,
            cursor: i32,
            modified: bool,
        );

        #[qinvokable]
        fn remove_tab(self: &SessionManager, id: &QString);

        #[qinvokable]
        fn set_active(self: &SessionManager, index: i32);

        #[qinvokable]
        fn new_id(self: &SessionManager) -> QString;

        #[qinvokable]
        fn read_file(self: &SessionManager, path: &QString) -> QString;

        #[qinvokable]
        fn write_file(self: &SessionManager, path: &QString, content: &QString) -> bool;

        #[qinvokable]
        fn clear_dump(self: &SessionManager, folder: &QString) -> QString;

        #[qinvokable]
        fn get_theme(self: &SessionManager) -> QString;

        #[qinvokable]
        fn set_theme(self: &SessionManager, theme: &QString);

        #[qinvokable]
        fn get_setting(self: &SessionManager, key: &QString) -> QString;

        #[qinvokable]
        fn set_setting(self: &SessionManager, key: &QString, value: &QString);
    }
}

use cxx_qt_lib::QString;

#[derive(Default)]
pub struct SessionManagerRust {}

#[derive(Serialize, Deserialize, Clone, Default)]
struct TabMeta {
    id: String,
    file_path: String,
    cursor: i32,
    modified: bool,
}

#[derive(Serialize, Deserialize, Default)]
struct SessionIndex {
    tabs: Vec<TabMeta>,
    active: i32,
    #[serde(default)]
    theme: String,
    #[serde(default)]
    settings: HashMap<String, String>,
}

fn session_dir() -> PathBuf {
    let dir = dirs::data_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("pnotepad")
        .join("session");
    let _ = fs::create_dir_all(&dir);
    dir
}

fn index_path() -> PathBuf {
    session_dir().join("index.json")
}

fn content_path(id: &str) -> PathBuf {
    session_dir().join(format!("{id}.txt"))
}

fn load_index() -> SessionIndex {
    fs::read_to_string(index_path())
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

fn save_index(index: &SessionIndex) {
    if let Ok(json) = serde_json::to_string_pretty(index) {
        let _ = fs::write(index_path(), json);
    }
}

/// A tab id only contains hex digits and hyphens; reject anything else so an
/// id can never traverse outside the session directory.
fn valid_id(id: &str) -> bool {
    !id.is_empty() && id.chars().all(|c| c.is_ascii_hexdigit() || c == '-')
}

fn unique_path(folder: &Path, base: &str) -> PathBuf {
    let first = folder.join(format!("{base}.txt"));
    if !first.exists() {
        return first;
    }
    for n in 2..1000 {
        let candidate = folder.join(format!("{base} {n}.txt"));
        if !candidate.exists() {
            return candidate;
        }
    }
    folder.join(format!("{base} {}.txt", chrono::Local::now().format("%H%M%S")))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_traversal_ids() {
        assert!(valid_id("18abc-1"));
        assert!(valid_id("ffff"));
        assert!(!valid_id(""));
        assert!(!valid_id("../../etc/passwd"));
        assert!(!valid_id("a/b"));
        assert!(!valid_id("id with spaces"));
    }

    #[test]
    fn unique_path_dedupes() {
        let dir = std::env::temp_dir().join(format!("pnotepad-test-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let first = unique_path(&dir, "note");
        assert_eq!(first.file_name().unwrap(), "note.txt");
        fs::write(&first, "x").unwrap();
        let second = unique_path(&dir, "note");
        assert_eq!(second.file_name().unwrap(), "note 2.txt");
        let _ = fs::remove_dir_all(&dir);
    }
}

impl qobject::SessionManager {
    /// Returns the whole saved session as JSON:
    /// {"tabs": [{"id", "file_path", "cursor", "modified", "content"}], "active": n}
    pub fn load_session(&self) -> QString {
        let index = load_index();
        let tabs: Vec<serde_json::Value> = index
            .tabs
            .iter()
            .map(|t| {
                let content = fs::read_to_string(content_path(&t.id)).unwrap_or_default();
                serde_json::json!({
                    "id": t.id,
                    "file_path": t.file_path,
                    "cursor": t.cursor,
                    "modified": t.modified,
                    "content": content,
                })
            })
            .collect();
        let out = serde_json::json!({ "tabs": tabs, "active": index.active });
        QString::from(&out.to_string())
    }

    pub fn save_tab(
        &self,
        id: &QString,
        file_path: &QString,
        content: &QString,
        cursor: i32,
        modified: bool,
    ) {
        let id = id.to_string();
        if !valid_id(&id) {
            return;
        }
        let _ = fs::write(content_path(&id), content.to_string());

        let mut index = load_index();
        let meta = TabMeta {
            id: id.clone(),
            file_path: file_path.to_string(),
            cursor,
            modified,
        };
        match index.tabs.iter_mut().find(|t| t.id == id) {
            Some(existing) => *existing = meta,
            None => index.tabs.push(meta),
        }
        save_index(&index);
    }

    pub fn remove_tab(&self, id: &QString) {
        let id = id.to_string();
        if !valid_id(&id) {
            return;
        }
        let _ = fs::remove_file(content_path(&id));
        let mut index = load_index();
        index.tabs.retain(|t| t.id != id);
        save_index(&index);
    }

    pub fn set_active(&self, index: i32) {
        let mut idx = load_index();
        idx.active = index;
        save_index(&idx);
    }

    pub fn new_id(&self) -> QString {
        static COUNTER: AtomicU32 = AtomicU32::new(0);
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        let n = COUNTER.fetch_add(1, Ordering::Relaxed);
        QString::from(&format!("{nanos:x}-{n:x}"))
    }

    pub fn read_file(&self, path: &QString) -> QString {
        QString::from(&fs::read_to_string(path.to_string()).unwrap_or_default())
    }

    pub fn write_file(&self, path: &QString, content: &QString) -> bool {
        fs::write(path.to_string(), content.to_string()).is_ok()
    }

    pub fn get_theme(&self) -> QString {
        QString::from(&load_index().theme)
    }

    pub fn set_theme(&self, theme: &QString) {
        let mut index = load_index();
        index.theme = theme.to_string();
        save_index(&index);
    }

    pub fn get_setting(&self, key: &QString) -> QString {
        let index = load_index();
        QString::from(
            index
                .settings
                .get(&key.to_string())
                .map(|s| s.as_str())
                .unwrap_or(""),
        )
    }

    pub fn set_setting(&self, key: &QString, value: &QString) {
        let mut index = load_index();
        index.settings.insert(key.to_string(), value.to_string());
        save_index(&index);
    }

    /// Dump every unsaved note into `folder` with a name derived from its
    /// content, then drop those tabs from the session. File-backed tabs are
    /// left untouched. Returns JSON: {"closed": [ids], "dumped": n}
    pub fn clear_dump(&self, folder: &QString) -> QString {
        let folder = PathBuf::from(folder.to_string());
        let mut index = load_index();
        let mut closed: Vec<String> = Vec::new();
        let mut kept: Vec<TabMeta> = Vec::new();
        let mut dumped = 0usize;

        let writable = fs::create_dir_all(&folder).is_ok();

        for tab in index.tabs.drain(..) {
            if !tab.file_path.is_empty() {
                kept.push(tab);
                continue;
            }
            let content = fs::read_to_string(content_path(&tab.id)).unwrap_or_default();
            if content.trim().is_empty() {
                // Nothing worth keeping, just close it
                let _ = fs::remove_file(content_path(&tab.id));
                closed.push(tab.id);
                continue;
            }
            if !writable {
                kept.push(tab);
                continue;
            }
            let name = naming::suggest_name(&content);
            let target = unique_path(&folder, &name);
            if fs::write(&target, &content).is_ok() {
                let _ = fs::remove_file(content_path(&tab.id));
                closed.push(tab.id);
                dumped += 1;
            } else {
                kept.push(tab);
            }
        }

        index.tabs = kept;
        save_index(&index);

        let out = serde_json::json!({ "closed": closed, "dumped": dumped });
        QString::from(&out.to_string())
    }
}
