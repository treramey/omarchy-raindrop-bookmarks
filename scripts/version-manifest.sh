#!/usr/bin/env bash
set -euo pipefail

pnpm changeset version

node <<'NODE'
const fs = require("node:fs")
const packageJson = JSON.parse(fs.readFileSync("package.json", "utf8"))
const manifest = JSON.parse(fs.readFileSync("manifest.json", "utf8"))
manifest.version = packageJson.version
fs.writeFileSync("manifest.json", `${JSON.stringify(manifest, null, 2)}\n`)
NODE

git add package.json manifest.json CHANGELOG.md .changeset
