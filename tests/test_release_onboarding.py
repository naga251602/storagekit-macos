import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent


class ReleaseAndOnboardingTests(unittest.TestCase):
    def test_readme_download_is_real_published_asset(self):
        readme = (ROOT / "README.md").read_text()
        self.assertIn("/releases/download/v0.1.0/StorageKit-v0.1.0-macos-arm64.zip", readme)

    def test_build_disallows_unsigned_updater_configuration(self):
        script = (ROOT / "build.sh").read_text()
        self.assertIn("STORAGEKIT_SPARKLE_PUBLIC_KEY", script)
        self.assertIn("STORAGEKIT_CODESIGN_IDENTITY", script)
        self.assertIn("SPARKLE_ON=0", script)

    def test_onboarding_has_two_choices_and_individual_folders(self):
        view = (ROOT / "app/Views/AdditionalViews.swift").read_text()
        for word in ("Accept Default Settings", "Customize", "Desktop", "Documents", "Downloads"):
            self.assertIn(word, view)

    def test_github_link_is_official(self):
        source = (ROOT / "app/Services/StorageKitLinks.swift").read_text()
        self.assertIn("https://github.com/naga251602/storagekit-macos", source)

    def test_updater_is_optional_and_defaults_to_releases(self):
        source = (ROOT / "app/Services/UpdateService.swift").read_text()
        self.assertIn("#if canImport(Sparkle)", source)
        self.assertIn("StorageKitLinks.releases", source)


if __name__ == "__main__":
    unittest.main()
