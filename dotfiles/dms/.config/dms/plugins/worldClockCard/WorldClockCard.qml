import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins
import qs.Modules.DDash

DashCardComponent {
    id: root

    // Zone slots come from the card's Options sheet (zone1..zone6 in plugin.json); slot order is display order
    readonly property int slotCount: 6
    readonly property var zones: {
        const list = [];
        for (let i = 1; i <= slotCount; i++) {
            const tz = options["zone" + i];
            if (typeof tz === "string" && tz !== "")
                list.push({
                    "timezone": tz
                });
        }
        return list;
    }
    // timezone -> { offset: minutes east of UTC, abbr } or null when the zone is unknown
    property var offsets: ({})

    readonly property bool wide: width >= DashMetrics.gridRowUnit * 2
    // Strip layout: zones side by side when the card is much wider than tall
    readonly property bool strip: width >= height * 3 && zones.length > 1
    readonly property real rowHeight: Theme.fontSizeXLarge * 1.9
    readonly property int maxRows: Math.max(1, Math.floor(height / rowHeight))
    readonly property int maxColumns: Math.max(1, Math.floor(width / (DashMetrics.gridRowUnit * 1.4)))
    readonly property var shownZones: zones.slice(0, strip ? maxColumns : maxRows)
    readonly property bool single: !strip && shownZones.length === 1
    readonly property bool use24: SettingsData.use24HourClock

    tone: options.tone ?? ""

    onZonesChanged: refreshOffsets()
    onLiveChanged: if (live) refreshOffsets()

    function refreshOffsets() {
        if (zones.length === 0 || offsetProc.running)
            return;
        offsetProc.queried = zones.map(z => z.timezone.trim());
        offsetProc.command = ["sh", "-c", 'for z; do if [ -f "/usr/share/zoneinfo/$z" ]; then TZ="$z" date +"%z %Z"; else echo invalid; fi; done', "sh"].concat(offsetProc.queried);
        offsetProc.running = true;
    }

    function parseOffset(line) {
        const m = /^([+-])(\d{2})(\d{2}) (\S+)$/.exec(line.trim());
        if (!m)
            return null;
        const minutes = parseInt(m[2]) * 60 + parseInt(m[3]);
        return {
            "offset": m[1] === "-" ? -minutes : minutes,
            "abbr": /^[+-]\d+$/.test(m[4]) ? "" : m[4]
        };
    }

    function zoneLabel(z) {
        const parts = z.timezone.trim().split("/");
        return parts[parts.length - 1].replace(/_/g, " ");
    }

    // A Date whose UTC fields read as the wall-clock time in the zone
    function shifted(now, info) {
        return new Date(now.getTime() + info.offset * 60000);
    }

    function formatTime(d) {
        const h = d.getUTCHours();
        const mm = String(d.getUTCMinutes()).padStart(2, "0");
        if (use24)
            return String(h).padStart(2, "0") + ":" + mm;
        return ((h + 11) % 12 + 1) + ":" + mm + (h < 12 ? " AM" : " PM");
    }

    function dayText(now, d) {
        const diff = Math.round((Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) - Date.UTC(now.getFullYear(), now.getMonth(), now.getDate())) / 86400000);
        if (diff === 1)
            return "Tomorrow";
        if (diff === -1)
            return "Yesterday";
        return "Today";
    }

    function offsetText(now, info) {
        const delta = info.offset + now.getTimezoneOffset();
        if (delta === 0)
            return "Same time";
        const abs = Math.abs(delta);
        const h = Math.floor(abs / 60);
        const m = abs % 60;
        return (delta > 0 ? "+" : "−") + h + (m ? ":" + String(m).padStart(2, "0") : "") + "h";
    }

    function detailText(now, info) {
        const parts = [dayText(now, shifted(now, info))];
        if (wide && info.abbr)
            parts.push(info.abbr);
        if (options.showOffset !== false)
            parts.push(offsetText(now, info));
        return parts.join(" · ");
    }

    SystemClock {
        id: clock
        enabled: root.live
        precision: SystemClock.Minutes
        // Pick up DST transitions without polling
        onHoursChanged: root.refreshOffsets()
    }

    Process {
        id: offsetProc

        property var queried: []

        // Zones changed while a lookup was in flight
        onExited: if (queried.join() !== root.zones.map(z => z.timezone.trim()).join()) root.refreshOffsets()

        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                const next = {};
                offsetProc.queried.forEach((tz, i) => next[tz] = root.parseOffset(lines[i] ?? ""));
                root.offsets = next;
            }
        }
    }

    StyledText {
        anchors.centerIn: parent
        width: parent.width
        visible: root.zones.length === 0
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: "Pick time zones in this card's Options (edit mode)"
        font.pixelSize: Theme.fontSizeSmall
        color: root.mutedColor
    }

    Row {
        anchors.fill: parent
        visible: root.strip
        spacing: Theme.spacingM

        Repeater {
            model: root.strip ? root.shownZones : []

            Column {
                id: cell

                required property var modelData
                required property int index
                readonly property var info: root.offsets[modelData.timezone.trim()]
                readonly property bool known: info !== null && info !== undefined

                width: (root.width - (root.shownZones.length - 1) * Theme.spacingM) / root.shownZones.length
                anchors.verticalCenter: parent.verticalCenter

                StyledText {
                    width: parent.width
                    text: root.zoneLabel(cell.modelData)
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Theme.fontWeightMedium
                    color: root.contentColor
                    elide: Text.ElideRight
                }

                NumericText {
                    isMonospace: false
                    text: cell.known ? root.formatTime(root.shifted(clock.date, cell.info)) : "--:--"
                    font.pixelSize: Theme.fontSizeXXLarge
                    font.weight: Theme.fontWeightMedium
                    color: root.accentColor
                }

                StyledText {
                    width: parent.width
                    text: cell.known ? root.detailText(clock.date, cell.info) : (root.offsets.hasOwnProperty(cell.modelData.timezone.trim()) ? "Unknown time zone" : "")
                    font.pixelSize: Theme.fontSizeSmall
                    color: root.mutedColor
                    elide: Text.ElideRight
                }
            }
        }
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.single ? 0 : Math.max(0, (root.height - root.shownZones.length * root.rowHeight) / Math.max(1, root.shownZones.length - 1))
        visible: root.zones.length > 0 && !root.strip

        Repeater {
            model: root.strip ? [] : root.shownZones

            Item {
                id: row

                required property var modelData
                readonly property var info: root.offsets[modelData.timezone.trim()]
                readonly property bool known: info !== null && info !== undefined
                readonly property var local: known ? root.shifted(clock.date, info) : null

                width: parent.width
                height: root.single ? root.height : root.rowHeight

                Column {
                    anchors.left: parent.left
                    anchors.right: timeText.left
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter

                    StyledText {
                        width: parent.width
                        text: root.zoneLabel(row.modelData)
                        font.pixelSize: root.single ? Theme.fontSizeMedium : Theme.fontSizeSmall
                        font.weight: Theme.fontWeightMedium
                        color: root.contentColor
                        elide: Text.ElideRight
                    }

                    StyledText {
                        width: parent.width
                        text: row.known ? root.detailText(clock.date, row.info) : (root.offsets.hasOwnProperty(row.modelData.timezone.trim()) ? "Unknown time zone" : "")
                        font.pixelSize: Theme.fontSizeSmall
                        color: root.mutedColor
                        elide: Text.ElideRight
                    }
                }

                NumericText {
                    id: timeText

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    isMonospace: false
                    text: row.known ? root.formatTime(row.local) : "--:--"
                    font.pixelSize: root.single ? (root.wide ? Theme.fontSizeDisplay : Theme.fontSizeXXLarge) : Theme.fontSizeXLarge
                    font.weight: Theme.fontWeightMedium
                    color: root.accentColor
                }
            }
        }
    }
}
