import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "FuzzySearch.js" as FuzzySearch

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property string filterText: ""
  property var bookmarks: []
  property var results: []
  property int selectedIndex: 0
  property int page: 0
  property string errorMessage: ""
  readonly property string pluginId: "io.github.treramey.raindrop-bookmarks"
  property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
  property string cacheHome: Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")
  property string tokenPath: Quickshell.env("RAINDROP_TOKEN_FILE") || (configHome + "/raindrop/token")
  property string pluginDirectory: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir)
    : configHome + "/omarchy/plugins/" + pluginId
  property string coverDirectory: cacheHome + "/omarchy-shell/raindrop-bookmarks/covers"
  property string coverSyncPath: pluginDirectory + "/cover-sync"
  property var coverLookup: ({})

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int cardWidth: Math.min(Style.space(760), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(520), panel.height - Style.gapsOut * 2)
  property int rowHeight: Math.max(Style.space(54), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)

  function open(payloadJson) {
    opened = true
    filterText = ""
    selectedIndex = 0
    syncCovers()
    if (!bookmarks.length && !fetch.running) {
      page = 0
      errorMessage = ""
      fetchPage()
    } else filter()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    opened = false
  }

  function toggle() { opened ? close() : open("{}") }

  function filter() {
    results = FuzzySearch.search(filterText, bookmarks)
    selectedIndex = results.length ? 0 : -1
  }

  function select(delta) {
    if (!results.length) return
    selectedIndex = (selectedIndex + delta + results.length) % results.length
    list.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function openCurrent() {
    if (selectedIndex < 0 || selectedIndex >= results.length) return
    Quickshell.execDetached(["xdg-open", results[selectedIndex].link])
    close()
  }

  function syncCovers() {
    if (coverSync.running) return
    coverSync.command = [coverSyncPath, tokenPath, coverDirectory]
    coverSync.running = true
  }

  function handleCoverIndex(text) {
    var lookup = {}
    var entries = text.split(/\r?\n/)
    for (var i = 0; i < entries.length; i++) {
      var separator = entries[i].indexOf("\t")
      if (separator > 0) {
        var id = entries[i].slice(0, separator)
        var path = entries[i].slice(separator + 1)
        if (/^\d+$/.test(id) && path) lookup[id] = "file://" + path
      }
    }
    coverLookup = lookup
  }

  function coverSource(bookmark) {
    if (!bookmark || bookmark._id === undefined || bookmark._id === null) return ""
    return coverLookup[String(bookmark._id)] || ""
  }

  function fetchPage() {
    fetch.command = ["bash", "-c",
      "[[ -r \"$1\" ]] || { printf 'Raindrop token not found: %s\\n' \"$1\" >&2; exit 1; }; "
        + "token=$(tr -d '\\r\\n' < \"$1\"); [[ -n \"$token\" ]] || { echo 'Raindrop token is empty' >&2; exit 1; }; "
        + "header=$(mktemp); chmod 600 \"$header\"; trap 'rm -f \"$header\"' EXIT; "
        + "printf 'Authorization: Bearer %s\\n' \"$token\" > \"$header\"; unset token; "
        + "curl --fail --silent --show-error --proto '=https' --proto-redir '=https' "
        + "--max-redirs 0 --noproxy '*' --connect-timeout 5 --max-time 15 "
        + "--max-filesize 10485760 --header \"@$header\" --url \"$2\"",
      "raindrop-fetch", tokenPath,
      "https://api.raindrop.io/rest/v1/raindrops/0?perpage=50&page=" + page]
    fetch.running = true
  }

  function handleResponse(text) {
    try {
      var items = (JSON.parse(text).items || [])
      bookmarks = bookmarks.concat(items)
      filter()
      if (items.length === 50) { page++; fetchPage() }
    } catch (error) { errorMessage = "Could not read the Raindrop response" }
  }

  Process {
    id: fetch
    stdout: StdioCollector { onStreamFinished: root.handleResponse(this.text) }
    stderr: StdioCollector { onStreamFinished: if (this.text.trim()) root.errorMessage = this.text.trim() }
  }

  Process {
    id: coverSync
    stdout: StdioCollector { onStreamFinished: root.handleCoverIndex(this.text) }
  }

  Component.onCompleted: syncCovers()

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "raindrop-bookmarks"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: root.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      anchors.centerIn: parent
      radius: root.cornerRadius
      color: root.background
      borderSpec: root.borderSpec
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) { root.filterText = ""; root.filter() } else root.close()
          } else if (Util.editsFilter(event, root.filterText)) {
            root.filterText = Util.editedFilter(event, root.filterText); root.filter()
          } else if (event.key === Qt.Key_Up) root.select(-1)
          else if (event.key === Qt.Key_Down) root.select(1)
          else if (event.key === Qt.Key_PageUp) root.select(-6)
          else if (event.key === Qt.Key_PageDown) root.select(6)
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.openCurrent()
          else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32
                   && event.text.charCodeAt(0) !== 127
                   && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
            root.filterText += event.text
            root.filter()
          }
          else return
          event.accepted = true
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.sm

        Rectangle {
          width: parent.width
          height: Math.max(Style.space(42), Style.font.title + Style.spacing.controlPaddingY * 2)
          radius: root.cornerRadius
          color: "transparent"
          Text {
            anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            text: root.filterText || (root.bookmarks.length ? "Search " + root.bookmarks.length + " bookmarks…" : "Loading bookmarks…")
            color: root.foreground; opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily; font.pixelSize: Style.font.title
            elide: Text.ElideRight
          }
        }

        Text {
          width: parent.width
          height: Style.space(28)
          verticalAlignment: Text.AlignVCenter
          text: root.filterText ? "RESULTS" : "ALL BOOKMARKS"
          color: root.foreground; opacity: 0.62
          font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.weight: Font.DemiBold
        }

        Text {
          visible: root.errorMessage !== ""
          width: parent.width
          text: root.errorMessage
          color: Color.urgent
          wrapMode: Text.Wrap
          font.family: root.fontFamily
        }

        ListView {
          id: list
          width: parent.width
          height: parent.height - y
          model: root.results
          clip: true
          spacing: Style.spacing.xs
          boundsBehavior: Flickable.StopAtBounds

          delegate: Rectangle {
            required property var modelData
            required property int index
            width: ListView.view.width; height: root.rowHeight
            radius: root.cornerRadius
            color: index === root.selectedIndex ? root.selectedBackground : mouse.containsMouse ? Util.alpha(root.foreground, 0.04) : "transparent"

            Rectangle {
              id: icon
              anchors.left: parent.left; anchors.leftMargin: Style.spacing.rowPaddingX; anchors.verticalCenter: parent.verticalCenter
              width: Style.space(30); height: width
              radius: Math.min(root.cornerRadius, width / 2)
              color: Util.alpha(root.foreground, 0.08)
              clip: true
              Text {
                anchors.centerIn: parent
                visible: coverImage.status !== Image.Ready
                text: (modelData.title || modelData.domain || "?").charAt(0).toUpperCase()
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.weight: Font.DemiBold
              }
              Image {
                id: coverImage
                anchors.fill: parent
                source: root.coverSource(modelData)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                visible: status === Image.Ready
              }
            }
            Column {
              anchors.left: icon.right; anchors.leftMargin: Style.spacing.md; anchors.right: parent.right
              anchors.rightMargin: Style.space(44); anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.xs
              Text { width: parent.width; text: modelData.title || modelData.link; color: index === root.selectedIndex ? root.selectedText : root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; elide: Text.ElideRight }
              Text { width: parent.width; text: modelData.domain || modelData.link; color: root.foreground; opacity: 0.58; font.family: root.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
            }
            Text { anchors.right: parent.right; anchors.rightMargin: Style.spacing.rowPaddingX; anchors.verticalCenter: parent.verticalCenter; visible: index === root.selectedIndex; text: "↵"; color: root.selectedText; font.family: root.fontFamily; font.pixelSize: Style.font.title }
            MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; onEntered: root.selectedIndex = index; onClicked: root.openCurrent() }
          }
        }
      }
    }
  }
}
