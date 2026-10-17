import os
import unittest
from unittest.mock import Mock, patch

import scores

KICKOFF_MS = 1_792_000_800_000  # 2026-10-14T19:20:00Z
KICKOFF_ISO = "2026-10-14T19:20:00Z"


def ours(home, away, date=KICKOFF_MS, title=None):
    teams = {"home": {"name": home}, "away": {"name": away}} if home else None
    return {"id": "m", "title": title or f"{home} vs {away}", "date": date, "teams": teams}


def theirs(home, away, short_home=None, short_away=None, tla_home=None, tla_away=None,
           utc=KICKOFF_ISO, status="TIMED", full_time=None, minute=None):
    return {
        "utcDate": utc,
        "status": status,
        "minute": minute,
        "homeTeam": {"name": home, "shortName": short_home, "tla": tla_home},
        "awayTeam": {"name": away, "shortName": short_away, "tla": tla_away},
        "score": {"fullTime": full_time or {"home": None, "away": None}},
        "competition": {"name": "Premier League"},
        "lastUpdated": "2026-10-14T20:01:00Z",
    }


class MatchingTests(unittest.TestCase):
    def test_everyday_names_match_official_ones(self):
        cases = [
            (("Bayern Munich", "Borussia Dortmund"), ("FC Bayern München", "Borussia Dortmund", "Bayern", "Dortmund")),
            (("Wolves", "Spurs"), ("Wolverhampton Wanderers FC", "Tottenham Hotspur FC", "Wolverhampton", "Tottenham")),
            (("Inter", "AC Milan"), ("FC Internazionale Milano", "AC Milan", "Inter", "Milan")),
            (("PSG", "Marseille"), ("Paris Saint-Germain FC", "Olympique de Marseille", "PSG", "Marseille")),
        ]
        for (home, away), (fd_home, fd_away, short_home, short_away) in cases:
            with self.subTest(home=home):
                fixture = theirs(fd_home, fd_away, short_home, short_away)
                self.assertIs(scores.find_fixture(ours(home, away), [fixture]), fixture)

    def test_a_derby_pairs_home_with_home(self):
        straight = theirs("Manchester United FC", "Manchester City FC", "Man United", "Man City")
        reversed_ = theirs("Manchester City FC", "Manchester United FC", "Man City", "Man United")
        found = scores.find_fixture(ours("Manchester United", "Manchester City"), [reversed_, straight])
        self.assertIs(found, straight)

    def test_other_matches_at_the_same_time_are_not_taken(self):
        fixture = theirs("Arsenal FC", "Chelsea FC", "Arsenal", "Chelsea")
        self.assertIsNone(scores.find_fixture(ours("Liverpool", "Everton"), [fixture]))

    def test_the_same_teams_on_another_day_are_not_taken(self):
        fixture = theirs("Arsenal FC", "Chelsea FC", utc="2026-10-17T19:20:00Z")
        self.assertIsNone(scores.find_fixture(ours("Arsenal", "Chelsea"), [fixture]))

    def test_teams_come_from_the_title_when_the_feed_has_none(self):
        fixture = theirs("Real Madrid CF", "FC Barcelona", "Real Madrid", "Barça")
        match = ours(None, None, title="Real Madrid vs Barcelona")
        self.assertIs(scores.find_fixture(match, [fixture]), fixture)


class ScoreTests(unittest.TestCase):
    def test_live_score_minute_and_competition(self):
        fixture = theirs("A", "B", status="IN_PLAY", full_time={"home": 2, "away": 1}, minute=67)
        score = scores.score_for(fixture)
        self.assertEqual((score["home"], score["away"], score["status"], score["minute"]), (2, 1, "live", 67))
        self.assertEqual(score["competition"], "Premier League")

    def test_kicked_off_without_goals_reads_nil_nil(self):
        score = scores.score_for(theirs("A", "B", status="PAUSED"))
        self.assertEqual((score["home"], score["away"], score["status"]), (0, 0, "halftime"))
        self.assertIsNone(score["minute"])

    def test_upcoming_match_has_no_score(self):
        score = scores.score_for(theirs("A", "B"))
        self.assertEqual((score["home"], score["away"], score["status"]), (None, None, "scheduled"))

    def test_free_plan_scores_are_marked_delayed(self):
        with patch.dict(os.environ, {"FOOTBALL_DATA_REALTIME": ""}):
            self.assertTrue(scores.score_for(theirs("A", "B"))["delayed"])
        with patch.dict(os.environ, {"FOOTBALL_DATA_REALTIME": "true"}):
            self.assertFalse(scores.score_for(theirs("A", "B"))["delayed"])


class AttachTests(unittest.TestCase):
    def setUp(self):
        scores.clear_cache()

    def test_without_a_token_matches_carry_no_score(self):
        with patch.dict(os.environ, {"FOOTBALL_DATA_TOKEN": ""}), patch.object(scores._session, "get") as get:
            result = scores.attach([ours("Arsenal", "Chelsea")])
        get.assert_not_called()
        self.assertIsNone(result[0]["score"])

    def test_scores_are_fetched_once_and_cached(self):
        payload = {"matches": [theirs("Arsenal FC", "Chelsea FC", status="IN_PLAY",
                                      full_time={"home": 1, "away": 0}, minute=12)]}
        response = Mock()
        response.json.return_value = payload
        with patch.dict(os.environ, {"FOOTBALL_DATA_TOKEN": "test-token"}), \
                patch.object(scores._session, "get", return_value=response) as get:
            first = scores.attach([ours("Arsenal", "Chelsea")])
            scores.attach([ours("Arsenal", "Chelsea")])
        self.assertEqual(get.call_count, 1)
        self.assertEqual(get.call_args.kwargs["headers"]["X-Auth-Token"], "test-token")
        self.assertEqual((first[0]["score"]["home"], first[0]["score"]["away"]), (1, 0))

    def test_a_provider_failure_leaves_matches_without_scores(self):
        with patch.dict(os.environ, {"FOOTBALL_DATA_TOKEN": "test-token"}), \
                patch.object(scores._session, "get", side_effect=scores.requests.ConnectionError("down")):
            result = scores.attach([ours("Arsenal", "Chelsea")])
        self.assertIsNone(result[0]["score"])


if __name__ == "__main__":
    unittest.main()
