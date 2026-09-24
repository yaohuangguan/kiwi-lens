CREATE TABLE IF NOT EXISTS route_history (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  destination_name TEXT NOT NULL,
  destination_latitude REAL NOT NULL,
  destination_longitude REAL NOT NULL,
  mode TEXT NOT NULL,
  distance_meters INTEGER,
  duration_seconds INTEGER,
  started_at INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS route_history_user_date ON route_history(user_id, started_at DESC);

CREATE TABLE IF NOT EXISTS place_reviews (
  user_id TEXT NOT NULL,
  place_id TEXT NOT NULL,
  place_name TEXT NOT NULL,
  rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment TEXT NOT NULL DEFAULT '',
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, place_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS place_reviews_user_date ON place_reviews(user_id, updated_at DESC);
