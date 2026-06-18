# Test Infrastructure: Polla Mundialista E2E Test Suite

This document defines the E2E testing infrastructure, mocking strategy, and the 71 test cases implemented to verify the Polla Mundialista application's correctness, performance, and compliance with the shielding requirements.

## Test Architecture
- **Framework**: Python 3.13.7 + Playwright E2E testing library.
- **Server**: A background Python-based `http.server` running locally on port `8080` to serve the single-page application and its assets (`index.html`, `style.css`, `app.js`, etc.).
- **Mocking**: A comprehensive client-side JavaScript mock injected via Playwright’s `page.add_init_script(...)` to override `window.supabase` and intercept all Supabase database and Auth calls before scripts execute.
- **Anti-Flakiness**: Injection of style overrides that disable CSS transitions, transforms, animations, and jQuery/standard web animations, ensuring instant state rendering.

## Test Tiers & Execution
The test suite consists of exactly 71 test cases organized into four distinct tiers:
1. **Tier 1: Feature Coverage (30 Cases)** - Smoke / Happy Path flows covering all 6 core features.
2. **Tier 2: Boundary & Corner Cases (30 Cases)** - Validation limits (age gate, Venezuelan phone prefix, cédula regex, password limits, predictions lockout).
3. **Tier 3: Cross-Feature / Offline Cases (6 Cases)** - Network connectivity changes, IndexedDB caching/sync queueing, canvas rendering, user agent adaptations.
4. **Tier 4: System / Admin UI Cases (5 Cases)** - Database level trigger simulations, admin standings overrides, declaring tournament finished.

---

## 71 Test Cases Specification

### Tier 1: Smoke & Happy Path (30 Cases)
- **TC-T1-01**: User Registration Happy Path
- **TC-T1-02**: User Login Happy Path
- **TC-T1-03**: Session Retention on Page Reload
- **TC-T1-04**: User Logout Session Cleardown
- **TC-T1-05**: Onboarding Tutorial Slide Navigation
- **TC-T1-06**: Onboarding Tutorial Storage Save
- **TC-T1-07**: Save Match Prediction
- **TC-T1-08**: Update Match Prediction
- **TC-T1-09**: Activate Match Wildcard
- **TC-T1-10**: Deactivate Match Wildcard
- **TC-T1-11**: Edit Lock Manual Toggle
- **TC-T1-12**: Match Date Filter List Population
- **TC-T1-13**: Filter Matches List by Date
- **TC-T1-14**: Submit Group Leader Special Prediction
- **TC-T1-15**: Update Group Leader Special Prediction
- **TC-T1-16**: Global Leaderboard Rendering
- **TC-T1-17**: Podium Render Check
- **TC-T1-18**: Private League Creation
- **TC-T1-19**: Private League Code Copying/Sharing
- **TC-T1-20**: Join Private League
- **TC-T1-21**: Badge Information Modal
- **TC-T1-22**: Admin Dashboard Authorization Access
- **TC-T1-23**: Admin Matches Score List Display
- **TC-T1-24**: Admin Enter Match Score
- **TC-T1-25**: Export User Database to CSV
- **TC-T1-26**: Enable Push Notifications Switch
- **TC-T1-27**: Service Worker Installation Event
- **TC-T1-28**: Service Worker Activation and Cache Cleardown
- **TC-T1-29**: Service Worker Fetch Handler for Local Assets
- **TC-T1-30**: Service Worker Fetch Handler for Flag CDN

### Tier 2: Boundary & Corner Cases (30 Cases)
- **TC-T2-01**: Under 18 Age Gate Block
- **TC-T2-02**: Venezuelan Cédula Regex Format Violation
- **TC-T2-03**: Venezuelan Carrier Prefix Phone Validation
- **TC-T2-04**: Email Format Strict Syntax Check
- **TC-T2-05**: Password Length Limit Boundary
- **TC-T2-06**: Password Confirmation Mismatch
- **TC-T2-07**: Blank Registration Fields Validation
- **TC-T2-08**: Already Registered Cédula Rejection
- **TC-T2-09**: Empty Login Input Validations
- **TC-T2-10**: Login Non-existent Cédula Rejection
- **TC-T2-11**: Login Unconfirmed Email Rejection
- **TC-T2-12**: Match Prediction Without Login
- **TC-T2-13**: Negative Score Input Rejection
- **TC-T2-14**: Wildcard Activation on Unpredicted Match Rejection
- **TC-T2-15**: Match Kickoff 10-Minute Lockout
- **TC-T2-16**: Lockout Enforcement After Real Score Entered
- **TC-T2-17**: Wildcard Activation Limit (Max 3)
- **TC-T2-18**: Wildcard Modify on Locked Match Rejection
- **TC-T2-19**: Special Predictions Without Login
- **TC-T2-20**: Special Predictions Deadline Lockout
- **TC-T2-21**: Exact Score Point Calculation Logic (+6 PTS)
- **TC-T2-22**: Outcome Simple Point Calculation Logic (+3 PTS)
- **TC-T2-23**: Goal Difference Point Calculation Logic (+5 PTS)
- **TC-T2-24**: Incorrect Outcome Point Calculation Logic (0 PTS)
- **TC-T2-25**: Group Leader Points Allocation Condition
- **TC-T2-26**: Badge Logic: Pronosticador Activo (+5 PTS)
- **TC-T2-27**: Badge Logic: Ganador Frecuente (+10 PTS)
- **TC-T2-28**: Badge Logic: Ojo Clínico (+15 PTS)
- **TC-T2-29**: Badge Logic: Oráculo de Grupos (+15 PTS)
- **TC-T2-30**: Join Already Joined Private League

### Tier 3: Integration, Offline & Comparative (6 Cases)
- **TC-T3-01**: Offline Match Prediction Queueing
- **TC-T3-02**: Offline Queue Auto-Sync Upon Connection Restored
- **TC-T3-03**: Head-to-Head VS Modal Predictions Privacy
- **TC-T3-04**: Player UUID Privacy Checks
- **TC-T3-05**: Symmetrical Canvas Ticket Receipt Rendering
- **TC-T3-06**: iOS Safari Manual Install Guide Rendering

### Tier 4: Admin, Database Triggers & System (5 Cases)
- **TC-T4-01**: Database-level Kickoff Lockout Constraint
- **TC-T4-02**: Database-level Special Predictions Lockout Constraint
- **TC-T4-03**: Admin Manual Group Standing Override Application
- **TC-T4-04**: Admin Manual Group Standing Override Clearing
- **TC-T4-05**: Declare Tournament Finished Enforcement

---

## How to Run the Test Suite

1. Ensure Playwright is installed:
   ```bash
   pip install playwright
   playwright install
   ```
2. Execute the test runner script:
   ```bash
   python tests/run.py
   ```
3. The runner automatically starts the local background server, spins up chromium browser via Playwright, executes all 71 tests sequentially with interactive UI steps assertion, terminates the background server, and outputs a detailed execution log.
