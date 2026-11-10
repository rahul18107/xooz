"""Conservative date evidence for time-specific chat questions."""

import re
from datetime import date, datetime, timedelta, timezone


def requested_day(question: str, local_today: date) -> date | None:
    matches = re.findall(r"\b(yesterday|today|tomorrow|tonight)\b", question, re.I)
    if len(set(word.lower() for word in matches)) != 1:
        return None
    if not matches:
        return None
    return local_today + timedelta(days={"yesterday": -1, "today": 0,
                                         "tonight": 0, "tomorrow": 1}[matches[0].lower()])


def asks_about_recording_day(question: str) -> bool:
    return bool(re.search(
        r"\b(?:did (?:i|we|you) (?:say|talk|discuss|mention|record)|"
        r"(?:say|talk|discuss|mention|record)(?:ed)?|conversations?|recordings?)\b",
        question, re.I,
    ))


def quote_supports_day(quote: str, recorded_at: str | None, target: date,
                       user_tz=timezone.utc) -> bool:
    """Only unambiguous dates in the cited words count as schedule evidence."""
    dates = set()
    for value in re.findall(r"\b\d{4}-\d{2}-\d{2}\b", quote):
        try:
            dates.add(date.fromisoformat(value))
        except ValueError:
            return False
    months = {name: index for index, name in enumerate(
        ("january", "february", "march", "april", "may", "june", "july",
         "august", "september", "october", "november", "december"), 1)}
    month_pattern = "|".join(months)
    for match in re.finditer(
        rf"\b({month_pattern})\s+(\d{{1,2}})(?:st|nd|rd|th)?(?:,?\s+(\d{{4}}))?\b",
        quote, re.I,
    ):
        year = int(match[3]) if match[3] else target.year
        try:
            candidate = date(year, months[match[1].lower()], int(match[2]))
        except ValueError:
            return False
        if not match[3]:
            # A yearless spoken date is usable only close to the recording.
            try:
                recorded = datetime.fromisoformat(recorded_at.replace("Z", "+00:00"))
                if recorded.tzinfo is None or abs((candidate - recorded.astimezone(user_tz).date()).days) > 31:
                    return False
            except (AttributeError, TypeError, ValueError):
                return False
        dates.add(candidate)
    if re.search(r"\b(?:today|tonight|tomorrow|yesterday)\b", quote, re.I):
        if not recorded_at:
            return False
        try:
            recorded = datetime.fromisoformat(recorded_at.replace("Z", "+00:00"))
            if recorded.tzinfo is None:
                return False
            base = recorded.astimezone(user_tz).date()
        except (TypeError, ValueError):
            return False
        for word in re.findall(r"\b(today|tonight|tomorrow|yesterday)\b", quote, re.I):
            dates.add(base + timedelta(days={"yesterday": -1, "today": 0,
                                         "tonight": 0, "tomorrow": 1}[word.lower()]))
    # Two distinct dates in one quote do not establish which one the event belongs to.
    return dates == {target}
