import QtQuick
import Quickshell

ShellRoot {
  id: fixture
  readonly property string directory: Quickshell.env("TEST_CONNECTION_DIR")
  readonly property string repo: Quickshell.env("TEST_REPO_DIR")
  property int index: -1
  property var current: null
  property bool waitingRetry: false
  property int successes: 0
  property int failures: 0
  property int beforeSuccesses: 0
  property int beforeFailures: 0
  property string lastMode: ""
  readonly property var cases: [
    { name: "discard-background", helper: "ok", file: "race-token", kind: "ignored" },
    { name: "reject-replacement", helper: "auth", file: "race-token", kind: "auth" },
    { name: "recover-auth", helper: "ok", file: "success-token", kind: "ok" },
    { name: "duplicate-and-reopen", helper: "ok", file: "duplicate-token", kind: "ok" },
    { name: "missing-helper", helper: "missing", kind: "local" },
    { name: "recover-helper", helper: "ok", file: "recovered-helper-token", kind: "ok" },
    { name: "save-failure", helper: "ok", file: "not-a-directory/token", kind: "save" },
    { name: "missing-writer", helper: "ok", writer: "missing", kind: "local" },
    { name: "recover-save", helper: "ok", file: "recovered-save-token", kind: "ok" },
    { name: "malformed", helper: "malformed", kind: "local" },
    { name: "false-ok", helper: "false-ok", kind: "local" },
    { name: "empty", helper: "ok", kind: "input", input: "" },
    { name: "multiline", helper: "ok", kind: "input", input: "first\nsecond" },
    { name: "oversized", helper: "real", kind: "input", input: "x".repeat(8193) },
    { name: "network", helper: "network", kind: "network" },
    { name: "service", helper: "service", kind: "service" },
    { name: "validation-timeout", helper: "hang", kind: "timeout" },
    { name: "save-timeout", helper: "ok", writer: "writer-hang", file: "timeout-token", kind: "timeout" },
    { name: "background-auth", helper: "auth", file: "stored-token", kind: "auth", stored: true, background: true },
    { name: "stored", helper: "ok", file: "stored-token", kind: "ok", stored: true, background: false },
    { name: "rate", helper: "rate", kind: "rate-limit" },
    { name: "rate-retry", helper: "ok", file: "rate-retry-token", kind: "ok" }
  ]

  RaindropConnection {
    id: connection
    presentationActive: true
    validationTimeoutSeconds: 1
    saveTimeoutSeconds: 1
    onValidated: function(mode) { fixture.successes++; fixture.lastMode = mode }
    onFailed: function(mode, kind, message) { fixture.failures++; fixture.lastMode = mode }
    onBusyChanged: if (!busy && fixture.current) Qt.callLater(fixture.finishCase)
    onRetrySecondsChanged: if (fixture.waitingRetry && retrySeconds === 0) {
      fixture.waitingRetry = false
      Qt.callLater(fixture.startCase)
    }
  }

  function verify(condition, message) {
    if (!condition) throw new Error((current ? current.name + ": " : "") + message)
  }

  function fail(error) {
    console.error("Raindrop connection check failed: " + error)
    Qt.exit(1)
  }

  function nextCase() {
    try {
      index++
      if (index === cases.length) {
        console.log("Raindrop connection checks passed")
        Qt.exit(0)
        return
      }
      current = Quickshell.env("TEST_MISSING_LAUNCHER")
        ? { name: "missing-launcher", helper: "ok", kind: "local" } : cases[index]
      if (current.name === "rate-retry" && connection.retrySeconds > 0) {
        waitingRetry = true
        return
      }
      startCase()
    } catch (error) { fail(error) }
  }

  function startCase() {
    try {
      connection.clearSuccess()
      connection.enter()
      connection.tokenPath = directory + "/" + (current.file || "failed-token")
      connection.validateTokenPath = current.helper === "real" ? repo + "/validate-token" : directory + "/helpers/" + current.helper
      connection.configureTokenPath = current.writer ? directory + "/helpers/" + current.writer : repo + "/configure-token"
      beforeSuccesses = successes
      beforeFailures = failures
      if (current.name === "discard-background") {
        verify(connection.validateStored(true), "Background check did not start")
        connection.enter()
        verify(!connection.submitToken("rejected-replacement"), "Submission replaced an active background request")
        verify(connection.phase === "entry" && !connection.canSubmit, "Waiting form was not recoverable")
        verify(connection.buttonText === "Finishing check…", "Missing waiting feedback")
      } else {
        var accepted = current.stored ? connection.validateStored(current.background)
          : connection.submitToken(current.input === undefined ? "validated-token" : current.input)
        if (current.name === "duplicate-and-reopen") {
          connection.prepareOpen()
          verify(connection.phase === "checking", "Reopening reset an in-flight check")
          verify(!connection.submitToken("different-token"), "Duplicate submission replaced a request")
        }
        if (!accepted) Qt.callLater(finishCase)
      }
    } catch (error) { fail(error) }
  }

  function finishCase() {
    if (!current || connection.busy) return
    try {
      verify(connection.request === null, "Finished request retained its token")
      if (current.kind === "ok") {
        verify(successes === beforeSuccesses + 1 && failures === beforeFailures, "Unexpected completion signals")
        verify(connection.phase === "success" && !connection.errorMessage, "Connection did not succeed")
        verify(lastMode === (current.stored ? "stored" : "submitted"), "Request mode changed")
      } else if (current.kind === "ignored") {
        verify(successes === beforeSuccesses && failures === beforeFailures, "Discarded background result was published")
        verify(connection.phase === "entry" && connection.canSubmit, "Form did not recover after the old check")
      } else {
        verify(successes === beforeSuccesses && failures === beforeFailures + 1, "A failed check authorized a save")
        verify(connection.phase === "entry" && connection.errorKind === current.kind, "Wrong recovery state")
        verify(connection.errorMessage.length > 0, "Failure had no user feedback")
        if (current.name === "oversized") verify(connection.errorMessage.indexOf("too long") >= 0, "Input error became a connection error")
        if (current.name === "save-timeout") verify(connection.errorMessage.indexOf("Saving") >= 0, "Save timeout became a network error")
        if (current.kind === "rate-limit") {
          verify(!connection.canSubmit && connection.retrySeconds > 0, "Rate limit did not disable retries")
          verify(!connection.submitToken("validated-token") && !connection.busy, "Rate limit was bypassed")
        } else verify(connection.canSubmit, "Failure left the form disabled")
      }
      if (Quickshell.env("TEST_MISSING_LAUNCHER")) {
        console.log("Raindrop connection checks passed")
        Qt.exit(0)
        return
      }
      current = null
      Qt.callLater(nextCase)
    } catch (error) { fail(error) }
  }

  Component.onCompleted: Qt.callLater(nextCase)
}
