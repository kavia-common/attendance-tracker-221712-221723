#!/usr/bin/env node
/**
 * Seeder for Firestore and Auth custom claims to enable the rules in firestore.rules.
 * - Seeds users (Auth + users collection)
 * - Sets custom claims: role = 'teacher' | 'student'
 * - Seeds classes, sessions, attendance
 *
 * Requires environment variables (see ../.env.sample). You can use dotenv or export envs before running.
 *
 * Usage:
 *   node seeder.js --emulator   # use local emulators
 *   node seeder.js              # use production project (requires proper Firebase Admin credentials)
 */

const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
const useEmulator = args.includes('--emulator') || process.env.USE_FIREBASE_EMULATOR === 'true';

// Load .env if present
try {
  require('dotenv').config({ path: path.resolve(__dirname, '..', '.env') });
} catch (_) {}

// Configure Admin SDK
let admin;
try {
  admin = require('firebase-admin');
} catch (e) {
  console.error('Missing dependency: firebase-admin. Please install it in your environment:');
  console.error('  npm install firebase-admin dotenv');
  process.exit(1);
}

const serviceAccountPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
if (!useEmulator && !serviceAccountPath) {
  console.warn('GOOGLE_APPLICATION_CREDENTIALS not set. For production seeding, set this to a service account JSON.');
}

if (useEmulator) {
  process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || 'localhost:8080';
  process.env.FIREBASE_AUTH_EMULATOR_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || 'localhost:9099';
  console.log('Seeding against Firebase Emulator Suite');
  console.log(` - Firestore: ${process.env.FIRESTORE_EMULATOR_HOST}`);
  console.log(` - Auth:      ${process.env.FIREBASE_AUTH_EMULATOR_HOST}`);
}

const projectId = process.env.FIREBASE_PROJECT_ID || 'demo-project';

if (!admin.apps.length) {
  const options = { projectId };
  if (!useEmulator && serviceAccountPath && fs.existsSync(serviceAccountPath)) {
    options.credential = admin.credential.cert(require(serviceAccountPath));
  } else {
    options.credential = admin.credential.applicationDefault();
  }
  admin.initializeApp(options);
}

const auth = admin.auth();
const db = admin.firestore();

async function upsertUserAuth(user) {
  try {
    // Try get existing
    const existing = await auth.getUser(user.uid).catch(() => null);
    if (!existing) {
      await auth.createUser({
        uid: user.uid,
        email: user.email,
        emailVerified: true,
        displayName: user.name
      });
      console.log(`Created auth user ${user.uid}`);
    } else {
      await auth.updateUser(user.uid, {
        email: user.email,
        displayName: user.name
      });
      console.log(`Updated auth user ${user.uid}`);
    }
    await auth.setCustomUserClaims(user.uid, { role: user.role });
    console.log(`Set custom claims for ${user.uid} -> role=${user.role}`);
  } catch (e) {
    console.error(`Auth error for ${user.uid}:`, e.message);
    throw e;
  }
}

async function seed() {
  const seedPath = path.resolve(__dirname, 'seed_data.json');
  const seedData = JSON.parse(fs.readFileSync(seedPath, 'utf-8'));

  // Users
  for (const u of seedData.users) {
    await upsertUserAuth(u);
    await db.collection('users').doc(u.uid).set({
      email: u.email,
      name: u.name,
      role: u.role,
      classIds: u.classIds || []
    }, { merge: true });
  }

  // Classes
  for (const c of seedData.classes) {
    await db.collection('classes').doc(c.id).set({
      name: c.name,
      code: c.code,
      ownerId: c.ownerId
    }, { merge: true });
  }

  // Sessions
  for (const s of seedData.sessions) {
    await db.collection('sessions').doc(s.id).set({
      classId: s.classId,
      date: s.date,
      startTime: s.startTime,
      endTime: s.endTime,
      ownerId: s.ownerId,
      open: s.open === true
    }, { merge: true });
  }

  // Attendance
  for (const a of seedData.attendance) {
    await db.collection('attendance').doc(a.id).set({
      sessionId: a.sessionId,
      studentId: a.studentId,
      status: a.status || 'present',
      markedAt: a.markedAt ? admin.firestore.Timestamp.fromDate(new Date(a.markedAt)) : null
    }, { merge: true });
  }

  console.log('Seeding complete.');
}

seed().then(() => process.exit(0)).catch(err => {
  console.error(err);
  process.exit(1);
});
