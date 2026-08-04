// The tour's content. Layout lives in Tour.qml and never needs touching to add,
// cut, reorder or translate a step.
//
// Written for someone who has never used Linux: a thing is explained before it
// is named, and never named in jargon. No "tiling", no "compositor", no "window
// manager". `keys` are rendered as keycaps and must match what `hyprctl binds`
// reports, not what reads nicely. `demo` is a GlobalStates flag opened while the
// step is on screen and closed on the way out, so the user sees the real surface
// rather than a picture of one.

const steps = [
    {
        icon: "waving_hand",
        title: "Welcome to KOOMPI",
        body: "This is your desktop. In the next few minutes you will see every part of it.\n\nYou can leave at any time and pick up where you left off.",
        keys: [],
        demo: ""
    },
    {
        icon: "toolbar",
        title: "The strip along the top",
        body: "It is always there. On the left is the KOOMPI star and your desks. In the middle is the program you are using now. On the right is the clock, and the icons for sound, network and battery.",
        keys: [],
        demo: ""
    },
    {
        icon: "grid_view",
        title: "Desks, not one crowded screen",
        body: "Instead of piling every window on one screen, you get several separate desks. Put your writing on one and your browser on another, and switch between them.\n\nScroll on the numbers at the top left, or use these keys.",
        keys: ["Super", "Page Down"],
        demo: ""
    },
    {
        icon: "search",
        title: "Search finds anything",
        body: "Tap Super on its own and start typing. Programs, files, sums, the web. This is the fastest way to open anything, and it is the one thing worth remembering from this tour.",
        keys: ["Super"],
        demo: "searchOpen"
    },
    {
        icon: "select_window",
        title: "See every window at once",
        body: "When you lose a window, this shows all of them across all your desks, laid out small. Click one to go to it, or drag it onto another desk.",
        keys: ["Super", "Tab"],
        demo: "overviewOpen"
    },
    {
        icon: "apps",
        title: "Everything installed",
        body: "A page of every program on the machine, in case you would rather look than type.\n\nOpen it by putting four fingers on the touchpad and spreading them apart.",
        keys: [],
        demo: "launchpadOpen"
    },
    {
        icon: "tune",
        title: "What your machine is doing",
        body: "Sound, screen brightness, network, Bluetooth and battery, with your notifications underneath. The second tab holds your calendar, to-do list and timer.",
        keys: ["Super", "N"],
        demo: "sidebarRightOpen"
    },
    {
        icon: "left_panel_open",
        title: "What your work is doing",
        body: "The panel on the other side. Today it holds the assistant and the translator.",
        keys: ["Super", "A"],
        demo: "sidebarLeftOpen"
    },
    {
        icon: "drag_pan",
        title: "Moving and arranging windows",
        body: "Hold Super and drag a window with the mouse to move it anywhere. Drag it towards an edge and an outline shows where it will land before you let go.\n\nHold Super and drag with the right button to change its size.",
        keys: ["Super", "drag"],
        demo: ""
    },
    {
        icon: "menu_open",
        title: "What a window can do",
        body: "Right-click the name of the program in the top strip. Close it, make it fill the screen, let it float free, pin it in front, or send it to another desk.",
        keys: [],
        demo: ""
    },
    {
        icon: "menu",
        title: "A program's own menus",
        body: "Left-click that same name and the program's own menus - File, Edit, View - drop down from the top strip instead of sitting inside its window.",
        keys: [],
        demo: ""
    },
    {
        icon: "gesture",
        title: "Touchpad shortcuts",
        body: "Three fingers left or right moves between desks. Four fingers up shows every window. Four fingers spread apart opens the list of programs.",
        keys: [],
        demo: ""
    },
    {
        icon: "wallpaper",
        title: "Making it yours",
        body: "Pick a wallpaper and the whole desktop recolours itself to match it. Each desk can have its own.",
        keys: ["Ctrl", "Super", "T"],
        demo: "wallpaperSelectorOpen"
    },
    {
        icon: "keyboard",
        title: "Every shortcut, in one place",
        body: "You are not expected to remember any of this. This list is always one key away, and it stays correct because it is built from the shortcuts themselves.",
        keys: ["Super", "/"],
        demo: "cheatsheetOpen"
    },
    {
        icon: "logout",
        title: "Finishing up",
        body: "Lock the screen when you step away. To log out, restart or shut down, use the power button at the top of the panel from a few steps ago, or these keys.",
        keys: ["Ctrl", "Alt", "Delete"],
        demo: ""
    }
];
