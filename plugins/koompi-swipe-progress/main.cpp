// Hyprland moves the workspaces under your fingers during a touchpad swipe but
// publishes nothing about it, so a shell drawing the wallpaper on a layer
// surface only learns of the switch when the gesture commits - a whole gesture
// late. This forwards the render offset Hyprland is already applying, so the
// wallpaper can ride along with the windows.
//
// Offset rather than finger delta on purpose: the offset is what actually got
// rendered, so the edge cases (no workspace that way, direction lock, clamping
// at the swipe distance) come out right without repeating any of that logic.

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/managers/EventManager.hpp>
#include <hyprland/src/managers/input/UnifiedWorkspaceSwipeGesture.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/Workspace.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/helpers/MiscFunctions.hpp>
#include <hyprland/src/config/ConfigValue.hpp>

#include <cmath>
#include <cstring>
#include <format>

inline HANDLE                PHANDLE = nullptr;

static CFunctionHook*        g_hookBegin  = nullptr;
static CFunctionHook*        g_hookUpdate = nullptr;
static CFunctionHook*        g_hookEnd    = nullptr;
static double                g_lastSentX  = 0;

static void post(const std::string& event, const std::string& data) {
    if (g_pEventManager)
        g_pEventManager->postEvent(SHyprIPCEvent{event, data});
}

static void postOffset() {
    const auto MONITOR = Desktop::focusState()->monitor();
    if (!MONITOR || !MONITOR->m_activeWorkspace)
        return;

    if (!MONITOR->m_activeWorkspace->m_renderOffset)
        return;

    const double X = MONITOR->m_activeWorkspace->m_renderOffset->value().x;
    // Touchpads report far faster than the screen redraws. A sub-pixel move is
    // not worth waking every socket2 client for.
    if (std::abs(X - g_lastSentX) < 1.0)
        return;

    g_lastSentX = X;

    // Positive offset means the workspace slid right, so the one arriving is
    // the one on its left. Resolved the same way the gesture resolves it, or
    // the answer disagrees with what is on screen.
    static auto PSWIPEUSER = CConfigValue<Config::INTEGER>("gestures:workspace_swipe_use_r");
    const auto  TARGET     = getWorkspaceIDNameFromString(X > 0 ? (*PSWIPEUSER ? "r-1" : "m-1") : (*PSWIPEUSER ? "r+1" : "m+1")).id;

    post("koompiswipe", std::format("{},{},{:.1f}", MONITOR->m_name, TARGET, X));
}

typedef void (*origBeginEnd)(void*);
typedef void (*origUpdate)(void*, double);

static void hkBegin(void* thisptr) {
    ((origBeginEnd)g_hookBegin->m_original)(thisptr);
    g_lastSentX = 0;
    post("koompiswipebegin", Desktop::focusState()->monitor() ? Desktop::focusState()->monitor()->m_name : "");
}

static void hkUpdate(void* thisptr, double delta) {
    ((origUpdate)g_hookUpdate->m_original)(thisptr, delta);
    postOffset();
}

static void hkEnd(void* thisptr) {
    // workspace_swipe_forever makes update() call end() then begin() mid
    // gesture; that commits for real, so it is right that both fire.
    ((origBeginEnd)g_hookEnd->m_original)(thisptr);
    post("koompiswipeend", "");
}

// The gesture methods are non-virtual and exported, so the linker resolves a
// pointer-to-member straight to the address the hook needs. Beats searching the
// symbol table by name, which cannot tell these three apart from every other
// begin/update/end in the compositor.
template <typename T>
static void* addressOf(T pmf) {
    void* addr = nullptr;
    std::memcpy(&addr, &pmf, sizeof(addr));
    return addr;
}

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;

    // No version check here: Hyprland already refuses to load a plugin whose
    // client hash does not match its own, and it does it before init.

    void* begin  = addressOf(&CUnifiedWorkspaceSwipeGesture::begin);
    void* update = addressOf(&CUnifiedWorkspaceSwipeGesture::update);
    void* end    = addressOf(&CUnifiedWorkspaceSwipeGesture::end);

    g_hookBegin  = HyprlandAPI::createFunctionHook(PHANDLE, begin, (void*)&hkBegin);
    g_hookUpdate = HyprlandAPI::createFunctionHook(PHANDLE, update, (void*)&hkUpdate);
    g_hookEnd    = HyprlandAPI::createFunctionHook(PHANDLE, end, (void*)&hkEnd);

    g_hookBegin->hook();
    g_hookUpdate->hook();
    g_hookEnd->hook();

    // A touchpad is the only thing that can normally drive this, which leaves
    // nothing to test against. `hyprctl dispatch koompiswipesim begin|<delta>|end`
    // walks the real gesture, so the whole path can be checked without fingers.
    HyprlandAPI::addDispatcherV2(PHANDLE, "koompiswipesim", [](std::string arg) -> SDispatchResult {
        if (arg == "begin")
            g_pUnifiedWorkspaceSwipe->begin();
        else if (arg == "end")
            g_pUnifiedWorkspaceSwipe->end();
        else
            g_pUnifiedWorkspaceSwipe->update(std::stod(arg));
        return {};
    });

    return {"koompi-swipe-progress", "Publishes workspace swipe progress on the event socket", "KOOMPI", "1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    ;
}
