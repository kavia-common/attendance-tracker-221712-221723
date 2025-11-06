-- Seed data for Attendance Tracker (idempotent where possible)

WITH t AS (
  INSERT INTO public.users (email, display_name, role)
  VALUES
    ('teacher1@example.com', 'Alex Teacher', 'teacher')
  ON CONFLICT (email) DO UPDATE SET display_name = EXCLUDED.display_name
  RETURNING id
),
s AS (
  INSERT INTO public.users (email, display_name, role)
  VALUES
    ('student1@example.com', 'Sam Student', 'student'),
    ('student2@example.com', 'Riley Student', 'student'),
    ('student3@example.com', 'Jordan Student', 'student')
  ON CONFLICT (email) DO UPDATE SET display_name = EXCLUDED.display_name
  RETURNING id, email
)
INSERT INTO public.classes (name, code, teacher_id, schedule)
SELECT
  'Math 101' AS name,
  'MATH101' AS code,
  (SELECT id FROM t) AS teacher_id,
  '{"days":["Mon","Wed","Fri"],"time":"09:00","room":"101"}'::jsonb
WHERE NOT EXISTS (SELECT 1 FROM public.classes WHERE code = 'MATH101');

-- Get ids for following inserts
WITH teacher AS (
  SELECT id FROM public.users WHERE email = 'teacher1@example.com'
),
klass AS (
  SELECT id FROM public.classes WHERE code = 'MATH101'
),
students AS (
  SELECT id, email FROM public.users WHERE email IN ('student1@example.com','student2@example.com','student3@example.com')
)
-- Enrollments
INSERT INTO public.enrollments (class_id, student_id)
SELECT (SELECT id FROM klass), s.id
FROM students s
ON CONFLICT (class_id, student_id) DO NOTHING;

-- Attendance seed for two dates
WITH klass AS (
  SELECT id FROM public.classes WHERE code = 'MATH101'
),
teacher AS (
  SELECT id FROM public.users WHERE email = 'teacher1@example.com'
),
students AS (
  SELECT id, email FROM public.users WHERE email IN ('student1@example.com','student2@example.com','student3@example.com')
)
INSERT INTO public.attendance_records (class_id, student_id, attendance_date, status, marked_by, notes)
SELECT (SELECT id FROM klass), s.id, d.att_date, d.status, (SELECT id FROM teacher), d.notes
FROM students s
JOIN (
  VALUES
    (CURRENT_DATE - INTERVAL '1 day', 'present'::text, 'On time'::text),
    (CURRENT_DATE, 'present'::text, 'On time'::text)
) AS d(att_date, status, notes)
ON CONFLICT (class_id, student_id, attendance_date) DO NOTHING;

-- Small variation: make student2 late today
WITH klass AS (
  SELECT id FROM public.classes WHERE code = 'MATH101'
),
student2 AS (
  SELECT id FROM public.users WHERE email = 'student2@example.com'
),
teacher AS (
  SELECT id FROM public.users WHERE email = 'teacher1@example.com'
)
INSERT INTO public.attendance_records (class_id, student_id, attendance_date, status, marked_by, notes)
SELECT (SELECT id FROM klass), (SELECT id FROM student2), CURRENT_DATE, 'late', (SELECT id FROM teacher), 'Arrived 5 min late'
ON CONFLICT (class_id, student_id, attendance_date) DO UPDATE
SET status = EXCLUDED.status,
    notes = EXCLUDED.notes,
    updated_at = now();
