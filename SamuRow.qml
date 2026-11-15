import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets as DC

// One row of the Forecast list: a task or an appointment, as
// `samu forecast --format json` gives it (ADR 0083 §2).
Item {
    id: row

    property var item: null
    property bool selected: false
    property bool clocked: false

    signal complete
    signal toggleClock
    signal toggleFlag
    signal open
    signal picked

    readonly property bool isTask: item?.kind ? item.kind === "task" : (item?.why ?? "") !== "termin"
    readonly property bool overdue: (item?.due ?? "") === "overdue"

    implicitHeight: layout.implicitHeight + Theme.spacingS * 2

    StyledRect {
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: row.selected ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
             : hover.containsMouse ? Theme.surfaceContainerHigh
             : "transparent"
        border.width: row.selected ? 1 : 0
        border.color: Theme.primary
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        onClicked: row.picked()
        onDoubleClicked: row.open()
    }

    RowLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Theme.spacingS
        anchors.rightMargin: Theme.spacingS
        spacing: Theme.spacingS

        // Check circle for a task, the calendar for an appointment; left of
        // it the priority as a bar, A red, B orange, C yellow (ADR 0089).
        Item {
            Layout.preferredWidth: 31
            Layout.preferredHeight: 24
            Layout.alignment: Qt.AlignTop

            Rectangle {
                readonly property string prio: row.isTask ? (row.item?.priority ?? "") : ""
                visible: prio !== ""
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                height: 20
                radius: 1.5
                // The scope palette's full shades (ADR 0060 §2), light and dark.
                color: {
                    const light = Theme.isLightMode ?? false;
                    if (prio === "A") return light ? "#d0645a" : "#f08a80";
                    if (prio === "B") return light ? "#dd8a45" : "#f0a468";
                    return light ? "#c9a93a" : "#e3c65c";
                }
            }

            DC.DIcon {
                anchors.horizontalCenter: checkArea.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                name: !row.isTask ? "event"
                    : checkArea.containsMouse ? "check_circle"
                    : "radio_button_unchecked"
                size: Theme.iconSize - 4
                color: !row.isTask ? Theme.secondary
                     : checkArea.containsMouse ? Theme.primary
                     : row.overdue ? Theme.error
                     : Theme.surfaceVariantText
            }

            MouseArea {
                id: checkArea
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 24
                enabled: row.isTask
                hoverEnabled: true
                cursorShape: row.isTask ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: row.complete()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            StyledText {
                Layout.fillWidth: true
                text: row.item?.title ?? ""
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeMedium
                color: row.overdue ? Theme.error : Theme.surfaceText
            }

            StyledText {
                Layout.fillWidth: true
                visible: text !== ""
                text: row.detail()
                elide: Text.ElideRight
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
        }

        // Flag and clock: shown when set, else on hover or selection.
        Repeater {
            model: row.isTask ? [
                { icon: "flag", on: (row.item?.flag ?? "") !== "", action: "flag" },
                { icon: row.clocked ? "timer" : "timer_play", on: row.clocked, action: "clock" }
            ] : []

            Item {
                required property var modelData
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignTop
                visible: modelData.on || hover.containsMouse || row.selected || iconArea.containsMouse

                DC.DIcon {
                    anchors.centerIn: parent
                    name: modelData.icon
                    size: Theme.iconSize - 6
                    color: modelData.on ? (modelData.action === "flag" ? "#FF9800" : Theme.primary)
                         : iconArea.containsMouse ? Theme.surfaceText
                         : Theme.surfaceVariantText
                }

                MouseArea {
                    id: iconArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: modelData.action === "flag" ? row.toggleFlag() : row.toggleClock()
                }
            }
        }
    }

    // The second line: where it belongs and why it stands here.
    function detail() {
        const it = row.item;
        if (!it) return "";
        const parts = [];
        if (!row.isTask) {
            if (it.all_day) parts.push("ganztägig");
            else {
                const start = (it.start ?? "").slice(11, 16);
                const end = (it.end ?? "").slice(11, 16);
                parts.push(end ? start + "–" + end : start);
            }
            if (it.location) parts.push(it.location);
            if (it.calendar) parts.push(it.calendar);
            return parts.join(" · ");
        }
        if (it.project) parts.push(it.project);
        if (it.why && it.why !== "Tag" && it.why !== "markiert") {
            parts.push(it.date ? it.why + " " + it.date : it.why);
        } else if (it.due_text) {
            parts.push("fällig " + it.due_text.replace(" overdue", "").replace(" soon", ""));
        }
        if (it.state) parts.push(it.state);
        if (it.tags) parts.push(it.tags);
        return parts.join(" · ");
    }
}
