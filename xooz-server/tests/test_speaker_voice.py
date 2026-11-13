import unittest
import io
import wave
import subprocess
import tempfile
from pathlib import Path
from unittest.mock import patch

from src.services import database, speaker_voice


class SpeakerVoiceTest(unittest.TestCase):
    def setUp(self):
        self.recording = {
            "id": "recording-id", "user_id": "u1", "audio_url": "stored",
            "speaker_ids": {"A": "person-id"},
            "speaker_labels": [{"speaker": "A", "start": 0, "end": 12000}],
        }

    def test_stale_assignment_does_not_enroll(self):
        with patch.object(speaker_voice, "get_transcript_by_id", return_value=self.recording), \
             patch.object(speaker_voice, "client") as client:
            self.assertFalse(speaker_voice.enroll_confirmed_speaker("recording-id", "A", "other-person"))
            client.storage.from_.assert_not_called()

    def test_missing_audio_does_not_enroll(self):
        recording = {**self.recording, "audio_url": None}
        with patch.object(speaker_voice, "get_transcript_by_id", return_value=recording), \
             patch.object(speaker_voice, "client") as client:
            self.assertFalse(speaker_voice.enroll_confirmed_speaker("recording-id", "A", "person-id"))
            client.storage.from_.assert_not_called()

    def test_diarized_clip_is_capped_at_ten_seconds(self):
        import numpy as np

        decoded = np.ones(12 * 16000, dtype=np.float32)
        with patch("resemblyzer.preprocess_wav", side_effect=lambda clip, source_sr: clip):
            voice, seconds = speaker_voice._speaker_audio(
                b"", [{"speaker": "A", "start": 0, "end": 12000}], "A", decoded=decoded,
            )
        self.assertEqual(len(voice), 10 * 16000)
        self.assertEqual(seconds, 10.0)

    def test_longest_uninterrupted_turn_wins_over_short_replies(self):
        import numpy as np

        decoded = np.concatenate((np.ones(16000, dtype=np.float32),
                                  np.zeros(16000, dtype=np.float32),
                                  np.full(6 * 16000, 0.5, dtype=np.float32)))
        turns = [{"speaker": "A", "start": 0, "end": 1000},
                 {"speaker": "B", "start": 1000, "end": 2000},
                 {"speaker": "A", "start": 2000, "end": 8000}]
        with patch("resemblyzer.preprocess_wav", side_effect=lambda clip, source_sr: clip):
            voice, seconds = speaker_voice._speaker_audio(b"", turns, "A", decoded=decoded)
        self.assertEqual(seconds, 6.0)
        self.assertAlmostEqual(float(voice.mean()), 0.5)

    def test_clean_five_second_turn_beats_longer_turn_with_only_three_seconds_of_speech(self):
        import numpy as np

        decoded = np.ones(17 * 16000, dtype=np.float32)
        turns = [{"speaker": "A", "start": 0, "end": 10000},
                 {"speaker": "A", "start": 11000, "end": 17000}]
        with patch("resemblyzer.preprocess_wav", side_effect=lambda clip, source_sr:
                   clip[:3 * 16000] if len(clip) == 10 * 16000 else clip):
            _, seconds = speaker_voice._speaker_audio(b"", turns, "A", decoded=decoded)
        self.assertEqual(seconds, 6.0)

    def test_unmatched_voice_keeps_assemblyai_label(self):
        recording = {**self.recording, "speaker_ids": {}, "speaker_names": {}}
        with patch.object(speaker_voice, "get_transcript_by_id", return_value=recording), \
             patch.object(speaker_voice, "_match_labels", return_value={}), \
             patch.object(speaker_voice, "client") as client:
            applied = speaker_voice.auto_identify_speakers("recording-id", "u1")
        self.assertEqual(applied, {})
        client.table.assert_not_called()

    def test_first_recording_without_saved_profiles_keeps_assemblyai_label(self):
        recording = {**self.recording, "speaker_ids": {}, "speaker_names": {}}
        with patch("src.services.database.get_speakers", return_value=[]), \
             patch.object(speaker_voice, "client") as client:
            matched = speaker_voice._match_labels(recording, ["A"])
        self.assertEqual(matched, {})
        client.table.assert_not_called()

    def test_old_provisional_names_are_not_reused_as_known_speakers(self):
        with patch.object(database, "client") as client:
            client.table.return_value.select.return_value.eq.return_value.order.return_value.execute.return_value.data = [
                {"id": "old-unknown", "name": "Unknown Speaker #14"},
                {"id": "named", "name": "Rahul"},
            ]
            speakers = database.get_speakers("u1")
        self.assertEqual(speakers, [{"id": "named", "name": "Rahul"}])

    def test_decodes_audio_without_relying_on_streamed_wav_header(self):
        import numpy as np

        source = io.BytesIO()
        with wave.open(source, "wb") as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(16000)
            wav.writeframes(np.full(16000, 1000, dtype="<i2").tobytes())
        decoded = speaker_voice._decode_audio(source.getvalue())
        self.assertEqual(len(decoded), 16000)
        self.assertAlmostEqual(float(decoded.mean()), 1000 / 32768, places=4)

    def test_decodes_seekable_m4a(self):
        import imageio_ffmpeg
        import numpy as np

        source = io.BytesIO()
        with wave.open(source, "wb") as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(16000)
            wav.writeframes(np.full(16000, 1000, dtype="<i2").tobytes())
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sample.m4a"
            subprocess.run(
                [imageio_ffmpeg.get_ffmpeg_exe(), "-v", "error", "-f", "wav",
                 "-i", "pipe:0", "-c:a", "aac", str(path)],
                input=source.getvalue(), capture_output=True, check=True,
            )
            decoded = speaker_voice._decode_audio(path.read_bytes())
        self.assertGreater(len(decoded), 15000)

    def test_strong_match_is_only_a_suggestion(self):
        import numpy as np

        voice = np.zeros(256, dtype=np.float32)
        voice[0] = 1
        other = np.zeros(256, dtype=np.float32)
        other[1] = 1
        speakers = [{"id": "one", "name": "Priya"}, {"id": "two", "name": "Rahul"}]
        samples = [
            {"speaker_id": "one", "embedding": voice.tolist()},
            {"speaker_id": "two", "embedding": other.tolist()},
        ]
        self.assertEqual(speaker_voice._best_match(voice, speakers, samples),
                         {"speaker_id": "one", "name": "Priya", "score": 1.0, "tier": "auto"})

    def test_gray_area_is_suggestion_and_low_score_is_unknown(self):
        import numpy as np

        voice = np.zeros(256, dtype=np.float32)
        voice[0] = 1
        speaker = [{"id": "one", "name": "Rahul"}]
        def sample(score):
            vector = np.zeros(256, dtype=np.float32)
            vector[0] = score
            vector[1] = np.sqrt(1 - score * score)
            return [{"speaker_id": "one", "embedding": vector.tolist()}]
        self.assertEqual(speaker_voice._best_match(voice, speaker, sample(0.7))["tier"], "possible")
        self.assertEqual(speaker_voice._best_match(voice, speaker, sample(0.85))["tier"], "auto")
        self.assertIsNone(speaker_voice._best_match(voice, speaker, sample(0.6)))

    def test_saved_samples_are_compared_as_a_normalized_centroid(self):
        import numpy as np

        voice = np.zeros(256, dtype=np.float32)
        voice[0] = 1
        left = voice.copy()
        right = voice.copy()
        left[1], right[1] = 0.8, -0.8
        samples = [{"speaker_id": "one", "embedding": vector.tolist()}
                   for vector in (left, right)]
        match = speaker_voice._best_match(voice, [{"id": "one", "name": "Rahul"}], samples)
        self.assertAlmostEqual(match["score"], 1.0)

    def test_ambiguous_match_is_not_suggested(self):
        import numpy as np

        voice = np.zeros(256, dtype=np.float32)
        voice[0] = 1
        other = voice.copy()
        other[1] = 0.02
        speakers = [{"id": "one", "name": "Priya"}, {"id": "two", "name": "Rahul"}]
        samples = [
            {"speaker_id": "one", "embedding": voice.tolist()},
            {"speaker_id": "two", "embedding": other.tolist()},
        ]
        self.assertIsNone(speaker_voice._best_match(voice, speakers, samples))

    def test_suggestion_does_not_search_another_users_profiles(self):
        with patch.object(speaker_voice, "get_transcript_by_id", return_value=self.recording), \
             patch.object(speaker_voice, "client") as client:
            self.assertIsNone(speaker_voice.suggest_speaker("recording-id", "A", "other-user"))
            client.table.assert_not_called()

    def test_auto_identification_saves_confident_match(self):
        recording = {**self.recording, "speaker_ids": {}, "speaker_names": {}}
        with patch.object(speaker_voice, "get_transcript_by_id", return_value=recording), \
             patch.object(speaker_voice, "_match_labels", return_value={
                 "A": {"speaker_id": "person-id", "name": "Priya"}
             }), patch.object(speaker_voice, "client") as client:
            client.table.return_value.update.return_value.eq.return_value.eq.return_value.eq.return_value.execute.return_value.data = [{}]
            applied = speaker_voice.auto_identify_speakers("recording-id", "u1")
            self.assertEqual(applied, {"A": "Priya"})
            client.table.return_value.update.assert_called_once_with({
                "speaker_names": {"A": "Priya"},
                "speaker_ids": {"A": "person-id"},
                "summary": None,
            })

    def test_confident_match_adds_sample_for_future_centroid(self):
        recording = {**self.recording, "speaker_ids": {}, "speaker_names": {}}
        vector = [0.0] * 256
        vector[0] = 1.0
        with patch.object(speaker_voice, "get_transcript_by_id", return_value=recording), \
             patch.object(speaker_voice, "_match_labels", return_value={
                 "A": {"speaker_id": "person-id", "name": "Rahul", "tier": "auto",
                       "score": 0.9, "embedding": vector, "speech_seconds": 6.0},
             }), patch.object(speaker_voice, "client") as client:
            client.table.return_value.update.return_value.eq.return_value.eq.return_value.eq.return_value.execute.return_value.data = [{}]
            self.assertEqual(speaker_voice.auto_identify_speakers("recording-id", "u1"), {"A": "Rahul"})
            client.table.return_value.upsert.assert_called_once_with({
                "speaker_id": "person-id", "transcript_id": "recording-id",
                "speaker_label": "A", "embedding": vector, "speech_seconds": 6.0,
            }, on_conflict="transcript_id,speaker_label")

    def test_gray_area_does_not_auto_assign_a_name(self):
        recording = {**self.recording, "speaker_ids": {}, "speaker_names": {}}
        with patch.object(speaker_voice, "get_transcript_by_id", return_value=recording), \
             patch.object(speaker_voice, "_match_labels", return_value={
                 "A": {"speaker_id": "person-id", "name": "Rahul", "tier": "possible", "score": 0.7},
             }), patch.object(speaker_voice, "client") as client:
            self.assertEqual(speaker_voice.auto_identify_speakers("recording-id", "u1"), {})
            client.table.assert_not_called()

    def test_auto_identification_does_not_overwrite_manual_name(self):
        recording = {**self.recording, "speaker_ids": {}, "speaker_names": {}}
        renamed = {**recording, "speaker_names": {"A": "Rahul"}}
        with patch.object(speaker_voice, "get_transcript_by_id", side_effect=[recording, renamed]), \
             patch.object(speaker_voice, "_match_labels", return_value={
                 "A": {"speaker_id": "person-id", "name": "Priya"}
             }), patch.object(speaker_voice, "client") as client:
            self.assertEqual(speaker_voice.auto_identify_speakers("recording-id", "u1"), {})
            client.table.assert_not_called()

    def test_auto_identification_rejects_duplicate_identity_for_two_voices(self):
        recording = {**self.recording, "speaker_ids": {}, "speaker_names": {},
                     "speaker_labels": [{"speaker": "A"}, {"speaker": "B"}]}
        with patch.object(speaker_voice, "get_transcript_by_id", return_value=recording), \
             patch.object(speaker_voice, "_match_labels", return_value={
                 "A": {"speaker_id": "person-id", "name": "Priya"},
                 "B": {"speaker_id": "person-id", "name": "Priya"},
             }), patch.object(speaker_voice, "client") as client:
            self.assertEqual(speaker_voice.auto_identify_speakers("recording-id", "u1"), {})
            client.table.assert_not_called()


if __name__ == "__main__":
    unittest.main()
