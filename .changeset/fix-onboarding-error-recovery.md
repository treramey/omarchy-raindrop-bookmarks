---
"io.github.treramey.raindrop-bookmarks": patch
---

Keep token validation and saving tied to one immutable attempt so background checks cannot authorize replacement credentials. Recover from helper-start failures and timeouts, distinguish connection and input errors, and respect rate-limit retry countdowns.
