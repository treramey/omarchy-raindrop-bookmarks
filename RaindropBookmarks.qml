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
  property var pendingBookmarks: []
  property double lastFetchMs: 0
  readonly property int refreshIntervalMs: 5 * 60 * 1000
  property string errorMessage: ""
  property bool needsToken: false
  property bool checkingToken: false
  property bool savingToken: false
  property bool tokenValidated: false
  property bool validatingSubmission: false
  property bool showToken: false
  property string onboardingPhase: "entry"
  property string onboardingError: ""
  property string pendingToken: ""
  readonly property string pluginId: "io.github.treramey.raindrop-bookmarks"
  property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
  property string cacheHome: Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")
  property string tokenPath: Quickshell.env("RAINDROP_TOKEN_FILE") || (configHome + "/raindrop/token")
  property string pluginDirectory: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir)
    : configHome + "/omarchy/plugins/" + pluginId
  property string coverDirectory: cacheHome + "/omarchy-shell/raindrop-bookmarks/covers"
  property string coverSyncPath: pluginDirectory + "/cover-sync"
  property string configureTokenPath: pluginDirectory + "/configure-token"
  property string validateTokenPath: pluginDirectory + "/validate-token"
  property var coverLookup: ({})

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int cardWidth: Math.min(Style.space(needsToken ? 580 : 760), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(needsToken ? 430 : 520), panel.height - Style.gapsOut * 2)
  property int rowHeight: Math.max(Style.space(54), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)

  function open(payloadJson) {
    showToken = false
    opened = true
    filterText = ""
    selectedIndex = 0
    errorMessage = ""
    onboardingError = ""
    onboardingPhase = "entry"
    checkToken()
  }

  function checkToken() {
    if (tokenCheck.running) return
    checkingToken = true
    tokenCheck.command = ["bash", "-c",
      "[[ -f \"$1\" && -r \"$1\" ]] && size=$(stat -Lc %s -- \"$1\") "
        + "&& [[ \"$size\" =~ ^[0-9]+$ ]] && (( size > 0 && size <= 8192 ))",
      "raindrop-token-check", tokenPath]
    tokenCheck.running = true
  }

  function continueOpen() {
    needsToken = false
    syncCovers()
    if (!fetch.running && (!bookmarks.length || Date.now() - lastFetchMs >= refreshIntervalMs)) {
      filter()
      startFetch()
    } else filter()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function saveToken() {
    var token = tokenField.text.trim()
    if (!token) {
      onboardingError = "Paste your Raindrop test token first"
      return
    }
    if (tokenWriter.running) return
    onboardingError = ""
    onboardingPhase = "checking"
    pendingToken = token
    savingToken = true
    validatingSubmission = true
    tokenValidator.command = [validateTokenPath]
    tokenValidator.running = true
  }

  function validateToken() {
    if (tokenValidator.running) return
    onboardingError = ""
    onboardingPhase = "checking"
    validatingSubmission = false
    tokenValidator.command = [validateTokenPath, "--file", tokenPath]
    tokenValidator.running = true
  }

  function showTokenError(message) {
    tokenValidated = false
    needsToken = true
    onboardingPhase = "entry"
    onboardingError = message
    Qt.callLater(function() { tokenField.forceActiveFocus() })
  }

  function handleFetchError(message) {
    if (/\b(401|403)\b/.test(message)) {
      showTokenError("Raindrop didn't accept this token. Check that you copied the complete test token, then try again.")
    } else if (message) {
      errorMessage = "Could not reach Raindrop. Check your connection and try again."
    }
  }

  function close() {
    showToken = false
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
    var link = String(results[selectedIndex].link || "")
    if (!/^https?:\/\/[^\s]+$/i.test(link)) {
      errorMessage = "Only HTTP and HTTPS bookmarks can be opened"
      return
    }
    Quickshell.execDetached(["xdg-open", link])
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
        if (/^\d+$/.test(id) && path) lookup[id] = fileUrl(path)
      }
    }
    coverLookup = lookup
  }

  function fileUrl(path) {
    return "file://" + String(path).split("/").map(function(part) {
      return encodeURIComponent(part)
    }).join("/")
  }

  function coverSource(bookmark) {
    if (!bookmark || bookmark._id === undefined || bookmark._id === null) return ""
    return coverLookup[String(bookmark._id)] || ""
  }

  function startFetch() {
    page = 0
    pendingBookmarks = []
    errorMessage = ""
    fetchPage()
  }

  function fetchPage() {
    fetch.command = ["bash", "-c",
      "[[ -r \"$1\" ]] || { printf 'Raindrop token not found: %s\\n' \"$1\" >&2; exit 1; }; "
        + "token=$(tr -d '\\r\\n' < \"$1\"); [[ -n \"$token\" ]] || { echo 'Raindrop token is empty' >&2; exit 1; }; "
        + "header=$(mktemp); chmod 600 \"$header\"; trap 'rm -f \"$header\"' EXIT; "
        + "printf 'Authorization: Bearer %s\\n' \"$token\" > \"$header\"; unset token; "
        + "curl -q --fail --silent --show-error --proto '=https' --proto-redir '=https' "
        + "--max-redirs 0 --noproxy '*' --connect-timeout 5 --max-time 15 "
        + "--max-filesize 10485760 --header \"@$header\" --url \"$2\"",
      "raindrop-fetch", tokenPath,
      "https://api.raindrop.io/rest/v1/raindrops/0?perpage=50&page=" + page]
    fetch.running = true
  }

  function handleResponse(text) {
    try {
      var response = JSON.parse(text)
      if (!response || !Array.isArray(response.items)) throw new Error("invalid items")
      var items = response.items
      pendingBookmarks = pendingBookmarks.concat(items)
      if (items.length === 50) { page++; fetchPage() }
      else {
        bookmarks = pendingBookmarks
        lastFetchMs = Date.now()
        errorMessage = ""
        filter()
      }
    } catch (error) { errorMessage = "Could not read the Raindrop response" }
  }

  Process {
    id: fetch
    stdout: StdioCollector { onStreamFinished: root.handleResponse(this.text) }
    stderr: StdioCollector { onStreamFinished: root.handleFetchError(this.text.trim()) }
  }

  Process {
    id: coverSync
    stdout: StdioCollector { onStreamFinished: root.handleCoverIndex(this.text) }
  }

  Process {
    id: tokenCheck
    onExited: function(exitCode, exitStatus) {
      root.checkingToken = false
      if (exitCode === 0) {
        if (root.tokenValidated) root.continueOpen()
        else root.validateToken()
      }
      else {
        root.needsToken = true
        Qt.callLater(function() { tokenField.forceActiveFocus() })
      }
    }
  }

  Process {
    id: tokenWriter
    stdinEnabled: true
    stderr: StdioCollector {
      onStreamFinished: if (this.text.trim()) root.onboardingError = this.text.trim()
    }
    onStarted: {
      write(root.pendingToken + "\n")
      root.pendingToken = ""
    }
    onExited: function(exitCode, exitStatus) {
      root.savingToken = false
      if (exitCode === 0) {
        root.validatingSubmission = false
        root.tokenValidated = true
        root.onboardingPhase = "success"
        tokenField.text = ""
        root.onboardingError = ""
        connectionSuccess.restart()
      } else if (!root.onboardingError) {
        root.onboardingError = "Could not save the Raindrop token"
      }
      if (exitCode !== 0) root.onboardingPhase = "entry"
    }
  }

  Process {
    id: tokenValidator
    stdinEnabled: true
    stderr: StdioCollector { id: tokenValidationError; waitForEnd: true }
    onStarted: if (root.validatingSubmission) write(root.pendingToken + "\n")
    onExited: function(exitCode, exitStatus) {
      if (exitCode === 0) {
        if (root.validatingSubmission) {
          tokenWriter.command = [root.configureTokenPath, root.tokenPath]
          tokenWriter.running = true
        } else {
          root.tokenValidated = true
          root.onboardingPhase = "success"
          tokenField.text = ""
          connectionSuccess.restart()
        }
      } else {
        root.savingToken = false
        root.pendingToken = ""
        var detail = tokenValidationError.text.trim()
        if (/\b(401|403)\b/.test(detail)) {
          root.showTokenError("Raindrop didn't accept this token. Check that you copied the complete test token, then try again.")
        } else {
          root.showTokenError("Could not reach Raindrop. Check your connection and try again.")
        }
      }
    }
  }

  Timer {
    id: connectionSuccess
    interval: 650
    repeat: false
    onTriggered: root.continueOpen()
  }

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
        Keys.enabled: !root.needsToken
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
        visible: !root.needsToken
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
            textFormat: Text.PlainText
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
          textFormat: Text.PlainText
          color: root.foreground; opacity: 0.62
          font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.weight: Font.DemiBold
        }

        Text {
          visible: root.errorMessage !== ""
          width: parent.width
          text: root.errorMessage
          textFormat: Text.PlainText
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
                textFormat: Text.PlainText
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
              Text { width: parent.width; text: modelData.title || modelData.link; textFormat: Text.PlainText; color: index === root.selectedIndex ? root.selectedText : root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; elide: Text.ElideRight }
              Text { width: parent.width; text: modelData.domain || modelData.link; textFormat: Text.PlainText; color: root.foreground; opacity: 0.58; font.family: root.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
            }
            Text { anchors.right: parent.right; anchors.rightMargin: Style.spacing.rowPaddingX; anchors.verticalCenter: parent.verticalCenter; visible: index === root.selectedIndex; text: "↵"; textFormat: Text.PlainText; color: root.selectedText; font.family: root.fontFamily; font.pixelSize: Style.font.title }
            MouseArea {
              id: mouse
              anchors.fill: parent
              hoverEnabled: true
              onClicked: {
                root.selectedIndex = index
                root.openCurrent()
              }
            }
          }
        }
      }

      Column {
        visible: root.needsToken
        width: Math.min(parent.width - card.contentLeftInset - card.contentRightInset, Style.space(500))
        anchors.centerIn: parent
        spacing: Style.spacing.md

        Text {
          width: parent.width
          text: root.onboardingPhase === "success" ? "Connected" : "Connect Raindrop"
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.weight: Font.DemiBold
          horizontalAlignment: root.onboardingPhase === "success" ? Text.AlignHCenter : Text.AlignLeft
        }

        Text {
          visible: root.onboardingPhase !== "success"
          width: parent.width
          text: "Create an app in the Raindrop integrations menu and copy its Test token. Then reopen Raindrop Bookmarks and paste it here."
          textFormat: Text.PlainText
          color: root.foreground
          opacity: 0.82
          wrapMode: Text.WordWrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Row {
          visible: root.onboardingPhase !== "success"
          width: parent.width
          spacing: Style.spacing.sm

          TextField {
            id: tokenField
            width: parent.width - revealToken.width - parent.spacing
            password: !root.showToken
            enabled: root.onboardingPhase === "entry" && !root.savingToken
            placeholderText: "Paste token"
            foreground: root.foreground
            onAccepted: root.saveToken()
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                root.close()
                event.accepted = true
              }
            }
          }

          Button {
            id: revealToken
            height: tokenField.height
            text: root.showToken ? "Hide" : "Show"
            bordered: true
            enabled: root.onboardingPhase === "entry"
            foreground: root.foreground
            onClicked: root.showToken = !root.showToken
          }
        }

        Text {
          visible: root.onboardingPhase !== "success" && root.onboardingError !== ""
          width: parent.width
          text: root.onboardingError
          textFormat: Text.PlainText
          color: Color.urgent
          wrapMode: Text.WordWrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Row {
          visible: root.onboardingPhase !== "success"
          anchors.right: parent.right
          spacing: Style.spacing.sm

          Button {
            text: "Get Raindrop token ↗"
            foreground: root.foreground
            onClicked: {
              root.close()
              Quickshell.execDetached(["xdg-open", "https://app.raindrop.io/settings/integrations"])
            }
          }

          Button {
            text: root.onboardingPhase === "checking" ? "Checking token…" : "Connect Raindrop"
            selected: true
            bordered: true
            enabled: root.onboardingPhase === "entry" && !root.savingToken && tokenField.text.trim() !== ""
            opacity: root.onboardingPhase === "checking" ? 0.72 : (enabled ? 1 : 0.45)
            foreground: root.foreground
            onClicked: root.saveToken()
          }
        }

        Text {
          visible: root.onboardingPhase === "success"
          width: parent.width
          text: "Loading your bookmarks…"
          textFormat: Text.PlainText
          color: root.foreground
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
      }
    }
  }
}
