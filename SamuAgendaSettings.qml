import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets as DC
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "samuAgenda"

    // The scopes to choose from, read from `samu scope list` (ADR 0083 §4).
    property var scopeOptions: [
        { label: "Wie auf diesem Gerät (samu scope use)", value: "device" },
        { label: "Ohne Scope", value: "none" }
    ]
    property string scopeError: ""

    // The profiles of this computer, from `samu profile list` (ADR 0086 §7).
    property var profiles: []
    property var profileOptions: [{ label: "Wie die Kommandozeile (default)", value: "" }]
    property string profileError: ""

    function samu() {
        return loadValue("samuCommand", "samu") || "samu";
    }

    function loadScopes() {
        const cmd = [samu()];
        const profile = loadValue("profile", "");
        if (profile) cmd.push("--profile", profile);
        scopeProc.command = cmd.concat(["scope", "list", "--format", "json"]);
        scopeProc.running = true;
    }

    function loadProfiles() {
        profileProc.command = [samu(), "profile", "list", "--format", "json"];
        profileProc.running = true;
    }

    function hasVariant(name) {
        return root.variants.some(v => v.profile === name);
    }

    Component.onCompleted: {
        Qt.callLater(loadScopes);
        Qt.callLater(loadProfiles);
    }

    Process {
        id: profileProc
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: code => {
            if (code !== 0) {
                root.profileError = String(stderr.text).trim() || "samu profile list: exit " + code;
                return;
            }
            try {
                root.profiles = JSON.parse(String(stdout.text).trim() || "[]");
                root.profileOptions = root.profileOptions.slice(0, 1).concat(
                    root.profiles.map(p => ({
                        label: p.name + " (" + p.account + ", " + (p.kind === "local" ? "lokal" : "online") + ")",
                        value: p.name
                    })));
                root.profileError = "";
            } catch (e) {
                root.profileError = "JSON: " + e.message;
            }
        }
    }

    Process {
        id: scopeProc
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: code => {
            if (code !== 0) {
                root.scopeError = String(stderr.text).trim() || "samu scope list: exit " + code;
                return;
            }
            try {
                const scopes = JSON.parse(String(stdout.text).trim() || "[]");
                root.scopeOptions = root.scopeOptions.slice(0, 2).concat(
                    scopes.map(s => ({ label: s.title + (s.mode === "except" ? " (außer)" : ""), value: s.id })));
                root.scopeError = "";
            } catch (e) {
                root.scopeError = "JSON: " + e.message;
            }
        }
    }

    StyledText {
        text: "samudo"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Forecast, Uhr und Erfassen über die samu-Kommandozeile, mit deiner eigenen Sitzung (samu login). Aktualisiert sich live über samu events."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StyledRect { width: parent.width; height: 1; color: Theme.surfaceVariant }

    SelectionSetting {
        settingKey: "scope"
        label: "Scope"
        description: root.scopeError ? "Scopes nicht gelesen: " + root.scopeError
            : "Durch welchen Scope der Forecast schaut. Erfassen folgt dem Scope dieses Geräts."
        options: root.scopeOptions
        defaultValue: "device"
    }

    StringSetting {
        settingKey: "samuCommand"
        label: "samu-Befehl"
        description: "Name oder Pfad der samu-Kommandozeile"
        placeholder: "samu"
        defaultValue: "samu"
    }

    SelectionSetting {
        settingKey: "profile"
        label: "Profil"
        description: root.profileError ? "Profile nicht gelesen: " + root.profileError
            : "--profile: welches Konto dieses Rechners das Widget zeigt (ADR 0086). Ein Wechsel lädt neu; den Scope danach neu wählen."
        options: root.profileOptions
        defaultValue: ""
        onValueChanged: Qt.callLater(root.loadScopes)
    }

    StyledRect { width: parent.width; height: 1; color: Theme.surfaceVariant }

    StyledText {
        text: "Ein Widget je Profil"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Legt für ein Profil ein eigenes Widget an, das unter Leiste › Widget hinzufügen als „samudo - <Profil>“ erscheint. Es folgt dem Scope, den samu scope use für das Profil gewählt hat; die übrigen Einstellungen oben gelten für alle."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    Repeater {
        model: root.profiles

        Row {
            required property var modelData
            width: root.width
            spacing: Theme.spacingM

            StyledText {
                width: parent.width - variantButton.width - Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.name + " — " + modelData.account + (modelData.kind === "local" ? ", lokal" : ", online")
                    + (modelData.running ? "" : " (Dienst läuft nicht)")
                color: Theme.surfaceText
                elide: Text.ElideRight
            }

            DC.DButton {
                id: variantButton
                readonly property var existing: root.variants.find(v => v.profile === modelData.name)
                text: existing ? "Entfernen" : "Widget anlegen"
                iconName: existing ? "delete" : "add"
                onClicked: {
                    if (existing) {
                        root.removeVariant(existing.id);
                        ToastService.showInfo("samudo", "Widget für " + modelData.name + " entfernt");
                    } else {
                        root.createVariant(modelData.name, { profile: modelData.name, icon: "task_alt" });
                        ToastService.showInfo("samudo", "Widget für " + modelData.name + " angelegt: Leiste › Widget hinzufügen");
                    }
                }
            }
        }
    }

    StringSetting {
        settingKey: "openCommand"
        label: "Öffnen mit (optional)"
        description: "Shell-Befehl für ⏎ auf einer Aufgabe, {id} wird ersetzt. Leer: samu open-uri samu:{id} (Web-UI)."
        placeholder: "samu open-uri samu:{id}"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "refreshMinutes"
        label: "Rückfall-Aktualisierung (Minuten)"
        description: "Neu laden ohne Ereignis, etwa nach Mitternacht oder wenn samu events abreißt"
        placeholder: "15"
        defaultValue: "15"
    }

    ToggleSetting {
        settingKey: "showLater"
        label: "„Später“ zeigen"
        description: "Auch was nach den Tagen des Forecasts kommt"
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "showClockTitle"
        label: "Aufgabe der laufenden Uhr in der Leiste"
        description: "Sonst nur die Zeit"
        defaultValue: true
    }
}
