pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.DDash
import qs.Modules.Plugins
import "/usr/share/quickshell/dms/Common/DateOnly.js" as DateOnly

// Copy of the stock dash CalendarOverviewCard (dms 2.0.0) with an agenda view,
// toggled by a header button and remembered across sessions
DashCardComponent {
    id: root

    opensTab: false
    property bool showEventDetails: false
    property bool agenda: false
    property date agendaStart: systemClock.date
    readonly property int agendaDays: options.agendaDays ?? 14
    // [{ date, events }] for each day in the agenda window that has events
    property var agendaGroups: []
    property date selectedDate: systemClock.date
    property var selectedDateEvents: []
    readonly property bool hasEvents: selectedDateEvents && selectedDateEvents.length > 0
    readonly property bool canCreate: CalendarService.canCreateEvents

    property int eventsRevision: 0

    signal detailRequested(var eventData)
    signal editorRequested(var eventData, var initialDate)

    focusTarget: root
    blocksTabNavigation: showEventDetails
    activeFocusOnTab: interactive

    pad: Theme.spacingS

    function weekStartQt() {
        if (SettingsData.firstDayOfWeek >= 7 || SettingsData.firstDayOfWeek < 0)
            return Qt.locale().firstDayOfWeek;
        return SettingsData.firstDayOfWeek;
    }

    function weekStartJs() {
        return weekStartQt() % 7;
    }

    function startOfWeek(dateOnly) {
        const diff = (dateOnly.dayOfWeek() - weekStartJs() + 7) % 7;
        return dateOnly.addDays(-diff);
    }

    function endOfWeek(dateOnly) {
        const add = (weekStartJs() + 6 - dateOnly.dayOfWeek() + 7) % 7;
        return dateOnly.addDays(add);
    }

    function getWeekNumber(dateObj) {
        const weekStartDay = startOfWeek(DateOnly.fromDate(dateObj));
        const isoWeeks = weekStartJs() === 1;
        const yearTarget = weekStartDay.addDays(isoWeeks ? 3 : 6);
        const week1Start = startOfWeek(DateOnly.of(yearTarget.year, 0, isoWeeks ? 4 : 1));
        const diffDays = week1Start.daysUntil(weekStartDay);
        return Math.floor(diffDays / 7) + 1;
    }

    function eventColorsFor(date) {
        if (!CalendarService.calendarAvailable || !CalendarService.hasEventsForDate(date))
            return [];
        return CalendarService.getEventsForDate(date).map(event => event.color?.length ? event.color : Theme.primary);
    }

    function updateSelectedDateEvents() {
        const events = CalendarService.calendarAvailable ? CalendarService.getEventsForDate(selectedDate) : [];
        if (JSON.stringify(events) === JSON.stringify(selectedDateEvents))
            return;
        selectedDateEvents = events;
    }

    function loadEventsForMonth() {
        if (!CalendarService.calendarAvailable)
            return;
        const year = calendarGrid.displayDate.getFullYear();
        const month = calendarGrid.displayDate.getMonth();
        const startDate = startOfWeek(DateOnly.firstOfMonth(year, month)).addDays(-7);
        const endDate = endOfWeek(DateOnly.lastOfMonth(year, month)).addDays(7);
        CalendarService.loadEvents(startDate.toDate(), endDate.toDate());
    }

    function updateAgendaGroups() {
        const groups = [];
        if (CalendarService.calendarAvailable) {
            const first = DateOnly.fromDate(agendaStart);
            for (let i = 0; i < agendaDays; i++) {
                const date = first.addDays(i).toDate();
                const events = CalendarService.getEventsForDate(date);
                if (events.length > 0)
                    groups.push({
                        "date": date,
                        "events": events
                    });
            }
        }
        if (JSON.stringify(groups) === JSON.stringify(agendaGroups))
            return;
        agendaGroups = groups;
    }

    function loadEventsForAgenda() {
        if (!CalendarService.calendarAvailable)
            return;
        const first = DateOnly.fromDate(agendaStart);
        CalendarService.loadEvents(first.toDate(), first.addDays(agendaDays).toDate());
    }

    function loadEventsForView() {
        if (agenda)
            loadEventsForAgenda();
        else
            loadEventsForMonth();
    }

    function shiftAgenda(delta) {
        agendaStart = DateOnly.fromDate(agendaStart).addDays(delta * agendaDays).toDate();
        loadEventsForAgenda();
    }

    function dayLabel(date) {
        const offset = DateOnly.fromDate(systemClock.date).daysUntil(DateOnly.fromDate(date));
        const dateStr = date.toLocaleDateString(I18n.locale(), "ddd, MMM d");
        if (offset === 0)
            return I18n.tr("Today") + " · " + dateStr;
        if (offset === 1)
            return I18n.tr("Tomorrow") + " · " + dateStr;
        return dateStr;
    }

    function goToToday() {
        const now = systemClock.date;
        if (agenda) {
            agendaStart = now;
            loadEventsForAgenda();
            return;
        }
        calendarGrid.selectedDate = now;
        calendarGrid.displayDate = now;
        root.selectedDate = now;
        loadEventsForMonth();
    }

    function selectDay(dayDate) {
        calendarGrid.selectedDate = dayDate;
        root.selectedDate = dayDate;
    }

    function moveSelection(days) {
        const moved = DateOnly.fromDate(calendarGrid.selectedDate).addDays(days);
        const d = moved.toDate();
        selectDay(d);
        if (moved.month === calendarGrid.displayDate.getMonth() && moved.year === calendarGrid.displayDate.getFullYear())
            return;
        calendarGrid.displayDate = d;
        loadEventsForMonth();
    }

    function shiftMonth(delta) {
        calendarGrid.displayDate = DateOnly.fromDate(calendarGrid.displayDate).addMonths(delta).toDate();
        loadEventsForMonth();
    }

    function openEditor(eventData) {
        root.editorRequested(eventData, root.selectedDate);
    }

    function handleKeyEvent(event) {
        if (!interactive)
            return false;
        if (showEventDetails) {
            if (event.key !== Qt.Key_Escape)
                return false;
            showEventDetails = false;
            return true;
        }
        if (agenda) {
            switch (event.key) {
            case Qt.Key_PageUp:
                shiftAgenda(-1);
                return true;
            case Qt.Key_PageDown:
                shiftAgenda(1);
                return true;
            case Qt.Key_T:
                goToToday();
                return true;
            case Qt.Key_A:
                agenda = false;
                return true;
            }
            return false;
        }
        switch (event.key) {
        case Qt.Key_A:
            agenda = true;
            return true;
        case Qt.Key_Left:
        case Qt.Key_H:
            moveSelection(I18n.isRtl ? 1 : -1);
            return true;
        case Qt.Key_Right:
        case Qt.Key_L:
            moveSelection(I18n.isRtl ? -1 : 1);
            return true;
        case Qt.Key_Up:
        case Qt.Key_K:
            moveSelection(-7);
            return true;
        case Qt.Key_Down:
        case Qt.Key_J:
            moveSelection(7);
            return true;
        case Qt.Key_PageUp:
            shiftMonth(-1);
            return true;
        case Qt.Key_PageDown:
            shiftMonth(1);
            return true;
        case Qt.Key_T:
            goToToday();
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            root.selectedDate = calendarGrid.selectedDate;
            showEventDetails = true;
            return true;
        }
        return false;
    }

    onSelectedDateChanged: updateSelectedDateEvents()
    onAgendaStartChanged: updateAgendaGroups()
    onAgendaDaysChanged: {
        updateAgendaGroups();
        if (agenda)
            loadEventsForAgenda();
    }

    onAgendaChanged: {
        setData("agenda", agenda);
        showEventDetails = false;
        loadEventsForView();
    }

    onShowEventDetailsChanged: {
        if (showEventDetails) {
            taskInput.forceActiveFocus();
            return;
        }
        navFocusRequested();
    }

    // pluginService is injected after creation, so the saved view can only be read then
    onPluginServiceChanged: agenda = getData("agenda", false) === true

    Component.onCompleted: {
        loadEventsForView();
        updateSelectedDateEvents();
        updateAgendaGroups();
    }

    Connections {
        target: CalendarService

        function onEventsByDateChanged() {
            root.eventsRevision++;
            root.updateSelectedDateEvents();
            root.updateAgendaGroups();
        }

        function onCalendarAvailableChanged() {
            if (CalendarService.calendarAvailable)
                root.loadEventsForView();
            root.updateSelectedDateEvents();
            root.updateAgendaGroups();
        }
    }

    Rectangle {
        id: dankWarning

        readonly property bool showWarning: CalendarService.dankNeedsLaunch ?? false

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        visible: showWarning
        height: showWarning ? Math.max(Theme.buttonHeightXS, warningRow.implicitHeight) + Theme.spacingXS * 2 : 0
        radius: Theme.cornerRadiusS
        color: Theme.foregroundColor(Theme.chipSurface, Theme.isFloatingWindow(root))

        Row {
            id: warningRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Theme.spacingS
            anchors.rightMargin: Theme.spacingS
            spacing: Theme.spacingS

            DIcon {
                name: "warning"
                size: Theme.iconSizeSmall
                color: Theme.warning
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                width: parent.width - Theme.iconSizeSmall - Theme.spacingS - (launchButton.visible ? launchButton.width + Theme.spacingS : 0)
                anchors.verticalCenter: parent.verticalCenter
                text: CalendarService.dankBinaryExists ? I18n.tr("Dux Calendar isn't running") : I18n.tr("Dux Calendar isn't installed")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                wrapMode: Text.Wrap
            }

            DButton {
                id: launchButton
                anchors.verticalCenter: parent.verticalCenter
                visible: CalendarService.dankBinaryExists
                text: I18n.tr("Launch")
                buttonHeight: Theme.buttonHeightXS
                backgroundColor: Theme.primary
                textColor: Theme.onPrimary
                onClicked: CalendarService.launchDankCalendar()
            }
        }
    }

    Item {
        id: header

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: dankWarning.bottom
        anchors.topMargin: dankWarning.visible ? Theme.spacingS : 0
        height: DashMetrics.monthNavSize

        Item {
            anchors.fill: parent
            visible: !root.showEventDetails

            NavButton {
                anchors.left: parent.left
                iconName: I18n.isRtl ? "chevron_right" : "chevron_left"
                iconColor: Theme.onSurfaceVariant
                Accessible.name: I18n.tr("Previous")
                onClicked: root.agenda ? root.shiftAgenda(-1) : root.shiftMonth(-1)
            }

            StyledText {
                anchors.centerIn: parent
                width: parent.width - DashMetrics.monthNavSize * 6
                text: {
                    if (!root.agenda)
                        return calendarGrid.displayDate.toLocaleDateString(I18n.locale(), "MMMM yyyy");
                    const first = DateOnly.fromDate(root.agendaStart);
                    const last = first.addDays(root.agendaDays - 1).toDate();
                    return root.agendaStart.toLocaleDateString(I18n.locale(), "MMM d") + " – " + last.toLocaleDateString(I18n.locale(), "MMM d");
                }
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            Row {
                anchors.right: parent.right

                NavButton {
                    iconName: root.agenda ? "calendar_month" : "view_agenda"
                    iconColor: Theme.onSurfaceVariant
                    Accessible.name: root.agenda ? I18n.tr("Month view") : I18n.tr("Agenda view")
                    onClicked: root.agenda = !root.agenda
                }

                NavButton {
                    readonly property bool isToday: {
                        const now = systemClock.date;
                        if (root.agenda)
                            return root.agendaStart.toDateString() === now.toDateString();
                        const disp = calendarGrid.displayDate;
                        const sel = calendarGrid.selectedDate;
                        return disp.getFullYear() === now.getFullYear() && disp.getMonth() === now.getMonth() && sel.toDateString() === now.toDateString();
                    }

                    iconName: "today"
                    enabled: !isToday
                    Accessible.name: I18n.tr("Today")
                    onClicked: root.goToToday()
                }

                NavButton {
                    iconName: I18n.isRtl ? "chevron_left" : "chevron_right"
                    iconColor: Theme.onSurfaceVariant
                    Accessible.name: I18n.tr("Next")
                    onClicked: root.agenda ? root.shiftAgenda(1) : root.shiftMonth(1)
                }
            }
        }

        Item {
            anchors.fill: parent
            visible: root.showEventDetails

            NavButton {
                anchors.left: parent.left
                iconName: I18n.isRtl ? "arrow_forward" : "arrow_back"
                onClicked: root.showEventDetails = false
            }

            StyledText {
                anchors.centerIn: parent
                width: parent.width - DashMetrics.monthNavSize * 2 - Theme.spacingS * 2
                text: {
                    const dateStr = Qt.formatDate(root.selectedDate, "MMM d");
                    if (!root.hasEvents)
                        return dateStr;
                    const count = root.selectedDateEvents.length;
                    const eventCount = count === 1 ? I18n.tr("1 task", "task count next to a date") : I18n.tr("%1 tasks", "task count next to a date, %1 is the number of tasks").arg(count);
                    return dateStr + " • " + eventCount;
                }
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            NavButton {
                anchors.right: parent.right
                iconName: "add"
                visible: root.canCreate
                Accessible.name: I18n.tr("New event")
                onClicked: root.openEditor(null)
            }
        }
    }

    Item {
        id: body

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.topMargin: Theme.spacingS
        anchors.bottom: parent.bottom

        DMonthGrid {
            id: calendarGrid

            anchors.fill: parent
            visible: !root.showEventDetails && !root.agenda
            displayDate: systemClock.date
            selectedDate: systemClock.date
            today: systemClock.date
            firstDayOfWeek: root.weekStartJs()
            dayNames: {
                const days = [];
                const qtFirst = root.weekStartQt();
                for (let i = 0; i < 7; ++i)
                    days.push(I18n.locale().dayName(((qtFirst - 1 + i) % 7) + 1, Locale.ShortFormat));
                return days;
            }
            showWeekNumbers: SettingsData.showWeekNumber
            highlightWeekends: root.options.weekends === true
            weekColumnWidth: DashMetrics.weekColumnWidth
            weekNumberFor: date => root.getWeekNumber(date)
            dotColorsFor: date => root.eventColorsFor(date)
            revision: root.eventsRevision
            interactive: root.interactive
            onDayClicked: date => {
                root.forceActiveFocus(Qt.MouseFocusReason);
                root.selectDay(date);
                root.showEventDetails = true;
            }
        }

        DFlickable {
            anchors.fill: parent
            visible: root.agenda && !root.showEventDetails
            showScrollBar: false
            clip: true
            contentWidth: width
            contentHeight: agendaColumn.height

            Column {
                id: agendaColumn
                width: parent.width
                spacing: Theme.spacingS

                StyledText {
                    width: parent.width
                    visible: root.agendaGroups.length === 0
                    topPadding: Theme.spacingL
                    text: I18n.tr("No events")
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.onSurfaceVariant
                    horizontalAlignment: Text.AlignHCenter
                }

                Repeater {
                    model: root.agendaGroups

                    delegate: Column {
                        id: dayGroup

                        required property var modelData

                        width: agendaColumn.width
                        spacing: Theme.groupedListGap

                        StyledText {
                            width: parent.width
                            leftPadding: Theme.spacingXS
                            text: root.dayLabel(dayGroup.modelData.date)
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Theme.fontWeightMedium
                            color: Theme.primary
                            elide: Text.ElideRight
                        }

                        Repeater {
                            model: dayGroup.modelData.events

                            delegate: AgendaRow {}
                        }
                    }
                }
            }
        }

        Column {
            anchors.fill: parent
            visible: root.showEventDetails
            spacing: Theme.spacingS

            DFlickable {
                id: flickableArea
                showScrollBar: false
                width: parent.width
                height: parent.height - taskInput.height - parent.spacing
                clip: true
                contentWidth: width
                contentHeight: listViewContainer.height
                interactive: listViewContainer.draggedItem === null

                Item {
                    id: listViewContainer

                    property var draggedItem: null
                    property bool orderChanged: false

                    width: parent.width
                    height: 0

                    function sortedItems() {
                        const items = [];
                        for (let i = 0; i < repeater.count; i++) {
                            const item = repeater.itemAt(i);
                            if (item)
                                items.push(item);
                        }
                        items.sort((a, b) => a.visualIndex - b.visualIndex);
                        return items;
                    }

                    function resetAndLayout() {
                        for (let i = 0; i < repeater.count; i++) {
                            const item = repeater.itemAt(i);
                            if (!item)
                                continue;
                            item.visualIndex = i;
                            item.isDragging = false;
                            item.isEditing = false;
                        }
                        updateLayout();
                    }

                    function updateLayout() {
                        const items = sortedItems();
                        let currentY = 0;
                        for (let i = 0; i < items.length; i++) {
                            if (!items[i].isDragging)
                                items[i].y = currentY;
                            currentY += items[i].height + Theme.groupedListGap;
                        }
                        listViewContainer.height = Math.max(0, currentY - Theme.groupedListGap);
                    }

                    function checkAndReorder(dragged) {
                        const items = sortedItems();
                        let swapped = false;

                        const targetY = index => {
                            let y = 0;
                            for (let i = 0; i < index; i++)
                                y += items[i].height + Theme.groupedListGap;
                            return y;
                        };

                        for (; ; ) {
                            const draggedIdx = items.indexOf(dragged);
                            if (draggedIdx < 0)
                                break;
                            let neighbour = null;
                            let neighbourIdx = -1;
                            if (draggedIdx > 0 && dragged.y < targetY(draggedIdx - 1) + items[draggedIdx - 1].height / 2)
                                neighbourIdx = draggedIdx - 1;
                            else if (draggedIdx < items.length - 1 && dragged.y + dragged.height > targetY(draggedIdx + 1) + items[draggedIdx + 1].height / 2)
                                neighbourIdx = draggedIdx + 1;
                            if (neighbourIdx < 0)
                                break;
                            neighbour = items[neighbourIdx];
                            const temp = dragged.visualIndex;
                            dragged.visualIndex = neighbour.visualIndex;
                            neighbour.visualIndex = temp;
                            items[draggedIdx] = neighbour;
                            items[neighbourIdx] = dragged;
                            listViewContainer.orderChanged = true;
                            swapped = true;
                        }

                        if (swapped)
                            updateLayout();
                    }

                    function saveNewOrder() {
                        if (!orderChanged)
                            return;
                        const orderedIds = sortedItems().map(item => item.taskId).filter(id => id.startsWith("task_")).map(id => id.replace("task_", ""));
                        if (orderedIds.length > 0)
                            CalendarService.reorderTasksForDate(root.selectedDate, orderedIds);
                        orderChanged = false;
                    }

                    Repeater {
                        id: repeater
                        model: root.selectedDateEvents

                        onModelChanged: Qt.callLater(listViewContainer.resetAndLayout)

                        delegate: EventRow {}
                    }
                }
            }

            DTextField {
                id: taskInput
                width: parent.width
                height: DashMetrics.taskInputHeight
                cornerRadius: Theme.fullRadius(width, height)
                font.pixelSize: Theme.fontSizeSmall
                leftIconName: "add_task"
                leftIconSize: Theme.iconSizeSmall
                placeholderText: I18n.tr("Add a task...", "placeholder in the new-task input field")
                hidePlaceholderOnFocus: false
                keyForwardTargets: [taskKeyHandler]

                onAccepted: {
                    const txt = text.trim();
                    if (txt === "")
                        return;
                    CalendarService.addTaskForDate(root.selectedDate, txt);
                    text = "";
                }

                Item {
                    id: taskKeyHandler

                    Keys.onEscapePressed: event => {
                        root.showEventDetails = false;
                        event.accepted = true;
                    }
                }
            }
        }
    }

    component NavButton: DActionButton {
        buttonSize: DashMetrics.monthNavSize
        iconSize: DashMetrics.monthNavIconSize
        iconColor: Theme.primary
    }

    // Read-only version of EventRow: no drag, edit or delete, clicking behaves the same
    component AgendaRow: Rectangle {
        id: agendaItem

        required property var modelData

        readonly property string taskId: modelData?.id ?? ""
        readonly property bool isLocalTask: taskId.startsWith("task_")
        readonly property bool isTask: isLocalTask || taskId.startsWith("vtodo_")
        readonly property bool completed: isTask && !!modelData?.completed
        readonly property bool canModify: isLocalTask || (isTask && !!modelData && !modelData.readOnly)
        readonly property color baseAccent: (isLocalTask || !modelData?.color?.length) ? Theme.primary : modelData.color
        readonly property color accentColor: completed ? Theme.withAlpha(baseAccent, Theme.stateLayerDrag) : baseAccent

        width: parent ? parent.width : 0
        height: Math.max(DashMetrics.eventRowMinHeight, agendaContent.implicitHeight + Theme.spacingS * 2)
        radius: Theme.cornerRadiusS
        color: Theme.foregroundColor(Theme.chipSurface, Theme.isFloatingWindow(root))
        activeFocusOnTab: !!modelData && root.interactive

        function activate() {
            if (isTask && canModify) {
                CalendarService.toggleTask(taskId);
                return;
            }
            root.detailRequested(modelData);
        }

        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Space:
            case Qt.Key_Return:
            case Qt.Key_Enter:
                activate();
                event.accepted = true;
                break;
            }
        }

        StateLayer {
            cornerRadius: agendaItem.radius
            stateColor: agendaItem.accentColor
            disabled: !agendaItem.modelData || !root.interactive
            onClicked: agendaItem.activate()
        }

        FocusRing {}

        Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            width: DashMetrics.eventAccentWidth
            height: parent.height - Theme.spacingM * 2
            radius: Theme.fullRadius(width, height)
            color: agendaItem.accentColor
        }

        Column {
            id: agendaContent

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Theme.spacingM + DashMetrics.eventAccentWidth + Theme.spacingM
            anchors.rightMargin: Theme.spacingS
            spacing: Theme.spacingXXS

            StyledText {
                width: parent.width
                text: agendaItem.modelData?.title ?? ""
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                font.strikeout: agendaItem.completed
                color: agendaItem.completed ? Theme.onSurfaceVariant : Theme.surfaceText
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            StyledText {
                width: parent.width
                text: {
                    const data = agendaItem.modelData;
                    if (!data)
                        return "";
                    const cal = data.calendar?.length ? " · " + data.calendar : "";
                    if (data.allDay)
                        return I18n.tr("All day", "calendar task with no specific time") + cal;
                    if (!data.start || !data.end)
                        return "";
                    const timeFormat = SettingsData.use24HourClock ? "HH:mm" : "h:mm AP";
                    const startTime = Qt.formatTime(data.start, timeFormat);
                    if (data.start.getTime() !== data.end.getTime())
                        return startTime + " – " + Qt.formatTime(data.end, timeFormat) + cal;
                    return startTime + cal;
                }
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.onSurfaceVariant
                elide: Text.ElideRight
                visible: text !== "" && !agendaItem.isLocalTask
            }
        }
    }

    component EventRow: Rectangle {
        id: taskItem

        required property int index
        required property var modelData

        property int visualIndex: index
        property bool isDragging: false
        property bool isEditing: false

        readonly property string taskId: modelData?.id ?? ""
        readonly property bool isLocalTask: taskId.startsWith("task_")
        readonly property bool isDankTask: taskId.startsWith("vtodo_")
        readonly property bool isTask: isLocalTask || isDankTask
        readonly property bool completed: isTask && !!modelData?.completed
        readonly property bool canModify: isLocalTask || (isDankTask && !!modelData && !modelData.readOnly)
        readonly property string quickUrl: {
            if (isTask || !modelData)
                return "";
            if (modelData.meetingUrl)
                return modelData.meetingUrl;
            const loc = (modelData.location || "").trim();
            if (/^https?:\/\/\S+$/i.test(loc))
                return loc;
            if (/^www\.\S+$/i.test(loc))
                return "https://" + loc;
            return modelData.url || "";
        }
        readonly property color baseAccent: (isLocalTask || !modelData?.color?.length) ? Theme.primary : modelData.color
        readonly property color accentColor: completed ? Theme.withAlpha(baseAccent, Theme.stateLayerDrag) : baseAccent
        readonly property real leadingWidth: Theme.spacingM + DashMetrics.eventAccentWidth + Theme.spacingM + (isLocalTask ? DashMetrics.eventActionSize + Theme.spacingXS : 0) + (isTask ? DashMetrics.eventActionSize + Theme.spacingXS : 0)
        readonly property real trailingWidth: {
            if (canModify)
                return DashMetrics.eventActionSize * 2 + Theme.spacingXS + Theme.spacingS * 2;
            if (quickUrl !== "")
                return DashMetrics.eventActionSize + Theme.spacingS * 2;
            return Theme.spacingS;
        }

        width: parent ? parent.width : 0
        height: Math.max(DashMetrics.eventRowMinHeight, eventContent.implicitHeight + Theme.spacingS * 2)
        radius: Theme.cornerRadiusS
        color: isDragging ? Theme.withAlpha(Theme.primary, Theme.stateLayerDrag) : Theme.foregroundColor(Theme.chipSurface, Theme.isFloatingWindow(root))
        z: isDragging ? 100 : visualIndex
        activeFocusOnTab: !!modelData && !isEditing && root.interactive

        function activate() {
            if (isTask && canModify) {
                CalendarService.toggleTask(taskId);
                return;
            }
            root.detailRequested(modelData);
        }

        Keys.onPressed: event => {
            if (!activeFocusOnTab)
                return;
            switch (event.key) {
            case Qt.Key_Space:
            case Qt.Key_Return:
            case Qt.Key_Enter:
                activate();
                event.accepted = true;
                break;
            }
        }

        StateLayer {
            cornerRadius: taskItem.radius
            stateColor: taskItem.accentColor
            disabled: !taskItem.modelData || taskItem.isEditing || !root.interactive
            onClicked: taskItem.activate()
        }

        FocusRing {}

        onIndexChanged: visualIndex = index

        onYChanged: {
            if (isDragging)
                listViewContainer.checkAndReorder(taskItem);
        }

        Behavior on y {
            enabled: !taskItem.isDragging && DashMetrics.animationsEnabled
            NumberAnimation {
                duration: Theme.expressiveDurations.expressiveFastSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.standard
            }
        }

        Component.onCompleted: {
            visualIndex = index;
            listViewContainer.updateLayout();
        }

        onHeightChanged: listViewContainer.updateLayout()

        onIsEditingChanged: {
            if (!isEditing)
                return;
            editInput.forceActiveFocus();
            editInput.selectAll();
        }

        function commitEdit() {
            const txt = editInput.text.trim();
            if (txt !== "" && taskItem.taskId !== "")
                CalendarService.editTask(taskItem.taskId, txt);
            taskItem.isEditing = false;
        }

        Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            width: DashMetrics.eventAccentWidth
            height: parent.height - Theme.spacingM * 2
            radius: Theme.fullRadius(width, height)
            color: taskItem.accentColor
        }

        DIcon {
            id: dragHandle
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingM + DashMetrics.eventAccentWidth + Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            name: "drag_indicator"
            size: DashMetrics.eventActionIconSize
            color: dragMouseArea.containsMouse ? Theme.primary : Theme.onSurfaceVariant
            visible: taskItem.isLocalTask && !taskItem.isEditing

            MouseArea {
                id: dragMouseArea
                anchors.fill: parent
                anchors.margins: -Theme.spacingS
                hoverEnabled: true
                cursorShape: Qt.SizeAllCursor
                preventStealing: true
                drag.target: taskItem
                drag.axis: Drag.YAxis
                drag.minimumY: 0
                drag.maximumY: listViewContainer.height - taskItem.height

                onPressed: {
                    taskItem.isDragging = true;
                    listViewContainer.orderChanged = false;
                    listViewContainer.draggedItem = taskItem;
                }

                onReleased: {
                    taskItem.isDragging = false;
                    listViewContainer.draggedItem = null;
                    if (listViewContainer.orderChanged)
                        listViewContainer.saveNewOrder();
                    else
                        listViewContainer.updateLayout();
                }

                onCanceled: {
                    taskItem.isDragging = false;
                    listViewContainer.draggedItem = null;
                    listViewContainer.resetAndLayout();
                }
            }
        }

        DActionButton {
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingM + DashMetrics.eventAccentWidth + Theme.spacingM + (taskItem.isLocalTask && !taskItem.isEditing ? DashMetrics.eventActionSize + Theme.spacingXS : 0)
            anchors.verticalCenter: parent.verticalCenter
            buttonSize: DashMetrics.eventActionSize
            iconSize: DashMetrics.eventActionIconSize
            iconName: taskItem.completed ? "check_box" : "check_box_outline_blank"
            Accessible.name: taskItem.completed ? I18n.tr("Mark incomplete") : I18n.tr("Mark complete")
            iconColor: taskItem.completed ? Theme.primary : Theme.onSurfaceVariant
            visible: taskItem.isTask
            enabled: taskItem.canModify && !taskItem.isEditing
            onClicked: CalendarService.toggleTask(taskItem.taskId)
        }

        Column {
            id: eventContent

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: taskItem.leadingWidth
            anchors.rightMargin: taskItem.trailingWidth
            spacing: Theme.spacingXXS
            visible: !taskItem.isEditing

            StyledText {
                width: parent.width
                text: taskItem.modelData?.title ?? ""
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: taskItem.completed ? Theme.onSurfaceVariant : Theme.surfaceText
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            StyledText {
                width: parent.width
                text: {
                    const data = taskItem.modelData;
                    if (!data)
                        return "";
                    const cal = data.calendar?.length ? " · " + data.calendar : "";
                    if (data.allDay)
                        return I18n.tr("All day", "calendar task with no specific time") + cal;
                    if (!data.start || !data.end)
                        return "";
                    const timeFormat = SettingsData.use24HourClock ? "HH:mm" : "h:mm AP";
                    const startTime = Qt.formatTime(data.start, timeFormat);
                    if (data.start.getTime() !== data.end.getTime())
                        return startTime + " – " + Qt.formatTime(data.end, timeFormat) + cal;
                    return startTime + cal;
                }
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.onSurfaceVariant
                visible: text !== "" && !taskItem.isLocalTask
            }
        }

        DTextField {
            id: editInput
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: taskItem.leadingWidth
            anchors.rightMargin: taskItem.trailingWidth
            anchors.verticalCenter: parent.verticalCenter
            height: DashMetrics.eventActionSize
            visible: taskItem.isEditing
            font.pixelSize: Theme.fontSizeSmall
            backgroundColor: "transparent"
            borderWidth: 0
            focusedBorderWidth: 0
            topPadding: 0
            bottomPadding: 0
            text: taskItem.modelData?.title ?? ""
            keyForwardTargets: [editKeyHandler]
            onAccepted: taskItem.commitEdit()

            Item {
                id: editKeyHandler

                Keys.onEscapePressed: event => {
                    taskItem.isEditing = false;
                    event.accepted = true;
                }
            }
        }

        DActionButton {
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            buttonSize: DashMetrics.eventActionSize
            iconSize: DashMetrics.eventActionIconSize
            iconName: taskItem.modelData?.meetingUrl ? "videocam" : "link"
            iconColor: Theme.primary
            visible: taskItem.quickUrl !== "" && !taskItem.canModify
            tooltipText: taskItem.quickUrl
            tooltipSide: "left"
            onClicked: Qt.openUrlExternally(taskItem.quickUrl)
        }

        DActionButton {
            id: deleteButton
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            buttonSize: DashMetrics.eventActionSize
            iconSize: DashMetrics.eventActionIconSize
            iconName: taskItem.isEditing ? "close" : "delete"
            Accessible.name: taskItem.isEditing ? I18n.tr("Cancel") : I18n.tr("Delete")
            iconColor: taskItem.isEditing ? Theme.onSurfaceVariant : Theme.error
            visible: taskItem.canModify
            onClicked: {
                if (taskItem.isEditing) {
                    taskItem.isEditing = false;
                    return;
                }
                if (taskItem.taskId !== "")
                    CalendarService.removeTask(taskItem.taskId);
            }
        }

        DActionButton {
            anchors.right: deleteButton.left
            anchors.rightMargin: Theme.spacingXS
            anchors.verticalCenter: parent.verticalCenter
            buttonSize: DashMetrics.eventActionSize
            iconSize: DashMetrics.eventActionIconSize
            iconName: taskItem.isEditing ? "check" : "edit"
            Accessible.name: taskItem.isEditing ? I18n.tr("Save") : I18n.tr("Edit")
            iconColor: taskItem.isEditing ? Theme.primary : Theme.onSurfaceVariant
            visible: taskItem.canModify
            onClicked: {
                if (taskItem.isEditing) {
                    taskItem.commitEdit();
                    return;
                }
                taskItem.isEditing = true;
            }
        }
    }

    SystemClock {
        id: systemClock
        enabled: root.live
        precision: SystemClock.Hours
    }

    Connections {
        target: SessionService

        function onSessionResumed() {
            if (!root.live)
                return;
            systemClock.enabled = false;
            systemClock.enabled = true;
        }
    }
}
