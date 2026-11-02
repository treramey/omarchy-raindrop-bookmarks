import QtQuick
import Quickshell.Io

// Owns one token check and its optional atomic save. The request context never
// changes while a helper runs, including when the form is closed or reopened.
Item {
  id: root

  property string tokenPath: ""
  property string validateTokenPath: ""
  property string configureTokenPath: ""
  property bool presentationActive: false
  property int validationTimeoutSeconds: 20
  property int saveTimeoutSeconds: 5
  property string phase: "entry"
  property string errorKind: ""
  property string errorCode: ""
  property double retryAtMs: 0
  property double nowMs: Date.now()

  readonly property bool busy: request !== null
  readonly property bool foregroundBusy: busy && request.mode !== "background"
  readonly property int retrySeconds: Math.max(0, Math.ceil((retryAtMs - nowMs) / 1000))
  readonly property bool canSubmit: !busy && phase === "entry" && retrySeconds === 0
  readonly property string buttonText: busy
    ? (phase === "saving" ? "Saving token…" : phase === "entry" ? "Finishing check…" : "Checking token…")
    : retrySeconds > 0 ? "Retry in " + retrySeconds + "s" : "Connect Raindrop"
  readonly property string errorMessage: tokenErrorMessage(errorKind, errorCode)

  property var request: null
  property bool discardResult: false
  property string step: "idle"
  property bool helperStarted: false
  property var helperExit: null
  property string validationOutput: ""
  property double stepStartedMs: 0

  signal validated(string mode)
  signal failed(string mode, string kind, string message)

  function tokenErrorMessage(kind, code) {
    if (kind === "input") {
      if (code === "empty") return "Paste your Raindrop test token first."
      if (code === "size") return "The token is too long. Paste only the Test token from Raindrop."
      return "The token must be a single line. Paste only the Test token from Raindrop."
    }
    if (kind === "auth") return "Raindrop didn't accept this token. Copy a new Test token and try again."
    if (kind === "rate-limit") return retrySeconds > 0
      ? "Raindrop is limiting requests. Try again in " + retrySeconds + " seconds."
      : "You can retry the token check now."
    if (kind === "network") return "Could not reach Raindrop. Check your connection and try again."
    if (kind === "timeout") return code === "save"
      ? "Saving the token timed out. Check the token directory and try again."
      : "The token check timed out. Check your connection and try again."
    if (kind === "service") return "Raindrop could not complete the token check. Try again later."
    if (kind === "save") return "Could not save your token. Check the token file path, directory permissions, and free disk space, then retry."
    if (kind === "local") {
      if (code === "token-file") return "The saved token file cannot be read. Paste your Test token again."
      if (code === "token-path") return "The token file path must be absolute. Check RAINDROP_TOKEN_FILE, then retry."
      return "Could not run the token operation. Check the plugin installation and required tools, then retry."
    }
    return ""
  }

  function prepareOpen() {
    nowMs = Date.now()
    if (!busy && phase !== "success") {
      phase = "entry"
      errorKind = retrySeconds ? "rate-limit" : ""
      errorCode = ""
    }
  }

  function enter() {
    nowMs = Date.now()
    if (busy && request.mode === "submitted") return
    // Let an existing check finish under its deadline, but never let its late
    // result dismiss this form or authorize a different submitted token.
    if (busy) discardResult = true
    phase = "entry"
    errorKind = retrySeconds ? "rate-limit" : ""
    errorCode = ""
  }

  function clearSuccess() {
    if (!busy) phase = "entry"
  }

  function rejectToken(mode, kind, code) {
    phase = "entry"
    errorKind = kind
    errorCode = code
    failed(mode, kind, errorMessage)
  }

  function submitToken(value) {
    if (busy || phase === "success") return false
    nowMs = Date.now()
    if (retrySeconds) { errorKind = "rate-limit"; return false }
    var token = String(value || "").trim()
    if (!token) { rejectToken("submitted", "input", "empty"); return false }
    if (/[\r\n]/.test(token)) { rejectToken("submitted", "input", "multiline"); return false }
    return startTokenCheck("submitted", token)
  }

  function validateStored(background) {
    if (busy || phase === "success") return false
    nowMs = Date.now()
    var mode = background ? "background" : "stored"
    if (retrySeconds) { rejectToken(mode, "rate-limit", "http"); return false }
    return startTokenCheck(mode, "")
  }

  function startTokenCheck(mode, token) {
    if (!tokenPath.startsWith("/")) { rejectToken(mode, "local", "token-path"); return false }
    request = Object.freeze({
      mode: mode, token: token, tokenPath: tokenPath,
      validator: validateTokenPath, writer: configureTokenPath,
      validationSeconds: Math.max(1, validationTimeoutSeconds), saveSeconds: Math.max(1, saveTimeoutSeconds)
    })
    discardResult = false
    errorKind = ""
    errorCode = ""
    if (mode !== "background") phase = "checking"
    step = "validating"
    helperStarted = false
    helperExit = null
    validationOutput = ""
    stepStartedMs = Date.now()
    validator.stdinEnabled = true
    validator.command = ["timeout", "--kill-after=1", String(request.validationSeconds),
      "bash", request.validator, "--json"]
    if (mode !== "submitted") validator.command = validator.command.concat(["--file", request.tokenPath])
    startupGuard.restart()
    validator.running = true
    return true
  }

  function releaseRequest() {
    startupGuard.stop()
    step = "idle"
    request = null
    helperExit = null
    validationOutput = ""
    helperStarted = false
    discardResult = false
  }

  function obsoleteRequest() {
    return discardResult || request.tokenPath !== tokenPath
  }

  function finishFailure(kind, code, retryAfterSeconds) {
    var mode = request.mode
    var obsolete = obsoleteRequest()
    nowMs = Date.now()
    if (kind === "rate-limit") retryAtMs = Math.max(retryAtMs, nowMs + Math.max(1, retryAfterSeconds || 60) * 1000)
    releaseRequest()
    phase = "entry"
    if (!obsolete) rejectToken(mode, kind, code)
    else if (kind === "rate-limit") { errorKind = kind; errorCode = code }
  }

  function finishSuccess() {
    var mode = request.mode
    var obsolete = obsoleteRequest()
    releaseRequest()
    if (obsolete) { phase = "entry"; return }
    phase = mode === "background" ? "entry" : "success"
    errorKind = ""
    errorCode = ""
    validated(mode)
  }

  function timedOut(seconds) {
    return helperExit && (helperExit.code === 124 || helperExit.code === 137
      || (helperExit.status !== 0 && Date.now() - stepStartedMs >= seconds * 1000))
  }

  function validationReply() {
    if (validationOutput.length > 4096) return null
    try {
      var reply = JSON.parse(validationOutput)
      var statuses = ["ok", "input", "auth", "rate-limit", "network", "timeout", "service", "local"]
      if (reply && statuses.indexOf(reply.status) >= 0 && typeof reply.code === "string"
          && Number.isInteger(reply.retryAfterSeconds) && reply.retryAfterSeconds >= 0 && reply.retryAfterSeconds <= 86400)
        return reply
    } catch (error) {
      // A missing or malformed report never authorizes saving credentials.
    }
    return null
  }

  function settleValidation() {
    if (step !== "validating" || validator.running) return
    if (!helperStarted) { finishFailure("local", "start", 0); return }
    if (!helperExit) return
    if (timedOut(request.validationSeconds)) { finishFailure("timeout", "request", 0); return }
    var reply = validationReply()
    if (!reply) { finishFailure("local", "protocol", 0); return }
    if (reply.status !== "ok") { finishFailure(reply.status, reply.code, reply.retryAfterSeconds); return }
    if (helperExit.code !== 0 || helperExit.status !== 0) { finishFailure("local", "protocol", 0); return }
    if (obsoleteRequest() || request.mode !== "submitted") { finishSuccess(); return }
    // Only this immutable, successfully checked submission can reach the writer.
    phase = "saving"
    step = "saving"
    helperStarted = false
    helperExit = null
    stepStartedMs = Date.now()
    writer.stdinEnabled = true
    writer.command = ["timeout", "--kill-after=1", String(request.saveSeconds),
      "bash", request.writer, request.tokenPath]
    startupGuard.restart()
    writer.running = true
  }

  function settleWriter() {
    if (step !== "saving" || writer.running) return
    if (!helperStarted) { finishFailure("local", "start", 0); return }
    if (!helperExit) return
    if (timedOut(request.saveSeconds)) finishFailure("timeout", "save", 0)
    else if (helperExit.code === 0 && helperExit.status === 0) finishSuccess()
    else if (helperExit.code === 126 || helperExit.code === 127) finishFailure("local", "writer", 0)
    else finishFailure("save", "write", 0)
  }

  Process {
    id: validator
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.validationOutput = this.text }
    stderr: StdioCollector {}
    onStarted: {
      root.helperStarted = true
      startupGuard.stop()
      if (root.request.mode === "submitted") write(root.request.token + "\n")
      stdinEnabled = false
    }
    onExited: function(exitCode, exitStatus) {
      root.helperExit = { code: exitCode, status: exitStatus }
      Qt.callLater(root.settleValidation)
    }
    onRunningChanged: if (!running) Qt.callLater(root.settleValidation)
  }

  Process {
    id: writer
    stderr: StdioCollector {}
    onStarted: {
      root.helperStarted = true
      startupGuard.stop()
      write(root.request.token + "\n")
      stdinEnabled = false
    }
    onExited: function(exitCode, exitStatus) {
      root.helperExit = { code: exitCode, status: exitStatus }
      Qt.callLater(root.settleWriter)
    }
    onRunningChanged: if (!running) Qt.callLater(root.settleWriter)
  }

  Timer {
    id: startupGuard
    interval: 500
    onTriggered: {
      // Failed-to-start processes need not emit exited. Do not leave the form
      // busy when the launcher itself is missing, even without a running signal.
      if (root.step === "validating") root.settleValidation()
      else if (root.step === "saving") root.settleWriter()
    }
  }

  Timer {
    interval: 1000
    running: root.presentationActive && root.retrySeconds > 0
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }
}
