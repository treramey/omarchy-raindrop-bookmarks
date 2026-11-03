import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
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
  readonly property bool savingToken: connection.foregroundBusy
  property bool tokenValidated: false
  property bool showToken: false
  readonly property string onboardingPhase: connection.phase
  readonly property string onboardingError: connection.errorMessage
  property bool snapshotLoaded: false
  property bool snapshotLoading: false
  property string snapshotResponse: ""
  property string snapshotErrorMessage: ""
  property bool snapshotHandled: false
  property string syncResponse: ""
  property bool syncHandled: false
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

  property color background: Commons.Color.menu.background
  property color foreground: Commons.Color.menu.text
  property color scrim: Commons.Color.menu.scrim
  property color selectedBackground: Commons.Color.menu.selectedBackground
  property color selectedText: Commons.Color.menu.selectedText
  property var borderSpec: Border.surfaceSpec("menu", "border", Commons.Color.menu.border, Math.max(1, Style.space(2)))
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int cardWidth: Math.min(Style.space(needsToken ? 580 : 760), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(needsToken ? 430 : 520), panel.height - Style.gapsOut * 2)
  property double statusNowMs: Date.now()

  function open(payloadJson) {
    showToken = false
    opened = true
    filterText = ""
    selectedIndex = -1
    errorMessage = ""
    syncStatusMessage = "Loading saved bookmarks…"
    connection.prepareOpen()
    needsToken = connection.foregroundBusy || connection.phase === "success"
    if (connection.phase !== "success") tokenValidated = false
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
      if (!tokenSavedPendingSnapshot && connection.phase !== "success") tokenValidated = false
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
        + "&& [[ \"$size\" =~ ^[0-9]+$ ]] && (( size > 0 && size <= 8193 ))",
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
    Qt.callLater(function() { browser.focusSearch() })
  }

  function saveToken() {
    connection.submitToken(tokenField.text)
  }

  function validateToken() {
    if (connection.busy) return
    needsToken = true
    connection.validateStored(false)
  }

  function validateTokenInBackground() {
    connection.validateStored(true)
  }

  function reconnect() {
    connection.enter()
    showToken = false
    needsToken = true
    Qt.callLater(function() { tokenField.forceActiveFocus() })
  }

  function lastSyncLabel() {
    if (!lastFetchMs) return "No saved bookmarks yet"
    var minutes = Math.max(0, Math.floor((statusNowMs - lastFetchMs) / 60000))
    if (minutes < 1) return "Synced just now"
    if (minutes < 60) return "Synced " + minutes + "m ago"
    if (minutes < 1440) return "Synced " + Math.floor(minutes / 60) + "h ago"
    return "Synced " + Math.floor(minutes / 1440) + "d ago"
  }

  function refreshBookmarks() {
    startBookmarkSync(true)
  }

  function resumeAfterTokenSaved() {
    connection.clearSuccess()
    needsToken = false
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
    searchDebounce.stop()
  }

  function toggle() { opened ? close() : open("{}") }

  function scheduleSearch() {
    searchDebounce.restart()
  }

  function filter(preserveSelection) {
    searchDebounce.stop()
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
        ? "Refresh failed · using saved bookmarks"
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
      if (root.needsToken || connection.foregroundBusy || connection.phase === "success") return
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
          root.syncStatusMessage = "Reconnect to refresh · using saved bookmarks"
        } else {
          root.needsToken = true
          Qt.callLater(function() { tokenField.forceActiveFocus() })
        }
      }
    }
  }

  RaindropConnection {
    id: connection
    tokenPath: root.tokenPath
    validateTokenPath: root.validateTokenPath
    configureTokenPath: root.configureTokenPath
    presentationActive: root.opened && root.needsToken
    onRetryAtMsChanged: root.rateLimitResetMs = Math.max(root.rateLimitResetMs, retryAtMs)
    onBusyChanged: if (!busy && root.opened && root.needsToken && phase === "entry")
      Qt.callLater(function() { tokenField.forceActiveFocus() })
    onValidated: function(mode) {
      root.tokenValidated = true
      root.errorMessage = ""
      if (mode === "background") root.continueOpen()
      else {
        tokenField.text = ""
        root.showToken = false
        connectionSuccess.restart()
      }
    }
    onFailed: function(mode, kind, message) {
      root.tokenValidated = false
      if (mode === "background" && root.snapshotLoaded) {
        root.needsToken = false
        root.errorMessage = ""
        root.syncStatusMessage = kind === "auth" || kind === "input" || kind === "local"
          ? "Reconnect to refresh · using saved bookmarks"
          : kind === "rate-limit" ? "Raindrop rate limit reached · using saved bookmarks"
          : "Raindrop unreachable · using saved bookmarks"
      } else {
        root.needsToken = true
        if (root.opened) Qt.callLater(function() { tokenField.forceActiveFocus() })
      }
    }
  }

  Timer {
    id: searchDebounce
    interval: 275
    repeat: false
    onTriggered: root.filter()
  }

  Timer {
    interval: 60000
    running: root.opened
    triggeredOnStart: true
    repeat: true
    onTriggered: root.statusNowMs = Date.now()
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

      Shortcut {
        sequence: "Escape"
        enabled: root.opened && root.needsToken
        onActivated: root.close()
      }

      BookmarkBrowser {
        id: browser
        anchors.fill: parent
        anchors.topMargin: card.borderTop
        anchors.rightMargin: card.borderRight
        anchors.bottomMargin: card.borderBottom
        anchors.leftMargin: card.borderLeft
        visible: !root.needsToken
        active: root.opened && !root.needsToken
        query: root.filterText
        results: root.results
        selectedIndex: root.selectedIndex
        coverLookup: root.coverLookup
        statusText: root.syncStatusMessage.indexOf("Synced ") === 0 || !root.syncStatusMessage
          ? root.lastSyncLabel() : root.syncStatusMessage
        lastSyncMs: root.lastFetchMs
        errorText: root.errorMessage
        loading: root.snapshotLoading || (bookmarkSync.running && !root.snapshotLoaded)
        refreshing: bookmarkSync.running
        canRefresh: !bookmarkSync.running && (root.snapshotLoaded || root.tokenValidated)
        reconnectRequired: root.snapshotLoaded && !root.tokenValidated
        foreground: root.foreground
        selectedBackground: root.selectedBackground
        selectedText: root.selectedText
        fontFamily: root.fontFamily
        onQueryEdited: function(text) {
          root.filterText = text
          if (text) root.scheduleSearch()
          else root.filter()
        }
        onMoveRequested: function(delta) { root.select(delta) }
        onSelectionRequested: function(index) { root.selectedIndex = index }
        onOpenRequested: root.openCurrent()
        onRefreshRequested: root.refreshBookmarks()
        onReconnectRequested: root.reconnect()
        onCloseRequested: root.close()
      }

      Column {
        visible: root.needsToken
        width: Math.min(parent.width - card.contentLeftInset - card.contentRightInset, Style.space(500))
        anchors.centerIn: parent
        spacing: Style.spacing.panelGap

        Text {
          width: parent.width
          text: "Raindrop Bookmarks"
          textFormat: Text.PlainText
          color: root.foreground
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: root.onboardingPhase === "success" ? Text.AlignHCenter : Text.AlignLeft
        }

        Text {
          width: parent.width
          text: root.onboardingPhase === "success" ? "Connected" : "Connect Raindrop"
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
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
            objectName: "raindropTokenInput"
            width: parent.width - revealToken.width - parent.spacing
            password: !root.showToken
            enabled: root.onboardingPhase === "entry" && !root.savingToken
            placeholderText: "Paste token"
            foreground: root.foreground
            font.family: root.fontFamily
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
            fontFamily: root.fontFamily
            onClicked: root.showToken = !root.showToken
          }
        }

        Text {
          visible: root.onboardingPhase !== "success" && root.onboardingError !== ""
          width: parent.width
          text: root.onboardingError
          textFormat: Text.PlainText
          color: Commons.Color.urgent
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
            fontFamily: root.fontFamily
            onClicked: {
              root.close()
              Quickshell.execDetached(["xdg-open", "https://app.raindrop.io/settings/integrations"])
            }
          }

          Button {
            text: connection.buttonText
            objectName: "raindropConnectButton"
            selected: true
            bordered: true
            enabled: connection.canSubmit && tokenField.text.trim() !== ""
            opacity: connection.busy ? 0.72 : (enabled ? 1 : 0.45)
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.saveToken()
          }
        }

        Text {
          visible: root.onboardingPhase !== "success"
          width: parent.width
          text: "Your token is stored locally with private file permissions."
          textFormat: Text.PlainText
          color: root.foreground
          opacity: 0.7
          wrapMode: Text.WordWrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
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
