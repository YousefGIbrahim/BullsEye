import os
import unittest
from unittest.mock import patch
from server import local_match, match, validate


class MatchingChecks(unittest.TestCase):
    def test_suit_and_food_are_distinct(self):
        self.assertEqual(local_match("Where can I rent a suit?")["service_id"], "suit-a-bull")
        self.assertEqual(local_match("groceries")["service_id"], "feed-a-bull")

    def test_unknown_and_ambiguity(self):
        self.assertEqual(local_match("parking permit")["status"], "no_match")
        self.assertEqual(local_match("suit and groceries")["status"], "clarify")

    def test_reject_invalid_ids_and_inconsistent_state(self):
        for value in ({"status": "match", "service_id": "invented"},
                      {"status": "match", "service_id": None},
                      {"status": "no_match", "service_id": "suit-a-bull"},
                      {"status": "match", "service_id": "suit-a-bull", "directions": "invented"}):
            with self.assertRaises(ValueError):
                validate(value)

    @patch.dict(os.environ, {}, clear=True)
    def test_no_key_uses_local_directory(self):
        self.assertFalse(match("rent a suit")["live"])

    @patch.dict(os.environ, {"GEMINI_API_KEY": "unit-check-not-a-real-key"})
    @patch("urllib.request.urlopen", side_effect=TimeoutError)
    def test_timeout_falls_back(self, _):
        self.assertEqual(match("rent a suit")["service_id"], "suit-a-bull")


if __name__ == "__main__":
    unittest.main()
