"""Enroll a confirmed speaker from their diarized, stored recording."""

import subprocess
import tempfile
import os
import math
import json

from src.services.database import client, get_transcript_by_id

STORAGE_BUCKET = "recordings"
MIN_SPEECH_SECONDS = 3.0
PREFERRED_SPEECH_SECONDS = 5.0
MAX_SPEECH_SECONDS = 10.0
AUTO_MIN_SIMILARITY = 0.80
POSSIBLE_MIN_SIMILARITY = 0.65
SUGGESTION_MIN_MARGIN = 0.08


def remove_voice_sample(transcript_id: str, label: str, previous_speaker_id: str) -> None:
    current = get_transcript_by_id(transcript_id)
    if current and (current.get("speaker_ids") or {}).get(label) == previous_speaker_id:
        return
    (client.table("speaker_voice_samples").delete()
     .eq("transcript_id", transcript_id).eq("speaker_label", label)
     .eq("speaker_id", previous_speaker_id).execute())


def _decode_audio(audio: bytes):
    import imageio_ffmpeg
    import numpy as np

    if len(audio) > 30 * 1024 * 1024:
        raise ValueError("Recording is too large for speaker enrollment")
    # MP4/M4A metadata may be at the end; FFmpeg needs a seekable input.
    with tempfile.NamedTemporaryFile(suffix=".m4a", delete=False) as source:
        source.write(audio)
        source_path = source.name
    try:
        decoded = subprocess.run(
            [imageio_ffmpeg.get_ffmpeg_exe(), "-v", "error", "-i", source_path,
             "-t", "600", "-vn", "-ac", "1", "-ar", "16000", "-f", "s16le", "pipe:1"],
            capture_output=True, check=True, timeout=90,
        ).stdout
    finally:
        os.remove(source_path)
    if not decoded:
        raise ValueError("Recording decoded to empty audio")
    return np.frombuffer(decoded, dtype="<i2").astype(np.float32) / 32768.0


def _speaker_audio(audio: bytes, utterances: list[dict], label: str, decoded=None):
    import numpy as np
    from resemblyzer import preprocess_wav

    samples = decoded if decoded is not None else _decode_audio(audio)

    turns = []
    other_turns = [(turn.get("start"), turn.get("end")) for turn in utterances
                   if str(turn.get("speaker")) != label
                   and isinstance(turn.get("start"), (int, float))
                   and isinstance(turn.get("end"), (int, float))]
    for turn in utterances:
        if str(turn.get("speaker")) != label:
            continue
        start, end = turn.get("start"), turn.get("end")
        if not isinstance(start, (int, float)) or not isinstance(end, (int, float)):
            continue
        if end - start < MIN_SPEECH_SECONDS * 1000 or start < 0 or end <= start:
            continue
        if any(min(end, other_end) - max(start, other_start) > 200
               for other_start, other_end in other_turns):
            continue
        turns.append((start, end))
    best_seconds = 0.0
    fallback = None
    for start, end in sorted(turns, key=lambda item: item[1] - item[0], reverse=True):
        segment = samples[int(start * 16):min(int(end * 16), len(samples),
                                               int(start * 16 + MAX_SPEECH_SECONDS * 16000))]
        if len(segment) < MIN_SPEECH_SECONDS * 16000:
            continue
        cleaned = preprocess_wav(segment, source_sr=16000)
        seconds = len(cleaned) / 16000
        best_seconds = max(best_seconds, seconds)
        if seconds >= PREFERRED_SPEECH_SECONDS:
            return cleaned, seconds
        if seconds >= MIN_SPEECH_SECONDS and fallback is None:
            fallback = cleaned
    if fallback is not None:
        return fallback, len(fallback) / 16000
    return None, best_seconds


