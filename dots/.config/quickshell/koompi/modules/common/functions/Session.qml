pragma Singleton
import Quickshell
import qs.services
import qs.modules.common

Singleton {
    id: root

    function closeAllWindows() {
        // Hyprland reports pid -1 for a window whose client it cannot resolve,
        // and `kill 0` signals the whole process group.
        HyprlandData.windowList.map(w => w.pid).filter(pid => pid > 0).forEach(pid => {
            Quickshell.execDetached(["kill", pid]);
        });
    }

    function changePassword() {
        Quickshell.execDetached(["bash", "-c", `${Config.options.apps.changePassword}`]);
    }

    function lock() {
        Quickshell.execDetached(["loginctl", "lock-session"]);
    }

    function suspend() {
        Quickshell.execDetached(["bash", "-c", "systemctl suspend || loginctl suspend"]);
    }

    function logout() {
        // `pkill -i Hyprland` is unscoped: it matches every compositor this user
        // owns, so a shell left over from an earlier session takes down the live
        // one. It also only killed the compositor, leaving the rest of the
        // session's processes in a scope logind then waits on indefinitely
        // (KillUserProcesses=no) - two sessions leaked that way for hours.
        // logind ends exactly the calling session, and SIGTERMs its scope.
        Quickshell.execDetached(["bash", "-c",
            'loginctl terminate-session "$XDG_SESSION_ID" || hyprctl dispatch exit']);
    }

    function launchTaskManager() {
        Quickshell.execDetached(["bash", "-c", `${Config.options.apps.taskManager}`]);
    }

    function hibernate() {
        Quickshell.execDetached(["bash", "-c", `systemctl hibernate || loginctl hibernate`]);
    }

    function poweroff() {
        closeAllWindows();
        Quickshell.execDetached(["bash", "-c", `systemctl poweroff || loginctl poweroff`]);
    }

    function reboot() {
        closeAllWindows();
        Quickshell.execDetached(["bash", "-c", `reboot || loginctl reboot`]);
    }

    function rebootToFirmware() {
        closeAllWindows();
        Quickshell.execDetached(["bash", "-c", `systemctl reboot --firmware-setup || loginctl reboot --firmware-setup`]);
    }
}
