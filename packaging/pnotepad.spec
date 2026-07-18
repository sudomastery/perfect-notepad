%global debug_package %{nil}

Name:           pnotepad
Version:        0.1.0
Release:        1%{?dist}
Summary:        Fast native notepad for KDE with automatic session restore
License:        GPL-3.0-or-later
URL:            https://github.com/sudomastery/perfect-notepad
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  cargo
BuildRequires:  rust
BuildRequires:  gcc-c++
BuildRequires:  qt6-qtbase-devel
BuildRequires:  qt6-qtdeclarative-devel
Requires:       qt6-qtdeclarative

%description
A fast, native notepad for KDE Plasma written in Rust (cxx-qt) with a QML
interface. Tabs like Windows 11 Notepad, continuous autosave with full
session restore, find and replace, word wrap, zoom, and a clear dump
feature that files away unsaved notes into a folder of your choice.

%prep
%autosetup

%build
cargo build --release --locked

%install
install -Dm755 target/release/pnote %{buildroot}%{_bindir}/pnote
install -Dm644 data/pnote.desktop %{buildroot}%{_datadir}/applications/pnote.desktop
install -Dm644 data/icons/pnote.png %{buildroot}%{_datadir}/icons/hicolor/1024x1024/apps/pnote.png

%files
%{_bindir}/pnote
%{_datadir}/applications/pnote.desktop
%{_datadir}/icons/hicolor/1024x1024/apps/pnote.png

%changelog
* Sat Jul 18 2026 sudomastery <koigu80@gmail.com> - 0.1.0-1
- Initial package