def enroll_confirmed_speaker(transcript_id: str, label: str, speaker_id: str) -> bool:
    """Return False when audio or enough clean speech is unavailable."""
    transcript = get_transcript_by_id(transcript_id)
    if not transcript or (transcript.get("speaker_ids") or {}).get(label) != speaker_id:
        print(f"speaker enrollment skipped: transcript={transcript_id} label={label} reason=assignment_changed")
        return False
    if not transcript.get("audio_url"):
        print(f"speaker enrollment skipped: transcript={transcript_id} label={label} reason=no_stored_audio")
        return False

    path = f"{transcript['user_id']}/{transcript_id}.m4a"
    audio = client.storage.from_(STORAGE_BUCKET).download(path)
    voice, seconds = _speaker_audio(audio, transcript.get("speaker_labels") or [], label)
    if voice is None:
        print(f"speaker enrollment skipped: transcript={transcript_id} label={label} reason=insufficient_speech seconds={seconds:.1f}")
        return False

    from resemblyzer import VoiceEncoder

    embedding = VoiceEncoder().embed_utterance(voice)
    if len(embedding) != 256:
        raise ValueError("Unexpected voice embedding size")
    # A correction made during processing must not enroll the wrong person.
    current = get_transcript_by_id(transcript_id)
    if not current or (current.get("speaker_ids") or {}).get(label) != speaker_id:
        print(f"speaker enrollment skipped: transcript={transcript_id} label={label} reason=assignment_changed")
        return False
    client.table("speaker_voice_samples").upsert({
        "speaker_id": speaker_id,
        "transcript_id": transcript_id,
        "speaker_label": label,
        "embedding": embedding.tolist(),
        "speech_seconds": round(seconds, 2),
    }, on_conflict="transcript_id,speaker_label").execute()
    return True


def enroll_in_background(transcript_id: str, label: str, speaker_id: str) -> None:
    try:
        enroll_confirmed_speaker(transcript_id, label, speaker_id)
    except Exception as exc:
        print(f"speaker enrollment failed: transcript={transcript_id} label={label}: {exc}")


def _best_match(embedding, speakers: list[dict], samples: list[dict]) -> dict | None:
    import numpy as np

    voice = np.asarray(embedding, dtype=np.float32)
    if voice.shape != (256,) or not np.isfinite(voice).all():
        return None
    voice_norm = np.linalg.norm(voice)
    if voice_norm == 0:
        return None
    names = {speaker["id"]: speaker["name"] for speaker in speakers}
    references = {}
    for sample in samples:
        speaker_id = sample.get("speaker_id")
        if speaker_id not in names:
            continue
        try:
            reference = np.asarray(sample.get("embedding"), dtype=np.float32)
        except (TypeError, ValueError):
            continue
        if reference.shape != (256,) or not np.isfinite(reference).all():
            continue
        reference_norm = np.linalg.norm(reference)
        if reference_norm == 0:
            continue
        references.setdefault(speaker_id, []).append(reference / reference_norm)
    if not references:
        return None
    ranked = []
    for speaker_id, vectors in references.items():
        centroid = np.mean(vectors, axis=0)
        norm = np.linalg.norm(centroid)
        if norm:
            ranked.append((float(np.dot(voice, centroid) / (voice_norm * norm)), speaker_id))
    if not ranked:
        return None
    ranked.sort(reverse=True)
    best_score, best_id = ranked[0]
    runner_up = ranked[1][0] if len(ranked) > 1 else -math.inf
    if best_score < POSSIBLE_MIN_SIMILARITY or best_score - runner_up < SUGGESTION_MIN_MARGIN:
        return None
    return {"speaker_id": best_id, "name": names[best_id], "score": best_score,
            "tier": "auto" if best_score > AUTO_MIN_SIMILARITY else "possible"}


