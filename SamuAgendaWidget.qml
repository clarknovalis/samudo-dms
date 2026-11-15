import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets as DC
import qs.Modules.Plugins

// samudo in the DankMaterialShell bar (ADR 0083). Everything goes through
// the `samu` command line with the user's own session; the widget computes
// nothing the server computes (ADR 0006): it draws `samu forecast`.
PluginComponent {
    id: root

    popoutWidth: 520
    popoutHeight: 680

    // ── Settings ────────────────────────────────────────────────────────
    // A variant is the widget of one profile (ADR 0086 §7); DMS sets these.
    property string variantId: ""
    property var variantData: null

    property string samuCommand: pluginData.samuCommand || "samu"
    // A profile of this computer (`samu --profile`); empty: the CLI's default.
    property string profile: variantData ? (variantData.profile || "") : (pluginData.profile || "")
    // "device": what `samu scope use` chose here; "none": no scope; else an id.
    // A variant follows its profile's own choice: scope ids are per account.
    property string scope: variantData ? "device" : (pluginData.scope || "device")
    property string openCommand: pluginData.openCommand || ""
    property int refreshMinutes: parseInt(pluginData.refreshMinutes) || 15
    property bool showLater: pluginData.showLater ?? false
    property bool showClockTitle: pluginData.showClockTitle ?? true

    // ── State ───────────────────────────────────────────────────────────
    property var rows: []
    property bool loading: false
    property string error: ""
    property var clock: null          // the running clock, or null
    property string lastCapture: ""
    property bool captureRequested: false
    property date now: new Date()

    signal captureWanted

    readonly property string today: dayOf(now)

    readonly property var overdueTasks: rows.filter(r => r.section_kind === "overdue" && isTask(r))
    readonly property var todayTasks: rows.filter(r => r.section_kind === "day" && r.day === today && isTask(r))
    readonly property int overdueCount: overdueTasks.length
    readonly property int todayCount: todayTasks.length

    readonly property int clockSeconds: clock ? Math.max(0, Math.floor((now - new Date(clock.start)) / 1000)) : 0

    // The rows as the list draws them: a header before each section.
    readonly property var entries: {
        const out = [];
        let last = null;
        for (const r of rows) {
            if (r.section_kind === "later" && !showLater) continue;
            const key = r.section_kind + "|" + (r.day ?? "");
            if (key !== last) {
                out.push({ header: true, title: sectionTitle(r), overdue: r.section_kind === "overdue" });
                last = key;
            }
            out.push(r);
        }
        return out;
    }

    // ── Running samu ────────────────────────────────────────────────────
    function base(sub) {
        const args = [samuCommand];
        if (profile) args.push("--profile", profile);
        return args.concat(sub);
    }

    function scopeArgs() {
        if (scope === "none") return ["--no-scope"];
        if (scope && scope !== "device") return ["--scope", scope];
        return [];
    }

    Component {
        id: runner
        Process {
            property var done: null
            stdout: StdioCollector {}
            stderr: StdioCollector {}
            onExited: code => {
                const out = String(stdout.text);
                const err = String(stderr.text).trim();
                if (done) done(code, out, err);
                destroy();
            }
        }
    }

    function run(sub, done) {
        const proc = runner.createObject(root, { command: base(sub), done: done });
        proc.running = true;
    }

    // A command that changes something: a toast on failure, then refresh.
    function act(sub, what) {
        run(sub, (code, out, err) => {
            if (code !== 0) ToastService.showError("samudo", what + ": " + (err || "exit " + code));
            refresh();
        });
    }

    function refresh() {
        if (loading) { pending = true; return; }
        loading = true;
        run(["forecast", "--format", "json"].concat(scopeArgs()), (code, out, err) => {
            loading = false;
            if (code !== 0) {
                error = err || "samu forecast: exit " + code;
            } else {
                try {
                    rows = JSON.parse(out.trim() || "[]").map(normalize);
                    error = "";
                } catch (e) {
                    error = "JSON: " + e.message;
                }
            }
            if (pending) { pending = false; Qt.callLater(refresh); }
        });
        run(["clock", "status", "--format", "json"], (code, out) => {
            if (code !== 0) return;
            try {
                const list = JSON.parse(out.trim() || "[]");
                clock = list.length > 0 ? list[0] : null;
            } catch (e) {
                clock = null;
            }
        });
    }
    property bool pending: false

    // ── Actions ─────────────────────────────────────────────────────────
    function complete(r) { if (isTask(r)) act(["done", r.id], "Erledigen"); }

    function toggleFlag(r) {
        if (!isTask(r)) return;
        act(["set", r.id, "flagged", (r.flag ?? "") !== "" ? "false" : "true"], "Markieren");
    }

    function toggleClock(r) {
        if (clock && (!r || clock.owner === r.id)) act(["clock", "out"], "Uhr anhalten");
        else if (r && isTask(r)) act(["clock", "in", r.id], "Uhr starten");
    }

    function open(r) {
        if (!r) return;
        if (!isTask(r)) {
            if (r.link) Quickshell.execDetached(["xdg-open", r.link]);
            return;
        }
        if (openCommand) {
            Quickshell.execDetached(["sh", "-c", openCommand.split("{id}").join(r.id)]);
        } else {
            Quickshell.execDetached(base(["open-uri", "samu:" + r.id]));
        }
    }

    function capture(text, done) {
        text = (text || "").trim();
        if (!text) return;
        run(["add", "--format", "json", "--", text], (code, out, err) => {
            if (code !== 0) {
                ToastService.showError("samudo", "Erfassen: " + (err || "exit " + code));
                if (done) done(false);
                return;
            }
            let title = text;
            try {
                const made = JSON.parse(out)[0];
                title = made.title;
                if ((made.warnings ?? []).length > 0) title += " (" + made.warnings.join("; ") + ")";
            } catch (e) {}
            lastCapture = title;
            ToastService.showInfo("samudo", "Erfasst: " + title);
            refresh();
            if (done) done(true);
        });
    }

    // ── Live: `samu events`, one line per change ────────────────────────
    Process {
        id: events
        running: false
        stdout: SplitParser {
            onRead: _ => debounce.restart()
        }
        onExited: reconnect.start()
    }

    Timer {
        id: debounce
        interval: 700
        onTriggered: root.refresh()
    }

    Timer {
        id: reconnect
        interval: 30000
        onTriggered: {
            interval = 30000;
            root.refresh();
            events.running = true;
        }
    }

    // Fallback, and the day changes at midnight without an event.
    Timer {
        interval: root.refreshMinutes * 60 * 1000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Timer {
        interval: root.clock ? 1000 : 60000
        running: true
        repeat: true
        onTriggered: {
            const before = root.today;
            root.now = new Date();
            if (root.today !== before) root.refresh();
        }
    }

    // A changed command or profile: a new `samu events`. A running one is
    // stopped first; its exit starts the new one through `reconnect`.
    function restart() {
        console.info("[samuAgenda] using", base([]).join(" "));
        refresh();
        events.command = base(["events", "--format", "jsonl"]);
        if (events.running) {
            reconnect.interval = 200;
            events.signal(15);
        } else {
            events.running = true;
        }
    }

    Component.onCompleted: restart()

    // pluginData arrives after onCompleted; profile or command may change.
    onSamuCommandChanged: Qt.callLater(restart)
    onProfileChanged: Qt.callLater(restart)
    onScopeChanged: Qt.callLater(refresh)

    Component.onDestruction: {
        reconnect.stop();
        if (events.running) events.signal(15);
    }

    IpcHandler {
        target: "samuAgenda"

        function toggle(): void { root.triggerPopout(); }
        function refresh(): void { root.refresh(); }
        function capture(): void {
            root.captureRequested = true;
            root.captureWanted();
            if (!root.interactionActive) root.triggerPopout();
        }
        function add(text: string): void { root.capture(text, null); }
        function clockOut(): void { root.toggleClock(null); }
    }

    // ── Helpers ─────────────────────────────────────────────────────────
    // A samu before ADR 0083 §2 names the section only in German words.
    function normalize(r) {
        if (r.section_kind) return r;
        const kinds = { "überfällig": "overdue", "markiert": "flagged", "später": "later" };
        r.section_kind = kinds[r.section] ?? "day";
        if (r.section_kind === "day") r.day = r.section;
        r.kind = r.why === "termin" ? "appointment" : "task";
        return r;
    }

    function isTask(r) { return r.kind ? r.kind === "task" : r.why !== "termin"; }

    function dayOf(d) {
        return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
    }

    function sectionTitle(r) {
        switch (r.section_kind) {
        case "overdue": return "Überfällig";
        case "flagged": return "Markiert";
        case "later": return "Später";
        }
        const day = r.day ?? r.section;
        const p = day.split("-");
        const d = new Date(parseInt(p[0]), parseInt(p[1]) - 1, parseInt(p[2]));
        const names = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"];
        const label = names[d.getDay()] + " " + d.getDate() + "." + (d.getMonth() + 1) + ".";
        const tomorrow = new Date(now);
        tomorrow.setDate(tomorrow.getDate() + 1);
        if (day === today) return "Heute · " + label;
        if (day === dayOf(tomorrow)) return "Morgen · " + label;
        return label;
    }

    function duration(s) {
        const h = Math.floor(s / 3600);
        const m = Math.floor((s % 3600) / 60);
        return h + ":" + String(m).padStart(2, "0");
    }

    function shortTitle(t) {
        t = t || "";
        return t.length > 24 ? t.slice(0, 23) + "…" : t;
    }

    readonly property color pillColor: error ? Theme.surfaceVariantText
        : overdueCount > 0 ? Theme.error
        : todayCount > 0 ? Theme.primary
        : Theme.surfaceVariantText

    // ── Bar ─────────────────────────────────────────────────────────────
    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DC.DIcon {
                name: root.error ? "sync_problem" : root.clock ? "timer" : "task_alt"
                size: Theme.iconSize - 6
                color: root.clock ? Theme.primary : root.pillColor
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                visible: !root.clock && !root.error && (root.overdueCount > 0 || root.todayCount > 0)
                text: root.overdueCount > 0 ? root.overdueCount + "!" : String(root.todayCount)
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: root.pillColor
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                visible: !!root.clock
                text: root.duration(root.clockSeconds)
                      + (root.showClockTitle && root.clock ? " " + root.shortTitle(root.clock.title) : "")
                      + (root.overdueCount > 0 ? "  " + root.overdueCount + "!" : "")
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            DC.DIcon {
                name: root.error ? "sync_problem" : root.clock ? "timer" : "task_alt"
                size: Theme.iconSize - 6
                color: root.clock ? Theme.primary : root.pillColor
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                visible: !root.error && (!!root.clock || root.overdueCount > 0 || root.todayCount > 0)
                text: root.clock ? root.duration(root.clockSeconds)
                    : root.overdueCount > 0 ? root.overdueCount + "!" : String(root.todayCount)
                font.pixelSize: Theme.fontSizeXSmall
                color: root.clock ? Theme.surfaceText : root.pillColor
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // ── Popout ──────────────────────────────────────────────────────────
    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: root.profile ? "samudo · " + root.profile : "samudo"
            detailsText: {
                if (root.error) return "Fehler";
                const parts = [];
                if (root.overdueCount > 0) parts.push(root.overdueCount + " überfällig");
                parts.push(root.todayCount + " heute");
                if (root.clock) parts.push("⏱ " + root.duration(root.clockSeconds));
                return parts.join(" · ");
            }
            showCloseButton: true

            Column {
                id: panel
                width: parent.width
                spacing: Theme.spacingS

                property int tab: root.captureRequested ? 1 : 0

                function focusTab() {
                    if (tab === 1) captureField.forceActiveFocus();
                    else list.forceActiveFocus();
                }
                onTabChanged: Qt.callLater(focusTab)
                Component.onCompleted: {
                    root.captureRequested = false;
                    Qt.callLater(focusTab);
                }

                Connections {
                    target: root
                    function onCaptureWanted() {
                        panel.tab = 1;
                        root.captureRequested = false;
                        Qt.callLater(panel.focusTab);
                    }
                }

                // Tabs
                Row {
                    id: tabs
                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: ["Vorschau", "Erfassen"]

                        Rectangle {
                            required property string modelData
                            required property int index
                            width: (tabs.width - 2) / 2
                            height: 32
                            radius: Theme.cornerRadius
                            color: panel.tab === index ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2) : "transparent"

                            StyledText {
                                anchors.centerIn: parent
                                text: modelData
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: panel.tab === index ? Font.DemiBold : Font.Normal
                                color: panel.tab === index ? Theme.primary : Theme.surfaceVariantText
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: panel.tab = index
                            }
                        }
                    }
                }

                // ── Forecast ────────────────────────────────────────────
                ListView {
                    id: list
                    visible: panel.tab === 0
                    width: parent.width
                    height: 520
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.entries
                    keyNavigationEnabled: false
                    highlightFollowsCurrentItem: false

                    property int selected: -1
                    readonly property var current: selected >= 0 && selected < root.entries.length ? root.entries[selected] : null

                    function step(by) {
                        let i = selected;
                        for (;;) {
                            i += by;
                            if (i < 0 || i >= root.entries.length) return;
                            if (!root.entries[i].header) break;
                        }
                        selected = i;
                        positionViewAtIndex(i, ListView.Contain);
                    }

                    // Keep the selection on the same row when the list reloads.
                    property string selectedId: current && !current.header ? current.id + "|" + current.section : ""
                    onModelChanged: {
                        const at = root.entries.findIndex(e => !e.header && e.id + "|" + e.section === selectedId);
                        selected = at;
                    }

                    Keys.onPressed: event => {
                        const r = current && !current.header ? current : null;
                        switch (event.key) {
                        case Qt.Key_Down: case Qt.Key_J: step(1); break;
                        case Qt.Key_Up: case Qt.Key_K: step(-1); break;
                        case Qt.Key_Return: case Qt.Key_Enter:
                            root.open(r);
                            if (r && popout.closePopout) popout.closePopout();
                            break;
                        case Qt.Key_X: case Qt.Key_Space: if (r) root.complete(r); break;
                        case Qt.Key_F: if (r) root.toggleFlag(r); break;
                        case Qt.Key_C: root.toggleClock(r); break;
                        case Qt.Key_R: root.refresh(); break;
                        case Qt.Key_A: case Qt.Key_Tab: panel.tab = 1; break;
                        default: return;
                        }
                        event.accepted = true;
                    }

                    delegate: Item {
                        id: entry
                        required property var modelData
                        required property int index
                        width: list.width
                        height: modelData.header ? 30 : rowItem.implicitHeight

                        StyledText {
                            visible: entry.modelData.header === true
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingS
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 4
                            text: entry.modelData.title ?? ""
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.DemiBold
                            color: entry.modelData.overdue ? Theme.error : Theme.primary
                        }

                        SamuRow {
                            id: rowItem
                            visible: !entry.modelData.header
                            width: parent.width
                            item: entry.modelData.header ? null : entry.modelData
                            selected: list.selected === entry.index
                            clocked: !!root.clock && root.clock.owner === entry.modelData.id
                            onPicked: { list.selected = entry.index; list.forceActiveFocus(); }
                            onComplete: root.complete(entry.modelData)
                            onToggleFlag: root.toggleFlag(entry.modelData)
                            onToggleClock: root.toggleClock(entry.modelData)
                            onOpen: {
                                root.open(entry.modelData);
                                if (popout.closePopout) popout.closePopout();
                            }
                        }
                    }

                    // Empty, loading or failing.
                    Column {
                        visible: root.entries.length === 0
                        anchors.centerIn: parent
                        width: parent.width - Theme.spacingL * 2
                        spacing: Theme.spacingM

                        DC.DIcon {
                            name: root.error ? "sync_problem" : "task_alt"
                            size: 36
                            color: root.error ? Theme.error : Theme.surfaceVariantText
                            opacity: 0.6
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        StyledText {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            text: root.error ? root.error : root.loading ? "Lädt…" : "Nichts vorgesehen"
                            color: Theme.surfaceVariantText
                        }
                    }
                }

                StyledText {
                    visible: panel.tab === 0
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: root.error && root.entries.length > 0 ? root.error
                        : "↑↓ wählen · ⏎ öffnen · x erledigt · f markieren · c Uhr · a erfassen"
                    elide: Text.ElideRight
                    font.pixelSize: Theme.fontSizeXSmall
                    color: root.error ? Theme.error : Theme.surfaceVariantText
                }

                // ── Capture ─────────────────────────────────────────────
                Column {
                    visible: panel.tab === 1
                    width: parent.width
                    spacing: Theme.spacingM
                    topPadding: Theme.spacingM

                    DC.DTextField {
                        id: captureField
                        width: parent.width
                        placeholderText: "Neue Aufgabe: #projekt @tag !A d:fr ~15m // Notiz"
                        leftIconName: "add_task"
                        onAccepted: {
                            const text = captureField.text;
                            root.capture(text, ok => { if (ok) captureField.text = ""; });
                        }
                        Keys.onEscapePressed: event => {
                            if (captureField.text) { captureField.text = ""; event.accepted = true; }
                            else { panel.tab = 0; event.accepted = true; }
                        }
                        Keys.onTabPressed: event => { panel.tab = 0; event.accepted = true; }
                    }

                    StyledText {
                        width: parent.width
                        wrapMode: Text.Wrap
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        text: "⏎ legt die Aufgabe an (samu add), ohne #projekt in den Eingang oder dorthin, wohin der Scope auf diesem Gerät erfasst.\n"
                            + "#projekt  @tag  !  markiert  !A  Priorität  d:  fällig  s:  verfügbar ab  p:  geplant  ~15m  Aufwand  every:1w  Wiederholung  //  Notiz"
                    }

                    StyledText {
                        visible: root.lastCapture !== ""
                        width: parent.width
                        wrapMode: Text.Wrap
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.primary
                        text: "Zuletzt erfasst: " + root.lastCapture
                    }
                }
            }
        }
    }
}
