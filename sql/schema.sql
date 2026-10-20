-- SQLite schema for the calendar assistant MVP.
-- Run with PRAGMA foreign_keys = ON for each database connection.

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS screenshots (
    id                  INTEGER PRIMARY KEY,
    source_type         TEXT NOT NULL CHECK (source_type IN ('plan', 'fact')),
    day_date            TEXT NOT NULL, -- YYYY-MM-DD; confirmed by the user
    sent_at             TEXT NOT NULL, -- ISO 8601 timestamp
    telegram_file_id    TEXT,
    device_type         TEXT CHECK (device_type IN ('phone', 'desktop', 'unknown')),
    visible_from        TEXT, -- HH:MM, earliest visible time on the screenshot
    visible_to          TEXT, -- HH:MM, latest visible time on the screenshot
    covers_full_day     INTEGER NOT NULL DEFAULT 0 CHECK (covers_full_day IN (0, 1)),
    date_confirmed      INTEGER NOT NULL DEFAULT 0 CHECK (date_confirmed IN (0, 1)),
    created_at          TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (visible_from IS NULL OR visible_from GLOB '[0-2][0-9]:[0-5][0-9]'),
    CHECK (visible_to IS NULL OR visible_to GLOB '[0-2][0-9]:[0-5][0-9]')
);

CREATE TABLE IF NOT EXISTS events (
    id                      INTEGER PRIMARY KEY,
    screenshot_id           INTEGER NOT NULL REFERENCES screenshots(id) ON DELETE CASCADE,
    day_date                TEXT NOT NULL, -- duplicated for simple indexed day queries
    source_type             TEXT NOT NULL CHECK (source_type IN ('plan', 'fact')),
    task_name_raw           TEXT NOT NULL,
    task_name_normalized    TEXT NOT NULL,
    start_time              TEXT, -- HH:MM
    end_time                TEXT, -- HH:MM
    duration_minutes        INTEGER CHECK (duration_minutes IS NULL OR duration_minutes >= 0),
    label                   TEXT,
    color_hex               TEXT,
    project_or_category     TEXT,
    visual_completion       TEXT NOT NULL DEFAULT 'unknown'
                            CHECK (visual_completion IN ('done', 'not_done', 'unknown')),
    recognition_confidence  REAL CHECK (
                                recognition_confidence IS NULL
                                OR (recognition_confidence >= 0.0 AND recognition_confidence <= 1.0)
                            ),
    created_at              TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (start_time IS NULL OR start_time GLOB '[0-2][0-9]:[0-5][0-9]'),
    CHECK (end_time IS NULL OR end_time GLOB '[0-2][0-9]:[0-5][0-9]'),
    CHECK (color_hex IS NULL OR color_hex GLOB '#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]')
);

-- The MVP assumes task names are unique within one day and one source set.
-- The application creates task_name_normalized using Unicode NFC, trim,
-- collapsed whitespace, and case folding; punctuation and word meaning stay intact.
CREATE UNIQUE INDEX IF NOT EXISTS uq_events_day_source_title
    ON events(day_date, source_type, task_name_normalized);

CREATE INDEX IF NOT EXISTS ix_events_day_source
    ON events(day_date, source_type);

CREATE TABLE IF NOT EXISTS event_matches (
    id                  INTEGER PRIMARY KEY,
    day_date            TEXT NOT NULL,
    plan_event_id       INTEGER UNIQUE REFERENCES events(id) ON DELETE CASCADE,
    fact_event_id       INTEGER UNIQUE REFERENCES events(id) ON DELETE CASCADE,
    result              TEXT NOT NULL CHECK (
                            result IN ('done', 'partially_done', 'not_done',
                                       'outside_plan', 'unconfirmed', 'uncertain')
                        ),
    match_method        TEXT CHECK (match_method IS NULL OR match_method = 'exact_normalized_title'),
    reason              TEXT,
    created_at          TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (plan_event_id IS NOT NULL OR fact_event_id IS NOT NULL),
    CHECK (
        (result IN ('done', 'partially_done') AND plan_event_id IS NOT NULL AND fact_event_id IS NOT NULL)
        OR (result IN ('not_done', 'unconfirmed') AND plan_event_id IS NOT NULL AND fact_event_id IS NULL)
        OR (result = 'outside_plan' AND plan_event_id IS NULL AND fact_event_id IS NOT NULL)
        OR (result = 'uncertain')
    )
);

CREATE INDEX IF NOT EXISTS ix_matches_day_result
    ON event_matches(day_date, result);
