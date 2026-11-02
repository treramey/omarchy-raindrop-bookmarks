import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons

ShellRoot {
  id: fixture

  property int opens: 0
  property int refreshes: 0
  property int reconnects: 0
  property int closes: 0
  property var moves: []
  readonly property string title: "<img src='https://example.invalid/title'>"
  readonly property string domain: "<b>untrusted domain</b>"
  readonly property string tag: "<i>untrusted tag</i>"
  readonly property string error: "<img src='https://example.invalid/error'>"
  readonly property var bookmarks: {
    var items = [{ _id: 1, title: title, domain: domain, tags: [tag] }]
    for (var index = 2; index <= 16; index++)
      items.push({ _id: index, title: "Bookmark " + index, domain: "example.invalid", tags: [] })
    return items
  }
  property bool narrowPhase: false

  FloatingWindow {
    id: window
    visible: true
    implicitWidth: 760
    implicitHeight: 520
    color: Commons.Color.menu.background

    BookmarkBrowser {
      id: browser
      width: fixture.narrowPhase ? 420 : 760
      height: fixture.narrowPhase ? 360 : 520
      active: true
      results: fixture.bookmarks
      selectedIndex: 0
      canRefresh: true
      errorText: fixture.error
      onQueryEdited: function(text) { query = text }
      onMoveRequested: function(delta) { fixture.moves.push(delta) }
      onOpenRequested: fixture.opens++
      onRefreshRequested: fixture.refreshes++
      onReconnectRequested: fixture.reconnects++
      onCloseRequested: fixture.closes++
    }
  }

  function verify(condition, message) {
    if (!condition) throw new Error(message)
  }

  function findItem(item, name) {
    if (item.objectName === name) return item
    for (var index = 0; index < item.children.length; index++) {
      var found = findItem(item.children[index], name)
      if (found) return found
    }
    return null
  }

  function verifyPlainText(item, value) {
    var count = 0
    if (item.text === value && item.textFormat !== undefined) {
      verify(item.textFormat === Text.PlainText, "Markup interpreted as rich text: " + value)
      verify(item.visible && item.width > 0, "Bookmark metadata is not visible: " + value)
      count++
    }
    for (var index = 0; index < item.children.length; index++)
      count += verifyPlainText(item.children[index], value)
    return count
  }

  function press(key, modifiers) {
    var event = { key: key, modifiers: modifiers || Qt.NoModifier, accepted: false }
    browser.handleKey(event)
    verify(event.accepted, "Unhandled navigation key: " + key)
  }

  function checkCommands() {
    var input = findItem(browser, "bookmarkSearch")
    // TextInput.insert follows the same committed-text path as an input method.
    input.insert(0, "日本語")
    verify(browser.query === "日本語", "Composed text did not reach the query")
    browser.query = "saved search"
    verify(input.text === browser.query, "External query change did not reach the input")
    press(Qt.Key_K, Qt.ControlModifier)
    verify(browser.actionsOpen && input.readOnly, "Action menu did not protect the search input")
    press(Qt.Key_Escape)
    verify(!browser.actionsOpen && browser.query === "saved search", "Escape cleared the query behind the action menu")
    press(Qt.Key_Escape)
    verify(browser.query === "" && closes === 0, "Escape closed instead of clearing search")
    press(Qt.Key_Escape)
    verify(closes === 1, "Escape did not close an empty search")

    press(Qt.Key_Return)
    verify(opens === 1, "Enter did not request the selected bookmark")
    press(Qt.Key_K, Qt.ControlModifier)
    press(Qt.Key_Down)
    press(Qt.Key_Return)
    verify(refreshes === 1 && !browser.actionsOpen, "Action menu did not request refresh")
    browser.canRefresh = false
    browser.refreshing = true
    press(Qt.Key_K, Qt.ControlModifier)
    press(Qt.Key_Down)
    verify(browser.actionIndex === 0, "Disabled refresh action was selected")
    press(Qt.Key_Escape)
    press(Qt.Key_R, Qt.ControlModifier)
    verify(refreshes === 1, "Disabled refresh shortcut still ran")

    browser.results = []
    browser.selectedIndex = -1
    press(Qt.Key_Return)
    verify(opens === 1, "Empty results could still open a bookmark")
    press(Qt.Key_K, Qt.ControlModifier)
    verify(browser.actionIndex === -1, "An unavailable action was selected")
    press(Qt.Key_Return)
    verify(opens === 1 && refreshes === 1, "Unavailable action was activated")
    browser.reconnectRequired = true
    press(Qt.Key_Escape)
    press(Qt.Key_K, Qt.ControlModifier)
    press(Qt.Key_Return)
    verify(reconnects === 1 && !browser.actionsOpen, "Reconnect was not keyboard accessible")
    browser.canRefresh = true
    press(Qt.Key_R, Qt.ControlModifier)
    verify(refreshes === 2, "Refresh shortcut did not run")
    press(Qt.Key_Up)
    press(Qt.Key_PageDown)
    verify(moves.join(",") === "-1,6", "Result navigation changed")
    browser.results = fixture.bookmarks
    browser.selectedIndex = 0
    browser.reconnectRequired = false
    browser.refreshing = false
    var chord = { key: Qt.Key_K, modifiers: Qt.ControlModifier | Qt.AltModifier, accepted: false }
    browser.handleKey(chord)
    verify(!chord.accepted && !browser.actionsOpen, "Actions stole an Alt-modified shortcut")
  }

  function checkTheme() {
    Commons.Color.background = "#f5f5f0"
    Commons.Color.foreground = "#202422"
    Commons.Color.accent = "#3659a2"
    Commons.Color.shellValues = ({ "menu.selected-border-width": "2" })
    verify(Qt.colorEqual(browser.foreground, Commons.Color.menu.text), "Browser lost the live theme foreground")
    verify(Qt.colorEqual(browser.selectedText, Commons.Color.menu.selectedText), "Browser lost the live theme selection text")
    var row = findItem(browser, "bookmarkResults").itemAtIndex(0)
    verify(Qt.colorEqual(row.color, Commons.Color.menu.selectedBackground), "Selected row lost the live theme background")
    verify(Border.left(row.borderSpec) === 2, "Selected row ignored the theme border width")
  }

  function findShortcutLabel(item, text) {
    if (item.visible && item.text === text && item.textFormat !== undefined
        && item.parent.contentLeftInset !== undefined) return item
    for (var child of item.children) {
      var found = findShortcutLabel(child, text)
      if (found) return found
    }
    return null
  }

  function checkShortcutBoxes() {
    var control = findShortcutLabel(browser, "Ctrl")
    var key = findShortcutLabel(browser, "K")
    verify(control && key && control.parent !== key.parent, "Ctrl and K need separate key boxes")
    var controlBox = control.parent
    var keyBox = key.parent
    var controlPosition = controlBox.mapToItem(browser, 0, 0)
    var keyPosition = keyBox.mapToItem(browser, 0, 0)
    verify(controlPosition.x + controlBox.width < keyPosition.x
      && Math.abs(controlPosition.y - keyPosition.y) < 0.5,
      "Shortcut key boxes overlap or are not aligned: Ctrl=" + controlPosition + " width=" + controlBox.width
        + ", K=" + keyPosition + " width=" + keyBox.width)
    verify(controlPosition.x >= 0 && keyPosition.x + keyBox.width <= browser.width,
      "Shortcut key boxes extend outside the browser")
  }

  function checkVisibleGeometry(item) {
    if (item.visible && item.textFormat !== undefined)
      verify(item.width >= 0 && item.height >= 0, "Negative text geometry: " + item.text)
    if (item.visible && ["↵", "Ctrl", "K", "esc"].indexOf(item.text) !== -1
        && item.parent.contentLeftInset !== undefined) {
      var textLeft = item.x + (item.width - item.contentWidth) / 2
      var textRight = textLeft + item.contentWidth
      var padding = item.text === "↵" ? Style.spacing.sm : Style.spacing.controlPaddingX
      verify(textLeft - item.parent.borderLeft >= padding - 0.5
        && item.parent.width - item.parent.borderRight - textRight >= padding - 0.5,
        "Shortcut text needs horizontal padding inside its border: " + item.text)
      if (item.text === "↵")
        verify(item.parent.width <= Math.max(Style.space(20), item.contentWidth
          + padding * 2 + item.parent.borderLeft + item.parent.borderRight) + 0.5,
          "Enter shortcut should stay compact")
      verify(item.width >= item.contentWidth, "Shortcut text was clipped: " + item.text)
    }
    for (var index = 0; index < item.children.length; index++)
      checkVisibleGeometry(item.children[index])
  }

  function finishChecks() {
    try {
      var list = findItem(browser, "bookmarkResults")
      list.forceLayout()
      checkVisibleGeometry(browser)
      checkShortcutBoxes()
      var selected = list.itemAtIndex(browser.selectedIndex)
      verify(selected && selected.y < list.contentY + list.height
        && selected.y + selected.height > list.contentY, "Keyboard selection was not scrolled into view")
      browser.toggleActions()
      browser.active = false
      verify(!browser.actionsOpen, "Closing the browser retained the action menu")
      console.log("Bookmark browser checks passed")
      Qt.exit(0)
    } catch (error) {
      console.error("Bookmark browser check failed: " + error)
      Qt.exit(1)
    }
  }

  Timer {
    id: layoutSettle
    interval: 32
    onTriggered: fixture.finishChecks()
  }

  Timer {
    interval: 16
    running: true
    repeat: true
    onTriggered: {
      try {
        var list = fixture.findItem(browser, "bookmarkResults")
        if (!list.itemAtIndex(0)) return
        stop()
        for (var value of [fixture.title, fixture.domain, fixture.tag, fixture.error])
          fixture.verify(fixture.verifyPlainText(browser, value) > 0, "Missing plain-text metadata: " + value)
        fixture.checkCommands()
        fixture.checkVisibleGeometry(browser)
        fixture.checkShortcutBoxes()
        fixture.checkTheme()
        fixture.narrowPhase = true
        Style.fontBaseSize = 18
        browser.selectedIndex = 15
        // Nested shortcut rows need a polish pass after font scaling.
        layoutSettle.start()
      } catch (error) {
        console.error("Bookmark browser check failed: " + error)
        Qt.exit(1)
      }
    }
  }
}
