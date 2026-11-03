#!/usr/bin/env python3
"""Exercise bookmark JSON boundaries independently of jq and the network."""

import json
from pathlib import Path
import subprocess
import tempfile
import unittest


HELPER = Path(__file__).resolve().parent.parent / "bookmark-json"


class BookmarkJsonTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name)

    def run_helper(self, *args):
        return subprocess.run([str(HELPER), *map(str, args)], capture_output=True, text=True)

    def test_page_rejects_bad_items_and_overfull_pages_without_appending(self):
        response = self.path / "response.json"
        records = self.path / "records.ndjson"
        records.write_text('{"_id":1}\n')
        for items in ([{"_id": 2}, None], [{"_id": 2}, {"_id": 3}]):
            response.write_text(json.dumps({"items": items}))
            self.assertNotEqual(self.run_helper("append-page", response, records, 1).returncode, 0)
            self.assertEqual(records.read_text(), '{"_id":1}\n')
        response.write_text('{"items":[{"_id":2}]}')
        self.assertEqual(self.run_helper("append-page", response, records, 1).stdout, "1\n")
        self.assertEqual(records.read_text(), '{"_id":1}\n{"_id":2}\n')

    def test_snapshot_rejects_other_token_bad_types_and_nonfinite_time(self):
        snapshot = self.path / "bookmarks.json"
        value = {"version": 1, "tokenFingerprint": "fingerprint", "syncedAt": 12,
                 "bookmarks": [{"_id": 2}]}
        for change in ({"version": True}, {"syncedAt": True}, {"syncedAt": "12"},
                       {"syncedAt": -1}, {"syncedAt": float("nan")},
                       {"bookmarks": [None]}):
            snapshot.write_text(json.dumps(value | change))
            self.assertNotEqual(self.run_helper("load-snapshot", snapshot, "fingerprint").returncode, 0)
        snapshot.write_text(json.dumps(value))
        self.assertNotEqual(self.run_helper("load-snapshot", snapshot, "other-token").returncode, 0)
        result = self.run_helper("load-snapshot", snapshot, "fingerprint")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(json.loads(result.stdout), value)

    def test_numeric_version_forms_remain_compatible_for_load_and_covers(self):
        snapshot = self.path / "bookmarks.json"
        for version in ("1", "1.0", "1e0"):
            snapshot.write_text('{"version":' + version +
                                ',"tokenFingerprint":"fingerprint","syncedAt":12,'
                                '"bookmarks":[{"_id":2,"cover":"https://example.com/a"}]}')
            for command in ("load-snapshot", "cover-records"):
                self.assertEqual(self.run_helper(command, snapshot, "fingerprint").returncode, 0)
        snapshot.write_text(snapshot.read_text().replace('"version":1e0', '"version":true'))
        for command in ("load-snapshot", "cover-records"):
            self.assertNotEqual(self.run_helper(command, snapshot, "fingerprint").returncode, 0)

    def test_corrupt_state_cannot_extend_cooldown(self):
        state = self.path / "sync-state.json"
        for value in ({"tokenFingerprint": "other", "failureCooldownUntil": 9999999},
                      {"tokenFingerprint": "fingerprint", "failureCooldownUntil": "9999999"},
                      {"tokenFingerprint": "fingerprint", "rateLimitReset": True}):
            state.write_text(json.dumps(value))
            self.assertEqual(self.run_helper("read-state", state, "fingerprint").stdout, "0 0\n")
        self.assertEqual(self.run_helper("write-state", "fingerprint", 60, 120, state).returncode, 0)
        self.assertEqual(self.run_helper("read-state", state, "fingerprint").stdout, "60 120\n")

    def test_cover_prefers_cover_then_first_media_and_escapes_control_characters(self):
        snapshot = self.path / "bookmarks.json"
        snapshot.write_text(json.dumps({"version": 1, "tokenFingerprint": "fingerprint",
                                        "bookmarks": [{"_id": 1, "cover": "https://example.com/a"},
                                                      {"_id": 2, "cover": "", "media": [{"link": "https://example.com/b"}]},
                                                      {"_id": 3, "cover": "https://example.com/\tbad\n"},
                                                      {"_id": "12\0", "cover": "https://example.com/a"}]}))
        result = self.run_helper("cover-records", snapshot, "fingerprint")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "1\thttps://example.com/a\n2\thttps://example.com/b\n3\thttps://example.com/\\tbad\\n\n12\\0\thttps://example.com/a\n")


if __name__ == "__main__":
    unittest.main()
