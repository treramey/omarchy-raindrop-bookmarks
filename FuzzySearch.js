function isBoundary(text, index) {
  if (index === 0) return true
  var previous = text[index - 1]
  var current = text[index]
  return /[\s\/_.:#?&=-]/.test(previous) || (/[a-z]/.test(previous) && /[A-Z]/.test(current))
}

function scoreToken(rawQuery, rawText) {
  if (!rawText) return -1
  var caseSensitive = rawQuery !== rawQuery.toLowerCase()
  var query = caseSensitive ? rawQuery : rawQuery.toLowerCase()
  var text = caseSensitive ? String(rawText) : String(rawText).toLowerCase()
  if (query.length > text.length) return -1

  // Most fields cannot contain a long query as a subsequence. Reject them
  // before allocating and scoring a matrix for every query character.
  var position = 0
  for (var q = 0; q < query.length; q++) {
    position = text.indexOf(query[q], position)
    if (position < 0) return -1
    position++
  }

  var boundaries = new Array(text.length)
  for (var b = 0; b < text.length; b++) boundaries[b] = isBoundary(rawText, b)

  var previous = new Array(text.length)
  for (var j = 0; j < text.length; j++) {
    previous[j] = text[j] === query[0]
      ? 16 + (boundaries[j] ? 18 : 0) - Math.min(j, 24)
      : -Infinity
  }

  for (var i = 1; i < query.length; i++) {
    var current = new Array(text.length)
    var bestGap = -Infinity
    for (var k = 0; k < text.length; k++) {
      if (k > 0 && previous[k - 1] !== -Infinity)
        bestGap = Math.max(bestGap - 1, previous[k - 1] - 2)

      if (text[k] !== query[i]) current[k] = -Infinity
      else {
        var consecutive = k > 0 && previous[k - 1] !== -Infinity ? previous[k - 1] + 28 : -Infinity
        var gapped = bestGap === -Infinity ? -Infinity : bestGap + 12
        current[k] = Math.max(consecutive, gapped) + (boundaries[k] ? 10 : 0)
      }
    }
    previous = current
  }

  var best = Math.max.apply(Math, previous)
  if (best === -Infinity) return -1
  var comparable = caseSensitive ? String(rawText) : String(rawText).toLowerCase()
  if (comparable === query) best += 240
  else if (comparable.indexOf(query) === 0) best += 120
  else if (comparable.indexOf(query) >= 0) best += 55
  return best
}

function scoreBookmark(query, bookmark) {
  var tokens = query.trim().split(/\s+/).filter(function(token) { return token.length > 0 })
  if (!tokens.length) return 1
  var fields = [
    { text: bookmark.title || "", weight: 5 },
    { text: bookmark.domain || "", weight: 3 },
    { text: (bookmark.tags || []).join(" "), weight: 2 },
    { text: bookmark.link || "", weight: 1 }
  ]
  var total = 0
  for (var i = 0; i < tokens.length; i++) {
    var best = -1
    for (var j = 0; j < fields.length; j++) {
      var score = scoreToken(tokens[i], fields[j].text)
      if (score >= 0) best = Math.max(best, score * fields[j].weight)
    }
    if (best < 0) return -1
    total += best
  }
  if (bookmark.important) total += 40
  return total
}

function search(query, bookmarks) {
  if (!query.trim()) return bookmarks.slice()
  return bookmarks.map(function(bookmark, index) {
    return { bookmark: bookmark, index: index, score: scoreBookmark(query, bookmark) }
  }).filter(function(item) { return item.score >= 0 })
    .sort(function(a, b) { return b.score - a.score || a.index - b.index })
    .map(function(item) { return item.bookmark })
}
