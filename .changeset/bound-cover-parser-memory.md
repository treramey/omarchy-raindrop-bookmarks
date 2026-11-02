---
"io.github.treramey.raindrop-bookmarks": patch
---

Limit cover image parsers to 256 MiB of virtual address space before reading untrusted image metadata, while preserving stricter inherited limits. Skip parsing if the limit cannot be applied.
