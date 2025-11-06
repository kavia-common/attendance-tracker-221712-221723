# attendance-tracker-221712-221723

This workspace includes the database container for a real-time attendance app. It now ships with Firebase (Firestore) configuration and tooling for local development using the Firebase Emulator Suite.

Note: Legacy PostgreSQL helper scripts are present for convenience only (optional). The primary database is Firestore.

Contents
- firebase_realtime_database/
  - firebase.json (emulator + rules/indexes mapping)
  - firestore.rules (role-based security)
  - firestore.indexes.json (composite indexes)
  - database.rules.json (optional Realtime DB rules)
  - storage.rules (storage rules placeholder)
  - .env.sample (required envs)
  - seed/
    - seed_data.json (sample dataset)
    - seeder.js (Node.js seeder for Auth + Firestore)
- Optional: PostgreSQL helper scripts (backup_db.sh, restore_db.sh, startup.sh) and a simple DB viewer.

Prerequisites
- Node.js 18+ for running the seeder and optionally the Firebase CLI.
- Firebase CLI (optional but recommended): npm i -g firebase-tools
- If seeding production (not emulator), a Firebase service account or ADC must be available and GOOGLE_APPLICATION_CREDENTIALS set to its JSON.

Environment variables
Copy .env.sample to .env and fill in values:
- FIREBASE_PROJECT_ID
- FIREBASE_API_KEY (used by frontend; not required by Admin seeder)
- FIREBASE_APP_ID
- FIREBASE_MESSAGING_SENDER_ID
- FIREBASE_STORAGE_BUCKET (optional)
- USE_FIREBASE_EMULATOR=true to target emulator in local workflows

Emulator quick start
1) Install Firebase CLI:
   npm install -g firebase-tools

2) From firebase_realtime_database directory, start emulators:
   firebase emulators:start
   - Or specify only Firestore/Auth: firebase emulators:start --only firestore,auth

3) Seeding data to emulators:
   - Ensure .env has USE_FIREBASE_EMULATOR=true (or pass --emulator flag)
   - In firebase_realtime_database/seed run:
     npm install firebase-admin dotenv
     node seeder.js --emulator

4) Using rules and indexes:
   - Rules file: firestore.rules
   - Indexes file: firestore.indexes.json
   - Deploy/update to emulator (already auto loaded at start) or to project:
     firebase deploy --only firestore:rules,firestore:indexes

Security model highlights
- Custom claims:
  - role = 'teacher' or 'student' (set by seeder for demo users)
- Rules:
  - Students can mark attendance only for themselves and only when the session is open.
  - Teachers can manage classes, sessions, and attendance for sessions they own.
- Indexes support:
  - attendance: sessionId + studentId
  - sessions: classId + date

Seed data
- Users: 1 teacher and 2 students with roles applied via Auth custom claims.
- A sample class and session with one present and one absent entry.

Optional PostgreSQL utilities
- These scripts remain for optional local experiments; they are not required for the Firebase app flow:
  - backup_db.sh, restore_db.sh, startup.sh
  - db_visualizer/ simple viewer