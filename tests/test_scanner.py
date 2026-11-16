"""Safe fixture-only tests. Never touch real macOS apps or call the Trash API."""
import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class DiscoveryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder = pathlib.Path(tempfile.mkdtemp(prefix="mac-cleaner-fixture-"))
        cls.binary = cls.folder / "scanner"
        flags = ["clang++", "-std=c++20", "-O0", "-Wall", "-Wextra", str(ROOT / "engine/Scanner.cpp"), "-o", str(cls.binary)]
        if os.uname().sysname == "Darwin":
            flags.extend(["-framework", "CoreFoundation"])
        subprocess.run(flags, check=True)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.folder)

    def setUp(self):
        self.temp = pathlib.Path(tempfile.mkdtemp(prefix="cleaner-homedir-"))
        self.home = self.temp / "test-home"
        self.apps = self.home / "Applications"
        self.apps.mkdir(parents=True)
        self.foo = self.create_app("Example", "com.example.app")
        self.create_file("Library/Caches/com.example.app/x.tmp", b"cache")
        self.create_file("Library/Application Support/com.example.app/state.bin", b"data")
        self.create_file("Library/Application Support/Example/settings", b"user private")
        self.create_file("Library/Preferences/com.example.app.plist", b"prefs")
        self.create_file("Library/Group Containers/com.example.app/foo.txt", b"shared")
        self.create_file("Library/Caches/com.example.app.other/x", b"someone else's cache")
        self.create_file("Library/Caches/com.example-other/x", b"unrelated")
        self.create_file("Library/Logs/com.example.app.log", b"unknown prefix")
        self.create_file(".ollama/models/blobs/sha256-something", b"model")
        outside = self.create_file("unrelated/important.txt", b"important")
        (self.home / "Library/Caches/com.example.app.alias").symlink_to(outside)

    def tearDown(self):
        shutil.rmtree(self.temp)

    def create_file(self, name, data):
        p = self.home / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(data)
        return p

    def create_app(self, name, bundle):
        app = self.apps / (name + ".app")
        (app / "Contents").mkdir(parents=True)
        (app / "Contents/Info.plist").write_text('''<?xml version="1.0"?><plist><dict><key>CFBundleIdentifier</key><string>%s</string></dict></plist>''' % bundle)
        (app / "Contents/MacOS").mkdir()
        (app / "Contents/MacOS/app").write_bytes(b"binary")
        return app

    def run_scanner(self, *args):
        proc = subprocess.run([str(self.binary), *args, "--home", str(self.home),
            "--apps-root", str(self.apps), "--jsonl"], capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        return [json.loads(line) for line in proc.stdout.splitlines() if line.strip()]

    def test_list_and_exact_bundle_match(self):
        entries = self.run_scanner("list")
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["bundle_id"], "com.example.app")
        self.assertEqual(entries[0]["id"], str(self.foo))
        self.assertTrue(entries[0]["eligible"])
        found = self.run_scanner("scan", "--path", str(self.foo), "--sizes")
        bypath = {e["path"]: e for e in found}
        self.assertEqual(bypath[str(self.foo)]["cleanup"], "app")
        support = self.home / "Library/Application Support/com.example.app"
        self.assertEqual(bypath[str(support)]["status"], "GREEN")
        self.assertTrue(bypath[str(support)]["eligible"])
        self.assertEqual(bypath[str(support)]["size_bytes"], len(b"data"))
        self.assertTrue(bypath[str(self.home / "Library/Preferences/com.example.app.plist")]["eligible"])

    def test_name_only_and_shared_never_auto_eligible(self):
        found = self.run_scanner("scan", "--path", str(self.foo), "--sizes")
        named = next(e for e in found if e["path"] == str(self.home / "Library/Application Support/Example"))
        shared = next(e for e in found if e["category"] == "Group Containers")
        self.assertEqual(named["status"], "GREY")
        self.assertEqual(shared["status"], "AMBER")
        self.assertFalse(named["eligible"])
        self.assertFalse(shared["eligible"])

    def test_partial_names_unverified(self):
        found = self.run_scanner("scan", "--path", str(self.foo))
        prefix = [e for e in found if pathlib.Path(e["path"]).name in
                  {"com.example.app.other", "com.example.app.alias", "com.example.app.log"}]
        self.assertEqual(len(prefix), 3)
        self.assertTrue(all(not e["eligible"] for e in prefix))
        self.assertTrue(all(e["status"] == "GREY" for e in prefix))
        self.assertFalse(any(e["path"].endswith("com.example-other") for e in found))

    def test_name_duplicates_resolved_by_exact_path(self):
        duplicate = self.create_app("Second", "com.example.app")
        listed = self.run_scanner("list")
        self.assertEqual(len(listed), 2)
        selected = self.run_scanner("scan", "--path", str(duplicate))
        self.assertEqual(selected[0]["path"], str(duplicate))

    def test_apple_authored_user_app_requires_advanced_review(self):
        app = self.create_app("AppleDemo", "com.apple.demo")
        selected = self.run_scanner("scan", "--path", str(app))
        self.assertTrue(all(not e["eligible"] for e in selected))
        self.assertTrue(all(e["status"] in {"AMBER", "GREY"} for e in selected))

    def test_apple_apps_are_listed_for_explicit_opt_in(self):
        self.create_app("AppleDemo", "com.apple.demo")
        self.create_app("CaseInsensitiveApple", "COM.APPLE.Test")
        self.assertEqual([entry["bundle_id"] for entry in self.run_scanner("list")], ["com.example.app"])
        listed = self.run_scanner("list", "--include-apple")
        ids = [entry["bundle_id"] for entry in listed]
        self.assertEqual(ids, ["com.apple.demo", "COM.APPLE.Test", "com.example.app"])
        for entry in listed[:2]:
            self.assertFalse(entry["eligible"])
            self.assertEqual(entry["cleanup"], "app")
            self.assertEqual(entry["status"], "AMBER")

    def test_apple_exact_user_library_data_review_only(self):
        app = self.create_app("SafariFixture", "com.apple.fixture")
        exact_cache = self.create_file("Library/Caches/com.apple.fixture/cached.txt", b"cache")
        exact_pref = self.create_file("Library/Preferences/com.apple.fixture.plist", b"pref")
        shared = self.create_file("Library/Group Containers/com.apple.fixture/shared.txt", b"shared")
        partial = self.create_file("Library/Caches/com.apple.fixture.extra/keep.txt", b"keep")
        name_only = self.create_file("Library/Application Support/SafariFixture/keep.txt", b"keep")
        found = self.run_scanner("scan", "--path", str(app), "--sizes")
        bypath = {row["path"]: row for row in found}
        for path in (exact_cache.parent, exact_pref):
            row = bypath[str(path)]
            self.assertEqual(row["status"], "AMBER")
            self.assertEqual(row["confidence"], "review")
            self.assertFalse(row["eligible"])
            self.assertIn("Apple app user Library data", row["reason"])
        self.assertNotIn("Apple app user Library data", bypath[str(shared.parent)]["reason"])
        self.assertNotIn("Apple app user Library data", bypath[str(partial.parent)]["reason"])
        self.assertNotIn("Apple app user Library data", bypath[str(name_only.parent)]["reason"])
        self.assertEqual(exact_cache.read_bytes(), b"cache")
        self.assertEqual(exact_pref.read_bytes(), b"pref")

    def test_apple_prefixed_logs_excluded_from_storage(self):
        import time
        old = self.create_file("Library/Logs/com.apple.unrelated.log", b"system log")
        age = time.time() - 40 * 86400
        os.utime(old, (age, age))
        found = self.run_scanner("storage")
        self.assertFalse(any(e["path"] == str(old) for e in found))
        self.assertEqual(old.read_bytes(), b"system log")

    def test_scanner_no_mutation(self):
        cache = self.home / "Library/Caches/com.example.app/x.tmp"
        self.run_scanner("scan", "--path", str(self.foo), "--sizes")
        self.assertEqual(cache.read_bytes(), b"cache")
        self.assertTrue(self.foo.exists())

    def test_storagekit_history_not_deletable(self):
        storagekit = self.create_app("StorageKit", "dev.storagekit.macos")
        own_history = self.create_file("Library/Application Support/StorageKit/history-v1.json", b"[]")
        found = self.run_scanner("scan", "--path", str(storagekit), "--sizes")
        row = next(entry for entry in found if entry["path"] == str(own_history.parent))
        self.assertEqual(row["status"], "RED")
        self.assertFalse(row["eligible"])

    def test_storage_verified_cache_and_managed_inventory(self):
        found = self.run_scanner("storage", "--sizes")
        bypath = {row["path"]: row for row in found}
        expected = str(self.home / "Library/Caches/com.example.app")
        self.assertIn(expected, bypath)
        self.assertEqual(bypath[expected]["category"], "App Cache")
        self.assertTrue(bypath[expected]["eligible"])
        self.assertEqual(bypath[expected]["status"], "GREEN")
        managed = str(self.home / ".ollama/models")
        self.assertIn(managed, bypath)
        self.assertEqual(bypath[managed]["cleanup"], "none")
        self.assertFalse(bypath[managed]["eligible"])

    def test_storage_old_downloads_never_auto_selected(self):
        old = self.create_file("Downloads/old-report.txt", b"please keep")
        import time
        timestamp = time.time() - 120 * 86400
        os.utime(old, (timestamp, timestamp))
        found = self.run_scanner("storage")
        row = next(item for item in found if item["path"] == str(old))
        self.assertEqual(row["status"], "GREY")
        self.assertFalse(row["eligible"])
        self.assertEqual(old.read_bytes(), b"please keep")

    def test_storage_excludes_symlink_to_other_location(self):
        outsider = self.create_file("unrelated/cache-hidden.txt", b"do not touch")
        (self.home / "Downloads").mkdir(parents=True, exist_ok=True)
        (self.home / "Downloads/suspicious.txt").symlink_to(outsider)
        import time
        os.utime(outsider, (time.time() - 120 * 86400,) * 2)
        rows = self.run_scanner("storage", "--sizes")
        self.assertFalse(any(row["path"].endswith("Downloads/suspicious.txt") for row in rows))

    def test_ollama_vendor_documented_paths_include_models_and_logs(self):
        app = self.create_app("Ollama", "com.electron.ollama")
        model = self.create_file(".ollama/models/blobs/sha256-abc", b"large model")
        log = self.create_file(".ollama/logs/server.log", b"log entries")
        support = self.create_file("Library/Application Support/Ollama/db.sqlite", b"chat history")
        cache = self.create_file("Library/Caches/ollama/temp.db", b"cache")
        webkit = self.create_file("Library/WebKit/com.electron.ollama/session", b"web")
        rows = self.run_scanner("scan", "--path", str(app), "--sizes")
        bypath = {row["path"]: row for row in rows}
        store = str(self.home / ".ollama")
        self.assertIn(store, bypath)
        self.assertTrue(bypath[store]["eligible"])
        self.assertEqual(bypath[store]["category"], "Ollama Models & Configuration")
        self.assertEqual(bypath[store]["cleanup"], "data")
        self.assertEqual(bypath[store]["size_bytes"], len(b"large model") + len(b"log entries") + len(b"model"))
        for path in [support.parent, cache.parent, webkit.parent]:
            self.assertIn(str(path), bypath)
            self.assertEqual(bypath[str(path)]["status"], "GREEN")
        # Scanning is read-only, even for large model stores.
        self.assertEqual(model.read_bytes(), b"large model")
        self.assertEqual(log.read_bytes(), b"log entries")

    def test_ollama_remnant_discoverable_after_app_is_gone(self):
        old_model = self.create_file(".ollama/models/blobs/blob", b"model")
        rows = self.run_scanner("storage", "--sizes")
        remnant = next(row for row in rows if row["path"] == str(self.home / ".ollama"))
        self.assertEqual(remnant["status"], "GREY")
        self.assertEqual(remnant["category"], "Orphaned Ollama Data")
        self.assertFalse(remnant["eligible"])
        self.assertEqual(old_model.read_bytes(), b"model")

    def test_other_apps_do_not_claim_ollama_models(self):
        self.create_file(".ollama/models/blobs/random", b"model")
        rows = self.run_scanner("scan", "--path", str(self.foo))
        self.assertFalse(any(row["path"] == str(self.home / ".ollama") for row in rows))

    def test_inventory_requires_explicit_review(self):
        entries = self.run_scanner("inventory")
        self.assertTrue(any("models" in e["path"] for e in entries))
        self.assertTrue(all(not e["eligible"] for e in entries))
        model_store = next(e for e in entries if e["path"] == str(self.home / ".ollama/models"))
        self.assertEqual(model_store["cleanup"], "developer")
        self.assertEqual(model_store["status"], "AMBER")
        self.assertEqual(model_store["confidence"], "manual")
        manifests = [e for e in entries if e["category"] == "Ollama model manifest"]
        self.assertTrue(all(e["cleanup"] == "none" for e in manifests))

    def test_developer_runtime_version_is_manual_and_not_auto_selected(self):
        path = self.create_file(".pyenv/versions/3.12.1/bin/python", b"fake runtime")
        entries = self.run_scanner("inventory", "--sizes")
        version = path.parents[1]
        match = next(e for e in entries if e["path"] == str(version))
        self.assertEqual(match["category"], "Runtime/environment")
        self.assertEqual(match["cleanup"], "developer")
        self.assertFalse(match["eligible"])
        self.assertEqual(path.read_bytes(), b"fake runtime")

    def test_individual_hugging_face_model_cache_is_reviewable(self):
        one = self.create_file(".cache/huggingface/hub/models--org--safe-model/snapshots/v1/config.json", b"test")
        self.create_file(".cache/huggingface/hub/datasets--org--set/metadata.json", b"dataset")
        rows = self.run_scanner("inventory", "--sizes")
        model_dir = self.home / ".cache/huggingface/hub/models--org--safe-model"
        model = next(e for e in rows if e["path"] == str(model_dir))
        self.assertEqual(model["category"], "Hugging Face cached model")
        self.assertEqual(model["cleanup"], "developer")
        self.assertEqual(model["status"], "AMBER")
        self.assertFalse(any(e["category"] == "Hugging Face cached model"
                             and "datasets--" in e["path"] for e in rows))
        self.assertEqual(one.read_bytes(), b"test")

    def test_developer_inventory_does_not_follow_symlinks(self):
        target = self.create_file("unrelated/private.txt", b"private")
        root = self.home / ".pyenv/versions"
        root.mkdir(parents=True)
        (root / "linked-runtime").symlink_to(target.parent, target_is_directory=True)
        entries = self.run_scanner("inventory")
        self.assertFalse(any("linked-runtime" in entry["path"] for entry in entries))

if __name__ == "__main__": unittest.main()
