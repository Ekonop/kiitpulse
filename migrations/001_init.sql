-- KIITPulse schema.
--
-- Redis owns the live radar and presence; Postgres owns what must survive a
-- restart: identity, the topic catalogue, and message history. Ephemeral means
-- "deleted on schedule", not "never written down" - a student should be able to
-- scroll back through tonight's conversation after their phone dies.

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Students are created on first successful @kiit.ac.in sign-in.
-- The roll number is the primary identity: the email is derived from it.
CREATE TABLE IF NOT EXISTS students (
    roll_number   TEXT PRIMARY KEY,
    email         TEXT NOT NULL UNIQUE,
    branch_tag    TEXT NOT NULL DEFAULT 'KIIT Student',
    display_name  TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- A roll number is 6-12 digits; anything else is not a KIIT identity.
    CONSTRAINT students_roll_format CHECK (roll_number ~ '^[0-9]{6,12}$'),
    -- The domain rule enforced in the database too, so a bug in the Go guard
    -- cannot insert a student from another campus.
    CONSTRAINT students_domain CHECK (email LIKE '%@kiit.ac.in')
);

CREATE TABLE IF NOT EXISTS topics (
    id                 TEXT PRIMARY KEY,
    title              TEXT NOT NULL,
    description        TEXT NOT NULL,
    zone               SMALLINT NOT NULL,
    tag                TEXT,
    created_by         TEXT REFERENCES students(roll_number) ON DELETE SET NULL,
    message_count      INTEGER NOT NULL DEFAULT 0,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_activity_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Topics are ephemeral by design; this is what the reaper looks at.
    expires_at         TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '24 hours')
);

CREATE INDEX IF NOT EXISTS topics_zone_activity_idx
    ON topics (zone, last_activity_at DESC);
CREATE INDEX IF NOT EXISTS topics_expiry_idx ON topics (expires_at);

CREATE TABLE IF NOT EXISTS messages (
    id               TEXT PRIMARY KEY,
    topic_id         TEXT NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
    sender_roll      TEXT NOT NULL REFERENCES students(roll_number) ON DELETE CASCADE,
    content          TEXT NOT NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Deleted by the retention job. Explicit per row so a topic can be extended
    -- without extending its oldest messages.
    expires_at       TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '24 hours'),

    CONSTRAINT messages_content_len CHECK (char_length(content) BETWEEN 1 AND 500)
);

CREATE INDEX IF NOT EXISTS messages_topic_time_idx
    ON messages (topic_id, created_at DESC);
CREATE INDEX IF NOT EXISTS messages_expiry_idx ON messages (expires_at);

CREATE TABLE IF NOT EXISTS reactions (
    message_id   TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    sender_roll  TEXT NOT NULL REFERENCES students(roll_number) ON DELETE CASCADE,
    emoji        TEXT NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- One reaction of a given emoji per student per message.
    PRIMARY KEY (message_id, sender_roll, emoji)
);

-- Voice presence is deliberately not persisted: a stage that outlives its
-- process is a ghost speaker.

-- Retention: delete expired rows. Run from cron or a scheduler.
-- Returns how many rows each statement removed so the caller can log it.
CREATE OR REPLACE FUNCTION pulse_reap_expired() RETURNS TABLE(table_name TEXT, removed BIGINT) AS $$
DECLARE
    n BIGINT;
BEGIN
    DELETE FROM messages WHERE expires_at < now();
    GET DIAGNOSTICS n = ROW_COUNT;
    table_name := 'messages'; removed := n; RETURN NEXT;

    DELETE FROM topics WHERE expires_at < now();
    GET DIAGNOSTICS n = ROW_COUNT;
    table_name := 'topics'; removed := n; RETURN NEXT;
END;
$$ LANGUAGE plpgsql;
