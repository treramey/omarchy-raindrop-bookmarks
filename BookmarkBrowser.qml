import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Search and command presentation. Bookmark storage, filtering, and effects
// remain with RaindropBookmarks, reached only through the semantic signals below.
Item {
  id: root

  property bool active: false
  property string query: ""
  property var results: []
  property int selectedIndex: -1
  property var coverLookup: ({})
  property string statusText: ""
  property double lastSyncMs: 0
  property string errorText: ""
  property bool loading: false
  property bool refreshing: false
  property bool canRefresh: false
  property bool reconnectRequired: false
  property color foreground: Commons.Color.menu.text
  property color selectedBackground: Commons.Color.menu.selectedBackground
  property color selectedText: Commons.Color.menu.selectedText
  property string fontFamily: Style.font.menuFamily

  readonly property bool canOpen: selectedIndex >= 0 && selectedIndex < results.length
  readonly property int rowHeight: Math.max(Style.space(48), Style.font.body + Style.font.caption + Style.spacing.xs + Style.spacing.lg * 2)
  readonly property var selectedBorderSpec: Border.surfaceSpec("menu", "selected-border", Commons.Color.menu.selectedBorder, 0)
  property bool actionsOpen: false
  property int actionIndex: -1
  readonly property var actions: {
    var items = [
      { id: "open", label: "Open in browser", shortcut: "↵", enabled: root.canOpen },
      { id: "refresh", label: root.refreshing ? "Refreshing…" : "Refresh bookmarks", shortcut: "Ctrl R", enabled: root.canRefresh }
    ]
    if (root.reconnectRequired)
      items.push({ id: "reconnect", label: "Reconnect Raindrop", shortcut: "", enabled: true })
    return items
  }

  signal queryEdited(string text)
  signal moveRequested(int delta)
  signal selectionRequested(int index)
  signal openRequested()
  signal refreshRequested()
  signal reconnectRequested()
  signal closeRequested()

  onQueryChanged: {
    if (pointerGate) pointerGate.reset()
    if (searchInput.text !== query) searchInput.text = query
  }
  onActiveChanged: {
    if (pointerGate) pointerGate.reset()
    actionsOpen = false
    if (active) Qt.callLater(focusSearch)
  }
  onActionsOpenChanged: if (pointerGate) pointerGate.reset()
  onSelectedIndexChanged: Qt.callLater(revealSelection)
  onResultsChanged: {
    if (pointerGate) pointerGate.reset()
    Qt.callLater(revealSelection)
  }
  onRowHeightChanged: Qt.callLater(revealSelection)

  function revealSelection() {
    // Models and theme metrics can change in the same turn. Settle the layout
    // before positioning, or the old row heights leave the selection offscreen.
    list.forceLayout()
    if (selectedIndex >= 0 && selectedIndex < list.count)
      list.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function focusSearch() {
    if (active) searchInput.forceActiveFocus()
  }

  function moveAction(delta) {
    for (var offset = 1; offset <= actions.length; offset++) {
      var next = (actionIndex + delta * offset + actions.length) % actions.length
      if (actions[next].enabled) {
        actionIndex = next
        return
      }
    }
    actionIndex = -1
  }

  function toggleActions() {
    actionsOpen = !actionsOpen
    actionIndex = -1
    if (actionsOpen) moveAction(1)
    focusSearch()
  }

  function activateAction(index) {
    var action = actions[index]
    if (!action || !action.enabled) return
    actionsOpen = false
    if (action.id === "open") openRequested()
    else if (action.id === "refresh") refreshRequested()
    else if (action.id === "reconnect") reconnectRequested()
    focusSearch()
  }

  function handleKey(event) {
    if (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_K) toggleActions()
    else if (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_R) {
      if (canRefresh) refreshRequested()
    } else if (actionsOpen) {
      if (event.key === Qt.Key_Escape) actionsOpen = false
      else if (event.key === Qt.Key_Up) moveAction(-1)
      else if (event.key === Qt.Key_Down) moveAction(1)
      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) activateAction(actionIndex)
      // Do not type into the bookmark search behind the action menu.
    } else if (event.key === Qt.Key_Escape) {
      if (query) queryEdited("")
      else closeRequested()
    } else if (event.key === Qt.Key_Up) moveRequested(-1)
    else if (event.key === Qt.Key_Down) moveRequested(1)
    else if (event.key === Qt.Key_PageUp) moveRequested(-6)
    else if (event.key === Qt.Key_PageDown) moveRequested(6)
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (canOpen) openRequested()
    } else if (Util.editsFilter(event, query)) queryEdited(Util.editedFilter(event, query))
    else return
    pointerGate.reset()
    event.accepted = true
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: root
  }

  component Label: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
  }

  component Keycap: BorderSurface {
    id: keycap
    property string text: ""
    leftPadding: text === "↵" ? Style.spacing.sm : Style.spacing.controlPaddingX
    rightPadding: leftPadding
    implicitWidth: Math.max(Style.space(20), keyLabel.implicitWidth + contentLeftInset + contentRightInset)
    implicitHeight: keyLabel.implicitHeight + Style.spacing.sm * 2
    color: Style.normalFillFor(root.foreground, Commons.Color.accent)
    borderSpec: Border.controlSpec("normal", root.foreground, Commons.Color.accent)
    radius: Style.cornerRadius
    Label {
      id: keyLabel
      anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
      anchors.leftMargin: keycap.contentLeftInset
      anchors.rightMargin: keycap.contentRightInset
      horizontalAlignment: Text.AlignHCenter
      text: keycap.text
      font.pixelSize: Style.font.caption
      opacity: 0.8
    }
  }

  component CommandButton: Button {
    id: commandButton
    property string label: ""
    property string shortcut: ""
    Accessible.role: Accessible.Button
    Accessible.name: label
    implicitWidth: commandContent.implicitWidth + horizontalPadding * 2
    implicitHeight: commandContent.implicitHeight + verticalPadding * 2
    foreground: root.foreground
    fontFamily: root.fontFamily
    opacity: enabled ? 1 : 0.4
    Row {
      id: commandContent
      anchors.centerIn: parent
      spacing: Style.spacing.controlGap
      Label {
        anchors.verticalCenter: parent.verticalCenter
        text: commandButton.label
        font.pixelSize: Style.font.caption
      }
      Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xs
        Repeater {
          model: commandButton.shortcut.split(" ")
          Keycap {
            required property string modelData
            anchors.verticalCenter: parent.verticalCenter
            text: modelData
          }
        }
      }
    }
  }

  Item {
    id: browserKeys
    Keys.onPressed: function(event) { root.handleKey(event) }
  }

  Item {
    id: searchHeader
    anchors { top: parent.top; left: parent.left; right: parent.right }
    height: Math.max(Style.space(64), Style.font.heading + Style.spacing.panelPadding * 2)

    Item {
      id: searchIcon
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.panelPadding
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(18)
      height: width
      opacity: 0.6
      Rectangle {
        width: parent.width * 0.7
        height: width
        radius: width / 2
        color: "transparent"
        border { width: Math.max(1, Style.space(1.5)); color: root.foreground }
      }
      Rectangle {
        x: parent.width * 0.65
        y: parent.height * 0.55
        width: Math.max(1, Style.space(1.5))
        height: parent.height * 0.45
        rotation: -45
        color: root.foreground
      }
    }

    FilterInput {
      id: searchInput
      objectName: "bookmarkSearch"
      Accessible.name: "Search bookmarks"
      anchors { left: searchIcon.right; right: searchEscape.left; verticalCenter: parent.verticalCenter }
      anchors.leftMargin: Style.spacing.rowGap
      anchors.rightMargin: Style.spacing.rowGap
      enabled: root.active
      readOnly: root.actionsOpen
      keyHandler: browserKeys
      color: root.foreground
      selectionColor: Style.selectionFillFor(root.foreground, Commons.Color.accent)
      selectedTextColor: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.heading
      onTextChanged: if (text !== root.query) root.queryEdited(text)
    }

    Label {
      anchors.fill: searchInput
      verticalAlignment: Text.AlignVCenter
      text: "Search bookmarks…"
      visible: !searchInput.text && !searchInput.preeditText
      font.pixelSize: Style.font.heading
      opacity: 0.65
    }

    Keycap {
      id: searchEscape
      anchors { right: parent.right; verticalCenter: parent.verticalCenter }
      anchors.rightMargin: Style.spacing.panelPadding
      text: "esc"
    }
    PanelSeparator { anchors.bottom: parent.bottom; foreground: root.foreground }
  }

  Item {
    id: resultArea
    anchors { top: searchHeader.bottom; bottom: footer.top; left: parent.left; right: parent.right }
    anchors.margins: Style.spacing.lg

    Item {
      id: resultHeading
      anchors { top: parent.top; left: parent.left; right: parent.right }
      height: Style.font.caption + Style.spacing.rowPaddingX * 2
      Label {
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        anchors.leftMargin: Style.spacing.rowPaddingX
        text: root.query ? "Search results" : "Bookmarks"
        font.pixelSize: Style.font.caption
        font.weight: Font.DemiBold
        opacity: 0.65
      }
      Label {
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        anchors.rightMargin: Style.spacing.rowPaddingX
        text: root.results.length + (root.results.length === 1 ? " bookmark" : " bookmarks")
        font.pixelSize: Style.font.caption
        opacity: 0.65
      }
    }

    Label {
      id: errorLabel
      anchors { top: resultHeading.bottom; left: parent.left; right: parent.right }
      anchors.leftMargin: Style.spacing.rowPaddingX
      anchors.rightMargin: Style.spacing.rowPaddingX
      visible: root.errorText !== ""
      height: visible ? implicitHeight + Style.spacing.lg : 0
      text: root.errorText
      color: Commons.Color.urgent
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.Wrap
      maximumLineCount: 2
    }

    ListView {
      id: list
      objectName: "bookmarkResults"
      anchors { top: errorLabel.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
      model: root.results
      currentIndex: root.selectedIndex
      onHeightChanged: Qt.callLater(root.revealSelection)
      clip: true
      spacing: Style.spacing.xs
      boundsBehavior: Flickable.StopAtBounds

      Rectangle {
        parent: list
        anchors.right: parent.right
        width: Math.max(2, Style.space(2))
        height: Math.max(Style.space(12), list.height * list.visibleArea.heightRatio)
        y: Math.max(0, Math.min(list.height - height, list.height * list.visibleArea.yPosition))
        visible: list.contentHeight > list.height && list.height > 0
        color: Util.alpha(root.foreground, 0.3)
        z: 2
      }

      delegate: BorderSurface {
        id: resultRow
        required property var modelData
        required property int index
        readonly property bool selected: index === root.selectedIndex
        // ListView exposes nested arrays as Qt sequences, not JS Arrays.
        readonly property string tag: modelData.tags && typeof modelData.tags !== "string"
          && modelData.tags.length ? String(modelData.tags[0]) : ""
        width: ListView.view.width
        height: root.rowHeight
        radius: Style.cornerRadius
        color: selected ? root.selectedBackground : "transparent"
        borderSpec: selected ? root.selectedBorderSpec : Border.none()

        Rectangle {
          id: coverTile
          anchors { left: parent.left; verticalCenter: parent.verticalCenter }
          anchors.leftMargin: Style.spacing.rowPaddingX + Border.left(root.selectedBorderSpec)
          width: Style.space(28)
          height: width
          radius: Math.min(Style.cornerRadius, width / 2)
          color: Style.normalFillFor(root.foreground, Commons.Color.accent)
          clip: true
          Label {
            anchors.centerIn: parent
            visible: coverImage.status !== Image.Ready
            text: String(resultRow.modelData.title || resultRow.modelData.domain || "?").charAt(0).toUpperCase()
            color: resultRow.selected ? root.selectedText : root.foreground
            font.weight: Font.DemiBold
          }
          Image {
            id: coverImage
            anchors.fill: parent
            source: root.coverLookup[String(resultRow.modelData._id)] || ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: status === Image.Ready
          }
        }

        Column {
          anchors { left: coverTile.right; right: rowTrail.left; verticalCenter: parent.verticalCenter }
          anchors.leftMargin: Style.spacing.rowGap
          anchors.rightMargin: Style.spacing.rowGap
          spacing: Style.spacing.xs
          Label {
            width: parent.width
            text: resultRow.modelData.title || resultRow.modelData.link || "Untitled bookmark"
            color: resultRow.selected ? root.selectedText : root.foreground
            font.weight: resultRow.selected ? Font.Medium : Font.Normal
          }
          Label {
            width: parent.width
            text: resultRow.modelData.domain || resultRow.modelData.link || ""
            color: resultRow.selected ? root.selectedText : root.foreground
            font.pixelSize: Style.font.caption
            opacity: 0.7
          }
        }

        Row {
          id: rowTrail
          anchors { right: parent.right; verticalCenter: parent.verticalCenter }
          anchors.rightMargin: Style.spacing.rowPaddingX + Border.right(root.selectedBorderSpec)
          spacing: Style.spacing.rowGap
          Rectangle {
            visible: resultRow.tag !== "" && root.width >= Style.space(580)
            width: Math.min(Style.space(130), tagLabel.implicitWidth + Style.spacing.controlPaddingX * 2)
            height: tagLabel.implicitHeight + Style.spacing.sm * 2
            anchors.verticalCenter: parent.verticalCenter
            radius: Style.cornerRadius
            color: Style.normalFillFor(root.foreground, Commons.Color.accent)
            Label {
              id: tagLabel
              anchors { fill: parent; leftMargin: Style.spacing.controlPaddingX; rightMargin: Style.spacing.controlPaddingX }
              verticalAlignment: Text.AlignVCenter
              text: resultRow.tag
              color: resultRow.selected ? root.selectedText : root.foreground
              font.pixelSize: Style.font.caption
              opacity: 0.7
            }
          }
          Label {
            visible: resultRow.selected
            anchors.verticalCenter: parent.verticalCenter
            text: "↵"
            color: root.selectedText
            opacity: 0.65
          }
        }
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onPositionChanged: function(mouse) {
            if (pointerGate.moved(this, mouse)) root.selectionRequested(resultRow.index)
          }
          onClicked: {
            root.selectionRequested(resultRow.index)
            root.openRequested()
          }
        }
      }
    }

    Column {
      anchors.centerIn: list
      width: Math.max(0, parent.width - Style.spacing.panelPadding * 2)
      spacing: Style.spacing.lg
      visible: root.results.length === 0
      Label {
        width: parent.width
        text: root.loading ? "Loading bookmarks" : root.query ? "No matching bookmarks" : "No bookmarks yet"
        font.pixelSize: Style.font.heading
        horizontalAlignment: Text.AlignHCenter
      }
      Label {
        width: parent.width
        text: root.loading ? "Your bookmarks will appear here."
          : root.query ? "Try a different title, domain, or tag." : "Save a bookmark in Raindrop, then refresh."
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        opacity: 0.7
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    visible: root.actionsOpen
    z: 2
    onClicked: { root.actionsOpen = false; root.focusSearch() }
  }

  Item {
    id: footer
    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
    height: Math.max(Style.space(46), commands.implicitHeight + Style.spacing.sm * 2)
    z: 3
    PanelSeparator { anchors.top: parent.top; foreground: root.foreground }
    Label {
      id: brand
      anchors { left: parent.left; verticalCenter: parent.verticalCenter }
      anchors.leftMargin: Style.spacing.panelPadding
      text: "Raindrop"
      visible: root.width >= Style.space(360)
      font.pixelSize: Style.font.caption
      font.weight: Font.DemiBold
      opacity: 0.8
    }
    Label {
      anchors { left: brand.right; right: commands.left; verticalCenter: parent.verticalCenter }
      anchors.leftMargin: Style.spacing.rowGap
      anchors.rightMargin: Style.spacing.rowGap
      text: timestampHover.containsMouse && root.lastSyncMs
        ? "Synced " + Qt.formatDateTime(new Date(root.lastSyncMs), "MMM d, HH:mm") : root.statusText
      font.pixelSize: Style.font.caption
      opacity: 0.65
      visible: root.width >= Style.space(560)
      MouseArea {
        id: timestampHover
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
      }
    }
    Row {
      id: commands
      anchors { right: parent.right; verticalCenter: parent.verticalCenter }
      anchors.rightMargin: Style.spacing.lg
      spacing: Style.spacing.sm
      CommandButton {
        label: root.width >= Style.space(620) ? "Open in browser" : "Open"
        shortcut: "↵"
        enabled: root.canOpen
        onClicked: root.openRequested()
      }
      CommandButton {
        label: "Actions"
        shortcut: "Ctrl K"
        active: root.actionsOpen
        onClicked: root.toggleActions()
      }
    }
  }

  BorderSurface {
    id: actionMenu
    objectName: "bookmarkActions"
    visible: root.actionsOpen
    anchors { right: parent.right; bottom: footer.top }
    anchors.rightMargin: Style.spacing.lg
    anchors.bottomMargin: Style.spacing.lg
    width: Math.min(Style.space(290), root.width - Style.spacing.lg * 2)
    height: actionColumn.implicitHeight + contentTopInset + contentBottomInset
    color: Commons.Color.popups.background
    borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(1)))
    radius: Style.cornerRadius
    padding: Style.spacing.sm
    z: 4
    Column {
      id: actionColumn
      anchors { left: parent.left; right: parent.right; top: parent.top }
      anchors.leftMargin: actionMenu.contentLeftInset
      anchors.rightMargin: actionMenu.contentRightInset
      anchors.topMargin: actionMenu.contentTopInset
      Repeater {
        model: root.actions
        CursorSurface {
          required property var modelData
          required property int index
          width: parent.width
          height: Math.max(Style.spacing.popupRowHeight, Style.font.body + Style.spacing.controlPaddingY * 2)
          enabled: modelData.enabled
          opacity: enabled ? 1 : 0.4
          hasCursor: index === root.actionIndex
          foreground: Commons.Color.popups.text
          Accessible.role: Accessible.MenuItem
          Accessible.name: modelData.label
          Label {
            anchors { left: parent.left; right: actionShortcut.left; verticalCenter: parent.verticalCenter }
            anchors.leftMargin: Style.spacing.controlPaddingX
            anchors.rightMargin: Style.spacing.controlGap
            text: modelData.label
            color: Commons.Color.popups.text
          }
          Label {
            id: actionShortcut
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            anchors.rightMargin: Style.spacing.controlPaddingX
            text: modelData.shortcut
            color: Commons.Color.popups.text
            font.pixelSize: Style.font.caption
            opacity: 0.7
          }
          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: function(mouse) {
              if (pointerGate.moved(this, mouse)) root.actionIndex = index
            }
            onClicked: root.activateAction(index)
          }
        }
      }
    }
  }
}
