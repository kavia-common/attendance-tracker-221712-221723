#!/usr/bin/env bash
set -euo pipefail

# This script initializes the PostgreSQL database by applying schema and seed scripts.
# It is idempotent: schema uses IF NOT EXISTS and seed checks before inserting.

# Required env vars are expected to be present in the environment:
# - POSTGRES_URL OR (POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB, POSTGRES_PORT)
# The CI/orchestrator provides these. We avoid hardcoding credentials here.

psql_cmd=""

if [[ -n "${POSTGRES_URL:-}" ]]; then
  psql_cmd="psql \"$POSTGRES_URL\""
else
  # Default host to localhost; these variables must be provided by the environment.
  : "${POSTGRES_USER:?POSTGRES_USER is required}"
  : "${POSTGRES_DB:?POSTGRES_DB is required}"
  : "${POSTGRES_PORT:?POSTGRES_PORT is required}"
  PGPASSWORD="${POSTGRES_PASSWORD:-}" export PGPASSWORD
  psql_cmd="psql -h localhost -p ${POSTGRES_PORT} -U ${POSTGRES_USER} -d ${POSTGRES_DB}"
fi

echo "Running database initialization with command: ${psql_cmd%% *} (details hidden)"

# Apply schema: create necessary tables if not exist
${psql_cmd} -v ON_ERROR_STOP=1 -c "
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('teacher','student')),
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);
"
${psql_cmd} -v ON_ERROR_STOP=1 -c "
CREATE TABLE IF NOT EXISTS classes (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  teacher_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);
"
${psql_cmd} -v ON_ERROR_STOP=1 -c "
CREATE TABLE IF NOT EXISTS class_members (
  class_id INTEGER NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  PRIMARY KEY (class_id, user_id)
);
"
${psql_cmd} -v ON_ERROR_STOP=1 -c "
CREATE TABLE IF NOT EXISTS attendance (
  id SERIAL PRIMARY KEY,
  class_id INTEGER NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status TEXT NOT NULL CHECK (status IN ('present','absent','late')),
  ts TIMESTAMP NOT NULL DEFAULT NOW()
);
"
${psql_cmd} -v ON_ERROR_STOP=1 -c "CREATE INDEX IF NOT EXISTS idx_attendance_class_ts ON attendance(class_id, ts DESC);"
${psql_cmd} -v ON_ERROR_STOP=1 -c "CREATE INDEX IF NOT EXISTS idx_attendance_user_ts ON attendance(user_id, ts DESC);"

echo "Schema ensured."

# Seed data idempotently
# Teacher
${psql_cmd} -v ON_ERROR_STOP=1 -c "
INSERT INTO users (email, name, role)
SELECT 'teacher@example.com','Lead Teacher','teacher'
WHERE NOT EXISTS (SELECT 1 FROM users WHERE email='teacher@example.com');
"

# Students
${psql_cmd} -v ON_ERROR_STOP=1 -c "
INSERT INTO users (email, name, role)
SELECT 'student1@example.com','Student One','student'
WHERE NOT EXISTS (SELECT 1 FROM users WHERE email='student1@example.com');
"
${psql_cmd} -v ON_ERROR_STOP=1 -c "
INSERT INTO users (email, name, role)
SELECT 'student2@example.com','Student Two','student'
WHERE NOT EXISTS (SELECT 1 FROM users WHERE email='student2@example.com');
"

# Demo class for the teacher
${psql_cmd} -v ON_ERROR_STOP=1 -c "
WITH t AS (
  SELECT id AS teacher_id FROM users WHERE email='teacher@example.com' LIMIT 1
)
INSERT INTO classes (name, teacher_id)
SELECT 'Demo Class', t.teacher_id
FROM t
WHERE NOT EXISTS (
  SELECT 1 FROM classes c WHERE c.name='Demo Class' AND c.teacher_id=t.teacher_id
);
"

# Enroll students to the class
${psql_cmd} -v ON_ERROR_STOP=1 -c "
WITH cls AS (SELECT id FROM classes WHERE name='Demo Class' LIMIT 1),
s1 AS (SELECT id FROM users WHERE email='student1@example.com' LIMIT 1),
s2 AS (SELECT id FROM users WHERE email='student2@example.com' LIMIT 1)
INSERT INTO class_members (class_id, user_id)
SELECT cls.id, s1.id FROM cls, s1
WHERE NOT EXISTS (SELECT 1 FROM class_members WHERE class_id=cls.id AND user_id=s1.id);
"
${psql_cmd} -v ON_ERROR_STOP=1 -c "
WITH cls AS (SELECT id FROM classes WHERE name='Demo Class' LIMIT 1),
s2 AS (SELECT id FROM users WHERE email='student2@example.com' LIMIT 1)
INSERT INTO class_members (class_id, user_id)
SELECT cls.id, s2.id FROM cls, s2
WHERE NOT EXISTS (SELECT 1 FROM class_members WHERE class_id=cls.id AND user_id=s2.id);
"

echo "Seed applied."
echo "Database initialization completed."
