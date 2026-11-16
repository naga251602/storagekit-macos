"""Source-level regression guards for UI layout; not screenshot tests.

These run on Linux and macOS. The actual titlebar layout must still be
verified visually on macOS after the native build.
"""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
VIEW = (ROOT / "app/Views/MainViews.swift").read_text(encoding="utf-8")


class ApplicationInspectorLayoutTests(unittest.TestCase):
    def test_inspector_respects_titlebar_safe_area(self):
        # A safe-area override caused the app icon/name to render behind the
        # native macOS titlebar in v5.4.
        self.assertNotRegex(VIEW, r"\.ignoresSafeArea\s*\(")
        self.assertRegex(VIEW, r"case\s+\.applications\s*:\s*if let app = model\.selectedApp\s*\{\s*//[^\n]*\n(?:\s*//[^\n]*\n)*\s*appDetails\(app\)")

    def test_inspector_header_is_above_action_bar_and_file_list(self):
        body = VIEW.split("private func appDetails(_ app: ScanEntry)", 1)[1].split(
            "private func itemDetails", 1
        )[0]
        self.assertLess(body.index("Text(app.name)"), body.index("InspectorButtons(path: app.path)"))
        self.assertLess(body.index("InspectorButtons(path: app.path)"), body.index("ForEach(groupedCandidates"))
        top = re.search(r"\.padding\(\.horizontal,\s*20\)\.padding\(\.top,\s*(\d+)\)", body)
        self.assertIsNotNone(top)
        self.assertLessEqual(int(top.group(1)), 20)

    def test_actions_remain_single_row_and_scroll_if_needed(self):
        body = VIEW.split("private func appDetails(_ app: ScanEntry)", 1)[1]
        self.assertIn("ScrollView(.horizontal, showsIndicators: false)", body)
        self.assertIn(".fixedSize(horizontal: true, vertical: false)", body)
        for action in ("cacheButton", "resetButton", "uninstallButton"):
            self.assertIn(action, body)


if __name__ == "__main__":
    unittest.main()
