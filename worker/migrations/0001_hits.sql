-- One row per counted request or event. No IP addresses, cookies or visitor ids.
CREATE TABLE hits (
  ts       INTEGER NOT NULL,  -- unix seconds
  kind     TEXT    NOT NULL,  -- page | raw (.exs) | llms (llms*.txt) | run (Run button) | notfound
  path     TEXT    NOT NULL,
  client   TEXT    NOT NULL,  -- human | agent | tool | crawler
  agent    TEXT,              -- e.g. ClaudeBot, ChatGPT-User, curl; null for humans
  ref      TEXT,              -- referring host, '' when direct/unknown
  country  TEXT,
  device   TEXT               -- phone | tablet | desktop, humans only
);

CREATE INDEX hits_ts ON hits (ts);
CREATE INDEX hits_kind_ts ON hits (kind, ts);
