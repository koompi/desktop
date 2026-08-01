pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool packageManagerRunning: false
    property bool downloadRunning: false

    // logind says "na" with no resume device. Probed once; needs a reboot to change.
    property bool canHibernate: false

    function refresh() {
        packageManagerRunning = false;
        downloadRunning = false;
        detectPackageManagerProc.running = false;
        detectPackageManagerProc.running = true;
        detectDownloadProc.running = false;
        detectDownloadProc.running = true;
    }

    Process {
        id: detectPackageManagerProc
        command: ["bash", "-c", "pidof yay paru dnf zypper apt apx xbps snap apk yum epsi pikman || ls /var/lib/pacman/db.lck"]
        onExited: (exitCode, exitStatus) => {
            root.packageManagerRunning = (exitCode === 0);
        }
    }

    Process {
        id: detectDownloadProc
        command: ["bash", "-c", "pidof curl wget aria2c yt-dlp || ls ~/Downloads | grep -E '\.crdownload$|\.part$'"]
        onExited: (exitCode, exitStatus) => {
            root.downloadRunning = (exitCode === 0);
        }
    }

    Process {
        id: detectHibernateProc
        running: true
        // "challenge" = possible, just needs auth.
        command: ["bash", "-c", "busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager CanHibernate | grep -qE '\"(yes|challenge)\"'"]
        onExited: (exitCode, exitStatus) => {
            root.canHibernate = (exitCode === 0);
        }
    }
}