def _match_labels(transcript: dict, labels: list[str]) -> dict[str, dict]:
    if not labels or not transcript.get("audio_url"):
        return {}
    transcript_id = transcript["id"]
    user_id = transcript["user_id"]
    from src.services.database import get_speakers
    speakers = get_speakers(user_id)
    if not speakers:
        return {}
    ids = [speaker["id"] for speaker in speakers]
    samples = (client.table("speaker_voice_samples")
               .select("speaker_id,transcript_id,embedding")
               .in_("speaker_id", ids).neq("transcript_id", transcript_id)
               .limit(1000).execute().data)
    if not samples:
        return {}

    path = f"{user_id}/{transcript_id}.m4a"
    audio = client.storage.from_(STORAGE_BUCKET).download(path)
    decoded = _decode_audio(audio)
    from resemblyzer import VoiceEncoder
    encoder = None
    matches = {}
    for label in labels:
        voice, seconds = _speaker_audio(audio, transcript["speaker_labels"], label, decoded=decoded)
        if voice is None:
            continue
        if encoder is None:
            encoder = VoiceEncoder()
        embedding = encoder.embed_utterance(voice)
        match = _best_match(embedding, speakers, samples)
        if match:
            matches[label] = {**match, "embedding": embedding.tolist(), "speech_seconds": seconds}
    return matches


def suggest_speaker(transcript_id: str, label: str, user_id: str) -> dict | None:
    transcript = get_transcript_by_id(transcript_id)
    if not transcript or transcript.get("user_id") != user_id:
        return None
    if (transcript.get("speaker_names") or {}).get(label):
        return None
    if label not in {str(turn.get("speaker")) for turn in transcript.get("speaker_labels") or []}:
        return None
    match = _match_labels(transcript, [label]).get(label)
    return {key: match[key] for key in ("name", "score", "tier")} if match else None


def auto_identify_speakers(transcript_id: str, user_id: str) -> dict[str, str]:
    transcript = get_transcript_by_id(transcript_id)
    if not transcript or transcript.get("user_id") != user_id:
        return {}
    labels = list(dict.fromkeys(str(turn.get("speaker")) for turn in transcript.get("speaker_labels") or []
                                if turn.get("speaker") is not None))
    if not labels or not transcript.get("audio_url"):
        return {}
    current_names = transcript.get("speaker_names") or {}
    matches = _match_labels(transcript, [label for label in labels if label not in current_names])
    if not matches:
        return {}

    # A repeated identity across different diarized voices is ambiguous.
    matches = {label: match for label, match in matches.items() if match.get("tier", "auto") == "auto"}
    matched_ids = [match["speaker_id"] for match in matches.values()]
    unique = {label: match for label, match in matches.items()
              if matched_ids.count(match["speaker_id"]) == 1}
    if not unique:
        return {}

    latest = get_transcript_by_id(transcript_id)
    if not latest or latest.get("user_id") != user_id:
        return {}
    names = dict(latest.get("speaker_names") or {})
    ids = dict(latest.get("speaker_ids") or {})
    applied = {}
    for label, match in unique.items():
        if label in names or match["speaker_id"] in ids.values():
            continue
        names[label] = match["name"]
        ids[label] = match["speaker_id"]
        applied[label] = match["name"]
    if not applied:
        return {}

    result = (client.table("transcripts")
              .update({"speaker_names": names, "speaker_ids": ids, "summary": None})
              .eq("id", transcript_id)
              .eq("user_id", user_id)
              .eq("speaker_names", json.dumps(latest.get("speaker_names") or {}))
              .execute())
    if not result.data:
        return {}
    for label, match in unique.items():
        if label not in applied or "embedding" not in match:
            continue
        try:
            client.table("speaker_voice_samples").upsert({
                "speaker_id": match["speaker_id"], "transcript_id": transcript_id,
                "speaker_label": label, "embedding": match["embedding"],
                "speech_seconds": round(match["speech_seconds"], 2),
            }, on_conflict="transcript_id,speaker_label").execute()
        except Exception as exc:
            print(f"speaker sample update failed: transcript={transcript_id} label={label}: {exc}")
    return applied


def auto_identify_in_background(transcript_id: str, user_id: str) -> None:
    try:
        auto_identify_speakers(transcript_id, user_id)
    except Exception as exc:
        print(f"speaker auto-identification failed: transcript={transcript_id}: {exc}")
