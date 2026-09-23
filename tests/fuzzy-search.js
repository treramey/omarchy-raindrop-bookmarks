const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const vm = require('node:vm')

const searchModule = {}
vm.createContext(searchModule)
vm.runInContext(fs.readFileSync(path.join(__dirname, '..', 'FuzzySearch.js'), 'utf8'), searchModule)

const bookmarks = [
  { title: 'Everything I own', domain: 'example.com', tags: [], link: 'https://example.com/' + 'x'.repeat(180) },
  { title: 'Other bookmark', domain: 'another.org', tags: ['reference'], link: 'https://another.org/' },
]

assert.deepEqual(Array.from(searchModule.search('everythingiown', bookmarks)), [bookmarks[0]])
assert.deepEqual(Array.from(searchModule.search('zzzzzzzzzzzzzzzzzzzz', bookmarks)), [])
assert.deepEqual(Array.from(searchModule.search('x'.repeat(25), bookmarks)), [bookmarks[0]])
assert.deepEqual(Array.from(searchModule.search('other', bookmarks)), [bookmarks[1]])
console.log('fuzzy search checks passed')
