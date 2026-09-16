import QtQuick
import Quickshell
import Quickshell.Wayland
import QtMultimedia
import SessionLock
import "./shim"

ShellRoot {
    id: shellRoot

    property string activeTheme: Quickshell.env("QS_THEME") || "nier-automata"
    property string themePath: Quickshell.env("QS_THEME_PATH") || (Quickshell.shellDir + "/themes_link/" + activeTheme)

    readonly property var sddm: sddmShim.sddm
    readonly property var config: sddmShim.config
    readonly property var userModel: sddmShim.userModel
    readonly property var sessionModel: sddmShim.sessionModel
    readonly property bool isWayland: Quickshell.env("XDG_SESSION_TYPE") === "wayland"
    property bool authenticated: false
    property bool sessionLocked: true
    property bool isTesting: Quickshell.env("QS_TESTING") === "1"

    SddmShim {
        id: sddmShim
        themePath: shellRoot.themePath
    }

    SessionLock {
        id: slock
    }

    Connections {
        target: sddmShim.sddm
        function onLoginSucceeded() {
            shellRoot.authenticated = true;

            // Hyprland session lock fix
            if (Quickshell.env("XDG_CURRENT_DESKTOP") === "Hyprland" || Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") !== "") {
                Quickshell.execDetached(["hyprctl", "keyword", "misc:allow_session_lock_restore", "1"]);
            }
            Quickshell.execDetached(["loginctl", "unlock-session"]);

            // Dynamic exit delay
            let delay = 100;
            if (activeTheme.includes("clockwork") && sddmShim.config.enableWindup === "true") {
                delay = 500;
            }
            quitTimer.interval = delay;
            quitTimer.start();
        }
    }

    Timer {
        id: quitTimer
        interval: 3000
        onTriggered: {
            shellRoot.sessionLocked = false;
            slock.startConnection();
            slock.sendMessage("AUTHENTICATION_SUCCESSFUL");
            slock.closeConnection();
            Qt.quit();
        }
    }

    Component {
        id: themeComponent
        Loader {
            anchors.fill: parent
            source: "file://" + shellRoot.themePath + "/Main.qml"

            onLoaded: {
                item.forceActiveFocus();
            }
            onStatusChanged: {
                if (status === Loader.Error) {
                    console.error("FAILED to load theme:", source);
                }
            }
        }
    }

    Loader {
        id: waylandLoader
        active: shellRoot.isWayland
        sourceComponent: Component {
            WlSessionLock {
                id: lock
                locked: shellRoot.sessionLocked
                surface: Component {
                    WlSessionLockSurface {
                        color: "black"

                        // Absorb unhandled gestures
                        PinchHandler {
                            target: null
                        }
                        WheelHandler {
                            target: null
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.AllButtons
                            hoverEnabled: true
                            onWheel: wheel => {
                                wheel.accepted = true;
                            }
                        }

                        Loader {
                            anchors.fill: parent
                            sourceComponent: themeComponent
                        }
                    }
                }
            }
        }
    }

    Loader {
        id: x11Loader
        active: !shellRoot.isWayland
        sourceComponent: Component {
            Variants {
                model: Quickshell.screens
                delegate: Window {
                    id: window
                    required property var modelData
                    screen: modelData
                    width: isTesting ? 1280 : screen.width
                    height: isTesting ? 720 : screen.height
                    visible: shellRoot.sessionLocked
                    visibility: isTesting ? Window.Windowed : Window.FullScreen

                    onVisibleChanged: {
                        if (visible) {
                            const xid = slock.id(window);
                            if (xid === 0) {
                                console.error("Window handle is not ready yet!");
                                return;
                            }

                            console.log("OPEN:", slock.startConnection());
                            console.log("SEND:", slock.sendMessage("WINDOW_ID:" + xid));
                            console.log("GRAB:", slock.grabInputs());
                            console.log("CLOSE:", slock.closeConnection());
                        }
                    }

                    onClosing: close => {
                        close.accepted = shellRoot.authenticated || shellRoot.isTesting;
                    }

                    flags: Qt.WindowStaysOnTopHint | Qt.FramelessWindowHint | Qt.MaximizeUsingFullscreenGeometryHint
                    color: "black"

                    Loader {
                        anchors.fill: parent
                        sourceComponent: themeComponent
                    }
                }
            }
        }
    }
}
