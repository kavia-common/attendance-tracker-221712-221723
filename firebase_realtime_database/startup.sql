-- Attendance System Schema and Seed Data

-- Create enums
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE user_role AS ENUM ('student', 'teacher');
    END IF;
END$$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'attendance_status') THEN
        CREATE TYPE attendance_status AS ENUM ('present', 'absent', 'late');
    END IF;
END$$;

-- Tables
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role user_role NOT NULL,
    name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS classes (
    id BIGSERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    code TEXT NOT NULL UNIQUE,
    teacher_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS enrollments (
    id BIGSERIAL PRIMARY KEY,
    class_id BIGINT NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
    student_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'active'
);

CREATE TABLE IF NOT EXISTS sessions (
    id BIGSERIAL PRIMARY KEY,
    class_id BIGINT NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL
);

CREATE TABLE IF NOT EXISTS attendance (
    id BIGSERIAL PRIMARY KEY,
    session_id BIGINT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    student_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status attendance_status NOT NULL,
    marked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    marked_by UUID REFERENCES users(id) ON DELETE SET NULL
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_classes_teacher_id ON classes(teacher_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_enrollments_class_student ON enrollments(class_id, student_id);
CREATE INDEX IF NOT EXISTS idx_sessions_class_date ON sessions(class_id, date);
CREATE INDEX IF NOT EXISTS idx_attendance_session_student ON attendance(session_id, student_id);

-- Seed data (idempotent inserts)

-- Ensure pgcrypto for gen_random_uuid on some systems
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Users: 1 teacher, 3 students
WITH teacher AS (
  INSERT INTO users (role, name, email)
  SELECT 'teacher', 'Alice Teacher', 'alice.teacher@example.com'
  WHERE NOT EXISTS (SELECT 1 FROM users WHERE email='alice.teacher@example.com')
  RETURNING id
),
student1 AS (
  INSERT INTO users (role, name, email)
  SELECT 'student', 'Bob Student', 'bob.student@example.com'
  WHERE NOT EXISTS (SELECT 1 FROM users WHERE email='bob.student@example.com')
  RETURNING id
),
student2 AS (
  INSERT INTO users (role, name, email)
  SELECT 'student', 'Carol Student', 'carol.student@example.com'
  WHERE NOT EXISTS (SELECT 1 FROM users WHERE email='carol.student@example.com')
  RETURNING id
),
student3 AS (
  INSERT INTO users (role, name, email)
  SELECT 'student', 'Dave Student', 'dave.student@example.com'
  WHERE NOT EXISTS (SELECT 1 FROM users WHERE email='dave.student@example.com')
  RETURNING id
)
SELECT 1;

-- Class taught by teacher
WITH t AS (
  SELECT id FROM users WHERE email='alice.teacher@example.com'
),
ins AS (
  INSERT INTO classes (name, code, teacher_id)
  SELECT 'Intro to Real-time Systems', 'RT101', t.id
  FROM t
  WHERE NOT EXISTS (SELECT 1 FROM classes WHERE code='RT101')
  RETURNING id
)
SELECT 1;

-- Enroll students
WITH c AS (
  SELECT id FROM classes WHERE code='RT101'
),
s AS (
  SELECT id, email FROM users WHERE email IN ('bob.student@example.com','carol.student@example.com','dave.student@example.com')
)
INSERT INTO enrollments (class_id, student_id, status)
SELECT c.id, s.id, 'active'
FROM c, s
WHERE NOT EXISTS (
  SELECT 1 FROM enrollments e WHERE e.class_id=c.id AND e.student_id=s.id
);

-- Two sessions
WITH c AS (SELECT id FROM classes WHERE code='RT101')
INSERT INTO sessions (class_id, date, start_time, end_time)
SELECT c.id, d::date, '09:00'::time, '10:00'::time
FROM c
JOIN (VALUES (CURRENT_DATE), (CURRENT_DATE + INTERVAL '1 day')) as dates(d)
ON TRUE
WHERE NOT EXISTS (
  SELECT 1 FROM sessions s WHERE s.class_id=c.id AND s.date = d::date
);

-- Attendance rows: mark for first session
WITH s1 AS (
  SELECT s.id as session_id
  FROM sessions s
  JOIN classes c ON c.id=s.class_id
  WHERE c.code='RT101'
  ORDER BY s.date ASC
  LIMIT 1
),
t AS (SELECT id as teacher_id FROM users WHERE email='alice.teacher@example.com'),
studs AS (
  SELECT u.id as student_id, u.email
  FROM users u
  WHERE u.email IN ('bob.student@example.com','carol.student@example.com','dave.student@example.com')
),
comb AS (
  SELECT s1.session_id, studs.student_id, studs.email, t.teacher_id
  FROM s1, studs, t
)
INSERT INTO attendance (session_id, student_id, status, marked_by)
SELECT c.session_id,
       c.student_id,
       CASE c.email
         WHEN 'bob.student@example.com' THEN 'present'
         WHEN 'carol.student@example.com' THEN 'late'
         ELSE 'absent'
       END::attendance_status,
       c.teacher_id
FROM comb c
WHERE NOT EXISTS (
  SELECT 1 FROM attendance a WHERE a.session_id=c.session_id AND a.student_id=c.student_id
);

-- Attendance for second session: only one present
WITH s2 AS (
  SELECT s.id as session_id
  FROM sessions s
  JOIN classes c ON c.id=s.class_id
  WHERE c.code='RT101'
  ORDER BY s.date DESC
  LIMIT 1
),
t AS (SELECT id as teacher_id FROM users WHERE email='alice.teacher@example.com'),
bob AS (SELECT id as student_id FROM users WHERE email='bob.student@example.com')
INSERT INTO attendance (session_id, student_id, status, marked_by)
SELECT s2.session_id, bob.student_id, 'present'::attendance_status, t.teacher_id
FROM s2, t, bob
WHERE NOT EXISTS (
  SELECT 1 FROM attendance a WHERE a.session_id=s2.session_id AND a.student_id=bob.student_id
);
