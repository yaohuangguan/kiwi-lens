ALTER TABLE profiles ADD COLUMN display_name TEXT NOT NULL DEFAULT '';

CREATE TABLE IF NOT EXISTS google_identities (
  google_sub TEXT PRIMARY KEY,
  user_id TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS google_identities_user_id ON google_identities(user_id);
