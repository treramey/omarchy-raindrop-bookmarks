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
  property bool snapshotLoaded: false
  property bool snapshotLoading: false
  property string snapshotResponse: ""
  property string snapshotErrorMessage: ""
  property bool snapshotHandled: false
  property string syncResponse: ""
  property bool syncHandled: false
  property bool backgroundTokenValidation: false
  property string syncStatusMessage: ""
  property double syncRetryAfterMs: 0
  property double rateLimitResetMs: 0
  property bool syncAfterCurrent: false
  property bool tokenSavedPendingSnapshot: false
  property bool coverSyncForcePending: false
  readonly property string pluginId: "io.github.treramey.raindrop-bookmarks"
  property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
  property string dataHome: Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")
  property string cacheHome: Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")
  property string tokenPath: Quickshell.env("RAINDROP_TOKEN_FILE") || (configHome + "/raindrop/token")
  property string pluginDirectory: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir)
    : configHome + "/omarchy/plugins/" + pluginId
  property string coverDirectory: cacheHome + "/omarchy-shell/raindrop-bookmarks/covers"
  property string snapshotPath: dataHome + "/omarchy-shell/raindrop-bookmarks/bookmarks.json"
  property string bookmarkSyncPath: pluginDirectory + "/bookmark-sync"
  property string loadBookmarksPath: pluginDirectory + "/load-bookmarks"
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
    selectedIndex = -1
    errorMessage = ""
    syncStatusMessage = "Loading saved bookmarks…"
    onboardingError = ""
    onboardingPhase = "entry"
    tokenValidated = false
    backgroundTokenValidation = false
    snapshotLoaded = false
    bookmarks = []
    results = []
    lastFetchMs = 0
    loadSnapshot()
  }

  function loadSnapshot() {
    if (snapshotLoader.running) return
    snapshotLoading = true
    snapshotHandled = false
    snapshotResponse = ""
    snapshotErrorMessage = ""
    snapshotLoader.command = [loadBookmarksPath, tokenPath, snapshotPath]
    snapshotLoader.running = true
  }

  function applyLoadedSnapshot() {
    if (snapshotHandled) return
    snapshotHandled = true
    snapshotLoading = false
    var loaded = false
    try {
      var snapshot = JSON.parse(snapshotResponse)
      if (snapshot && snapshot.version === 1 && Array.isArray(snapshot.bookmarks)) {
        bookmarks = snapshot.bookmarks
        lastFetchMs = Number(snapshot.syncedAt) * 1000
        loaded = isFinite(lastFetchMs) && lastFetchMs > 0
      }
    } catch (error) {
      loaded = false
    }
    snapshotLoaded = loaded
    if (!loaded) {
      if (!tokenSavedPendingSnapshot) tokenValidated = false
      tokenSavedPendingSnapshot = false
      bookmarks = []
      results = []
      selectedIndex = -1
      lastFetchMs = 0
      syncStatusMessage = snapshotErrorMessage
        ? "Saved bookmarks are unavailable or incompatible. Downloading again."
        : "No saved bookmarks yet"
    } else {
      tokenSavedPendingSnapshot = false
      needsToken = false
      errorMessage = ""
      syncStatusMessage = lastSyncLabel()
      filter(true)
      syncCovers(coverSyncForcePending)
    }
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
    filter(true)
    syncCovers(false)
    if (!bookmarkSync.running && (!snapshotLoaded || Date.now() - lastFetchMs >= refreshIntervalMs)) {
      startBookmarkSync(false)
    }
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
    backgroundTokenValidation = false
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

  function validateTokenInBackground() {
    if (tokenValidator.running) return
    onboardingError = ""
    backgroundTokenValidation = true
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

  function reconnect() {
    needsToken = true
    onboardingPhase = "entry"
    onboardingError = ""
    Qt.callLater(function() { tokenField.forceActiveFocus() })
  }

  function lastSyncLabel() {
    if (!lastFetchMs) return "No saved bookmarks yet"
    return "Saved " + new Date(lastFetchMs).toLocaleString()
  }

  function refreshBookmarks() {
    startBookmarkSync(true)
  }

  function resumeAfterTokenSaved() {
    syncAfterCurrent = bookmarkSync.running
    syncRetryAfterMs = 0
    rateLimitResetMs = 0
    tokenSavedPendingSnapshot = true
    snapshotLoaded = false
    bookmarks = []
    results = []
    selectedIndex = -1
    lastFetchMs = 0
    syncStatusMessage = "Loading bookmarks…"
    loadSnapshot()
  }

  function close() {
    showToken = false
    opened = false
  }

  function toggle() { opened ? close() : open("{}") }

  function filter(preserveSelection) {
    var previousId = ""
    var previousIndex = selectedIndex
    if (preserveSelection && selectedIndex >= 0 && selectedIndex < results.length) {
      var previousBookmark = results[selectedIndex]
      if (previousBookmark && previousBookmark._id !== undefined && previousBookmark._id !== null)
        previousId = String(previousBookmark._id)
    }
    results = FuzzySearch.search(filterText, bookmarks)
    if (!results.length) {
      selectedIndex = -1
      return
    }
    if (previousId) {
      selectedIndex = -1
      for (var i = 0; i < results.length; i++) {
        var bookmark = results[i]
        if (bookmark && bookmark._id !== undefined && String(bookmark._id) === previousId) {
          selectedIndex = i
          break
        }
      }
      if (selectedIndex < 0) selectedIndex = Math.min(Math.max(previousIndex, 0), results.length - 1)
    } else selectedIndex = 0
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

  function syncCovers(force) {
    if (!snapshotLoaded) return
    if (coverSync.running) {
      if (force) coverSyncForcePending = true
      return
    }
    coverSyncForcePending = false
    coverSync.command = [coverSyncPath, tokenPath, coverDirectory, snapshotPath]
    if (force) coverSync.command.push("--force")
    coverSync.running = true
  }

  function startBookmarkSync(manual) {
    if (bookmarkSync.running) return
    var now = Date.now()
    if (now < rateLimitResetMs) {
      syncStatusMessage = "Refresh paused until the Raindrop rate limit resets"
      return
    }
    if (!manual && now < syncRetryAfterMs) {
      syncStatusMessage = "Refresh paused after a recent failure"
      return
    }
    syncHandled = false
    syncResponse = ""
    syncStatusMessage = manual
      ? "Refreshing bookmarks…"
      : (snapshotLoaded ? "Refreshing bookmarks in the background…" : "Loading bookmarks…")
    bookmarkSync.command = [bookmarkSyncPath, tokenPath, snapshotPath]
    if (manual) bookmarkSync.command.push("--manual")
    bookmarkSync.running = true
  }

  function handleBookmarkSyncResult(text) {
    if (syncHandled) return
    syncHandled = true
    var line = String(text).trim().split(/\r?\n/).filter(function(entry) { return entry }).pop() || ""
    var parts = line.split("\t")
    var kind = parts[0] || ""
    var timestamp = Number(parts[1] || 0) * 1000
    if (kind === "SYNC_SUCCESS") {
      syncRetryAfterMs = 0
      rateLimitResetMs = 0
      errorMessage = ""
      if (timestamp > 0) lastFetchMs = timestamp
      syncStatusMessage = lastSyncLabel()
      coverSyncForcePending = true
      loadSnapshot()
    } else if (kind === "SYNC_BLOCKED") {
      rateLimitResetMs = timestamp
      syncStatusMessage = "Refresh paused until the Raindrop rate limit resets"
    } else if (kind === "SYNC_COOLDOWN") {
      syncRetryAfterMs = timestamp
      syncStatusMessage = "Refresh paused after a recent failure"
    } else {
      var resetMs = timestamp
      syncRetryAfterMs = Math.max(Date.now() + 60 * 1000, resetMs)
      if (resetMs > Date.now()) rateLimitResetMs = resetMs
      var syncErrorMessage = parts.slice(2).join("\t") || "Could not refresh bookmarks"
      syncStatusMessage = snapshotLoaded
        ? lastSyncLabel() + " · Refresh failed"
        : "Could not load bookmarks. Try again when you are online."
      errorMessage = snapshotLoaded ? "Could not refresh bookmarks" : syncErrorMessage
    }
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

  Process {
    id: snapshotLoader
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.snapshotResponse = this.text }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root.snapshotErrorMessage = this.text.trim() }
    onExited: Qt.callLater(function() { root.applyLoadedSnapshot() })
  }

  Process {
    id: bookmarkSync
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.syncResponse = this.text
        root.handleBookmarkSyncResult(this.text)
      }
    }
    onExited: Qt.callLater(function() {
      if (!root.syncHandled) root.handleBookmarkSyncResult(root.syncResponse)
      if (root.syncAfterCurrent && root.tokenValidated) {
        root.syncAfterCurrent = false
        root.startBookmarkSync(false)
      }
    })
  }

  Process {
    id: coverSync
    stdout: StdioCollector { onStreamFinished: root.handleCoverIndex(this.text) }
    onExited: if (root.coverSyncForcePending) {
      root.coverSyncForcePending = false
      root.syncCovers(true)
    }
  }

  Process {
    id: tokenCheck
    onExited: function(exitCode, exitStatus) {
      root.checkingToken = false
      if (exitCode === 0) {
        if (root.tokenValidated) root.continueOpen()
        else if (root.snapshotLoaded) {
          root.needsToken = false
          if (Date.now() - root.lastFetchMs >= root.refreshIntervalMs) root.startBookmarkSync(false)
          root.validateTokenInBackground()
        } else root.validateToken()
      }
      else {
        if (root.snapshotLoaded) {
          root.needsToken = false
          root.syncStatusMessage = "Saved bookmarks are available offline. Reconnect to refresh."
        } else {
          root.needsToken = true
          Qt.callLater(function() { tokenField.forceActiveFocus() })
        }
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
        } else if (root.backgroundTokenValidation) {
          root.backgroundTokenValidation = false
          root.tokenValidated = true
          root.continueOpen()
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
        if (root.backgroundTokenValidation) {
          root.backgroundTokenValidation = false
          root.tokenValidated = false
          root.needsToken = false
          root.errorMessage = ""
          root.syncStatusMessage = "Saved bookmarks are available offline. Reconnect to refresh."
        } else if (/\b(401|403)\b/.test(detail)) {
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
    onTriggered: root.resumeAfterTokenSaved()
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
            text: root.filterText || (root.snapshotLoaded
              ? "Search " + root.bookmarks.length + " bookmarks…"
              : "Loading bookmarks…")
            textFormat: Text.PlainText
            color: root.foreground; opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily; font.pixelSize: Style.font.title
            elide: Text.ElideRight
          }
        }

        Row {
          visible: root.snapshotLoaded || root.tokenValidated || root.syncStatusMessage !== ""
          width: parent.width
          height: Math.max(Style.space(32), Style.font.caption + Style.spacing.controlPaddingY * 2)
          spacing: Style.spacing.sm

          Text {
            width: parent.width - refreshButton.width - reconnectButton.width - parent.spacing * 2
            anchors.verticalCenter: parent.verticalCenter
            text: root.syncStatusMessage || root.lastSyncLabel()
            textFormat: Text.PlainText
            color: root.foreground
            opacity: 0.62
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Button {
            id: refreshButton
            text: bookmarkSync.running ? "Refreshing…" : "Refresh"
            bordered: true
            enabled: !bookmarkSync.running && (root.snapshotLoaded || root.tokenValidated)
            foreground: root.foreground
            onClicked: root.refreshBookmarks()
          }

          Button {
            id: reconnectButton
            visible: root.snapshotLoaded && !root.tokenValidated
            text: "Reconnect"
            bordered: true
            foreground: root.foreground
            onClicked: root.reconnect()
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
          text: "Create an app in the Raindrop integrations menu, copy its Test token, then paste it below."
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
