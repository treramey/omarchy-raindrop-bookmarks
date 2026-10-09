import QtQuick
import Quickshell
import qs.Commons as Commons

ShellRoot {
  RaindropBookmarks { id: bookmarks }

  Timer {
    interval: 250
    running: true
    onTriggered: {
      // Exercise live theme updates, not just the initial default colors.
      Commons.Color.background = "#123456"
      Commons.Color.foreground = "#abcdef"
      Commons.Color.accent = "#fedcba"
      Commons.Color.shellValues = ({})
      Qt.callLater(function() {
        var roles = {
          background: "background", foreground: "text", scrim: "scrim",
          selectedBackground: "selectedBackground", selectedText: "selectedText"
        }
        for (var property in roles) {
          if (!Qt.colorEqual(bookmarks[property], Commons.Color.menu[roles[property]])) {
            console.error("Raindrop theme mismatch: " + property)
            Qt.exit(1)
            return
          }
        }
        console.log("Raindrop theme bindings passed")
        Qt.exit(0)
      })
    }
  }
}
