import importlib.util
from pathlib import Path
import tempfile
import unittest


MODULE = Path(__file__).resolve().parent.parent / "Tools/check_repository.py"
spec = importlib.util.spec_from_file_location("repository_checks", MODULE)
checks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checks)


class RepositoryChecksTests(unittest.TestCase):
    def test_links_resolve_relative_to_the_document_and_decode_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "docs").mkdir()
            (root / "README.md").write_text("hello\n")
            (root / "docs/with space.md").write_text("hello\n")
            content = "[root](../README.md#start) [local](with%20space.md) [web](https://example.com)"
            self.assertEqual(checks.broken_links(root, "docs/guide.md", content), [])
            self.assertEqual(checks.broken_links(root, "docs/guide.md", "[missing](gone.md)"), ["gone.md"])

    def test_links_cannot_escape_the_repository(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(checks.broken_links(Path(directory), "README.md", "[outside](../outside.md)"), ["../outside.md"])

    def test_only_specific_dummy_credentials_in_specific_test_files_are_allowed(self):
        dummy = "sk-ant-" + "sid01-testonlyabcdefghijklmnop"
        self.assertEqual(checks.credential_kinds("Tests/UsageTests.swift", dummy), [])
        self.assertIn("Claude session", checks.credential_kinds("README.md", dummy))
        real_looking = "sk-ant-" + "sid01-" + "R" * 50
        self.assertIn("Claude session", checks.credential_kinds("Tests/UsageTests.swift", real_looking))

    def test_private_keys_are_detected_without_returning_the_contents(self):
        private = "-----BEGIN " + "PRIVATE KEY-----\nconfidential\n"
        self.assertEqual(checks.credential_kinds("local.pem", private), ["private key"])

    def test_independent_provider_tokens_are_detected(self):
        github = "gh" + "p_" + "x" * 36
        anthropic = "sk-ant-" + "api03-" + "x" * 48
        self.assertEqual(checks.credential_kinds("config", github), ["GitHub token"])
        self.assertEqual(checks.credential_kinds("config", anthropic), ["Anthropic API key"])


if __name__ == "__main__":
    unittest.main()
