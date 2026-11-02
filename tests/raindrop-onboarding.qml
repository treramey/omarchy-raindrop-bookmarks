import QtQuick
import Quickshell

ShellRoot {
  id: fixture
  property int stage: 0
  readonly property string directory: Quickshell.env("TEST_CONNECTION_DIR")
  readonly property string repo: Quickshell.env("TEST_REPO_DIR")

  RaindropBookmarks {
    id: bookmarks
    // Deliberately never call open() or map this overlay on the real desktop.
    tokenPath: fixture.directory + "/root-token"
    validateTokenPath: fixture.directory + "/helpers/ok"
    configureTokenPath: fixture.repo + "/configure-token"
    coverSyncPath: fixture.directory + "/helpers/noop"
    snapshotLoaded: true
    lastFetchMs: Date.now()
  }

  function verify(condition, message) {
    if (!condition) throw new Error(message)
  }

  function findObject(object, name) {
    if (!object) return null
    if (object.objectName === name) return object
    if (object.contentItem) {
      var contentMatch = findObject(object.contentItem, name)
      if (contentMatch) return contentMatch
    }
    var children = object.data || object.children || []
    for (var index = 0; index < children.length; index++) {
      var match = findObject(children[index], name)
      if (match) return match
    }
    return null
  }

  Timer {
    interval: 16
    running: true
    repeat: true
    onTriggered: {
      try {
        var input = fixture.findObject(bookmarks, "raindropTokenInput")
        var connect = fixture.findObject(bookmarks, "raindropConnectButton")
        if (!input || !connect) return
        if (fixture.stage === 0) {
          bookmarks.validateTokenInBackground()
          bookmarks.reconnect()
          input.text = "rejected-replacement"
          bookmarks.validateTokenPath = fixture.directory + "/helpers/auth"
          bookmarks.saveToken()
          fixture.verify(bookmarks.needsToken && input.enabled && !connect.enabled, "Reconnecting did not keep a safe waiting form")
          fixture.verify(connect.text === "Finishing check…", "Background check had no waiting feedback")
          fixture.stage = 1
        } else if (fixture.stage === 1 && connect.enabled) {
          fixture.verify(!bookmarks.tokenValidated && input.text === "rejected-replacement", "Old result authorized or discarded the new token")
          bookmarks.saveToken()
          fixture.stage = 2
        } else if (fixture.stage === 2 && bookmarks.onboardingError) {
          fixture.verify(bookmarks.needsToken && bookmarks.onboardingPhase === "entry" && !bookmarks.tokenValidated, "Rejected token did not leave a retryable form")
          fixture.verify(bookmarks.onboardingError.indexOf("didn't accept") >= 0, "Authentication error was misclassified")
          bookmarks.snapshotHandled = false
          bookmarks.snapshotResponse = JSON.stringify({ version: 1, syncedAt: Math.floor(Date.now() / 1000), bookmarks: [] })
          bookmarks.applyLoadedSnapshot()
          fixture.stage = 3
        } else if (fixture.stage === 3 && connect.enabled) {
          fixture.verify(bookmarks.needsToken && input.enabled && bookmarks.onboardingError, "Cached data dismissed the failed reconnect form")
          bookmarks.validateTokenPath = fixture.directory + "/helpers/ok"
          input.text = "validated-token"
          bookmarks.saveToken()
          fixture.stage = 4
        } else if (fixture.stage === 4 && bookmarks.onboardingPhase === "success") {
          fixture.verify(bookmarks.tokenValidated && !bookmarks.onboardingError && input.text === "", "Successful retry did not complete onboarding safely")
          console.log("Raindrop connection checks passed")
          Qt.exit(0)
        }
      } catch (error) {
        console.error("Raindrop onboarding check failed: " + error)
        Qt.exit(1)
      }
    }
  }
}
