-- PostgreSQL Startup Schema for Attendance Tracker

-- Enable required extensions if available
DO $$
BEGIN
  BEGIN
    EXECUTE 'CREATE EXTENSION IF NOT EXISTS "uuid-ossp"';
  EXCEPTION WHEN undefined_file THEN
    -- Extension not available, ignore (we'll still allow uuid columns with defaults using gen_random_uuid if pgcrypto exists)
    RAISE NOTICE 'uuid-ossp extension not available';
  END;

  BEGIN
    EXECUTE 'CREATE EXTENSION IF NOT EXISTS "pgcrypto"';
  EXCEPTION WHEN undefined_file THEN
    RAISE NOTICE 'pgcrypto extension not available';
  END;
END
$$;

-- Helper: chooses a working UUID generator
CREATE OR REPLACE FUNCTION public._gen_uuid() RETURNS uuid AS $$
DECLARE
  v uuid;
BEGIN
  -- Try uuid-ossp first
  BEGIN
    EXECUTE 'SELECT uuid_generate_v4()' INTO v;
    RETURN v;
  EXCEPTION WHEN undefined_function THEN
    -- Try pgcrypto gen_random_uuid() (PG >= 13)
    BEGIN
      EXECUTE 'SELECT gen_random_uuid()' INTO v;
      RETURN v;
    EXCEPTION WHEN undefined_function THEN
      -- Fallback: pseudo-random uuid using md5 of random + clock_timestamp
      RETURN ((
        substr(md5(random()::text || clock_timestamp()::text),1,8) || '-' ||
        substr(md5(random()::text || clock_timestamp()::text),9,4) || '-' ||
        substr(md5(random()::text || clock_timestamp()::text),13,4) || '-' ||
        substr(md5(random()::text || clock_timestamp()::text),17,4) || '-' ||
        substr(md5(random()::text || clock_timestamp()::text),21,12)
      )::uuid);
    END;
  END;
END
$$ LANGUAGE plpgsql VOLATILE;

-- Tables

-- Users: teachers and students
CREATE TABLE IF NOT EXISTS public.users (
  id uuid PRIMARY KEY DEFAULT public._gen_uuid(),
  email text UNIQUE NOT NULL,
  display_name text NOT NULL,
  role text NOT NULL CHECK (role IN ('teacher','student')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Classes
CREATE TABLE IF NOT EXISTS public.classes (
  id uuid PRIMARY KEY DEFAULT public._gen_uuid(),
  name text NOT NULL,
  code text UNIQUE NOT NULL, -- join code
  teacher_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  schedule jsonb DEFAULT '{}'::jsonb, -- optional schedule metadata
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Enrollments: students in classes
CREATE TABLE IF NOT EXISTS public.enrollments (
  id uuid PRIMARY KEY DEFAULT public._gen_uuid(),
  class_id uuid NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  enrolled_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (class_id, student_id)
);

-- Attendance records
CREATE TABLE IF NOT EXISTS public.attendance_records (
  id uuid PRIMARY KEY DEFAULT public._gen_uuid(),
  class_id uuid NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  attendance_date date NOT NULL,
  status text NOT NULL CHECK (status IN ('present','absent','late','excused')),
  marked_by uuid REFERENCES public.users(id) ON DELETE SET NULL, -- who marked (teacher or self)
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (class_id, student_id, attendance_date)
);

-- Updated_at triggers (generic)
CREATE OR REPLACE FUNCTION public.set_updated_at() RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END
$$ LANGUAGE plpgsql;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'users_set_updated_at'
  ) THEN
    CREATE TRIGGER users_set_updated_at
      BEFORE UPDATE ON public.users
      FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'classes_set_updated_at'
  ) THEN
    CREATE TRIGGER classes_set_updated_at
      BEFORE UPDATE ON public.classes
      FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'attendance_records_set_updated_at'
  ) THEN
    CREATE TRIGGER attendance_records_set_updated_at
      BEFORE UPDATE ON public.attendance_records
      FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;
END
$$;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_users_role ON public.users(role);
CREATE INDEX IF NOT EXISTS idx_classes_teacher ON public.classes(teacher_id);
CREATE INDEX IF NOT EXISTS idx_enrollments_class ON public.enrollments(class_id);
CREATE INDEX IF NOT EXISTS idx_enrollments_student ON public.enrollments(student_id);
CREATE INDEX IF NOT EXISTS idx_attendance_class_date ON public.attendance_records(class_id, attendance_date);
CREATE INDEX IF NOT EXISTS idx_attendance_student_date ON public.attendance_records(student_id, attendance_date);
CREATE INDEX IF NOT EXISTS idx_attendance_status ON public.attendance_records(status);

-- Notification trigger to broadcast attendance updates
CREATE OR REPLACE FUNCTION public.notify_attendance_update() RETURNS trigger AS $$
DECLARE
  payload jsonb;
BEGIN
  IF (TG_OP = 'INSERT') THEN
    payload := jsonb_build_object(
      'event', 'insert',
      'record', to_jsonb(NEW)
    );
  ELSIF (TG_OP = 'UPDATE') THEN
    payload := jsonb_build_object(
      'event', 'update',
      'old', to_jsonb(OLD),
      'record', to_jsonb(NEW)
    );
  ELSE
    RETURN NULL;
  END IF;

  PERFORM pg_notify(
    'attendance_updates',
    payload::text
  );

  RETURN NEW;
END
$$ LANGUAGE plpgsql;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'attendance_records_notify_changes'
  ) THEN
    CREATE TRIGGER attendance_records_notify_changes
      AFTER INSERT OR UPDATE ON public.attendance_records
      FOR EACH ROW EXECUTE FUNCTION public.notify_attendance_update();
  END IF;
END
$$;
