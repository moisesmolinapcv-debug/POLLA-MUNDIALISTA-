# Project: Polla Mundialista Optimization & Shielding

## Architecture
- **Client Application**: Single-page application using HTML5 (`index.html`), CSS (`style.css`), and JavaScript (`app.js`, `supabase-js.js`) running in the browser. Employs a Service Worker (`sw.js`) to handle push notifications.
- **Backend Database**: Supabase PostgreSQL database holding tables:
  - `profiles`: User information (cedula, name, is_admin, is_mock, badges).
  - `matches`: Match details (match_no, group_letter, stage, home_code, away_code, kickoff/match_date, home_score, away_score).
  - `predictions`: Match predictions (id, user_id, match_no, home_score, away_score, wildcard, created_at).
  - `group_leader_predictions`: Group predictions (id, user_id, group_letter, team_code).
  - `app_config`: Key-value application configs (e.g. `tournament_finished`, `group_standings_overrides`).
  - `push_subscriptions`: Web push tokens mapped to user `cedula`.
- **Data Flow**:
  - Frontend queries Supabase Client for user info, matches, and user-owned predictions.
  - Predictions and special predictions are written directly to Supabase with PostgreSQL triggers checking time validity (10 minutes before kickoff for matches, and June 18, 2026, 10:00 AM VET for group leaders).
  - Leaderboard points, badges, and streaks are calculated on-the-fly or concurrently via the `leaderboard` View in the backend and retrieved using pagination.
  - Notifications are received via native Web Push event in `sw.js`.

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Exploration & Database Setup | Create PostgreSQL tables, triggers, views, and RLS policies on the database to secure predictions and calculate leaderboard. | None | DONE |
| M2 | Remove LocalStorage (R1) | Migrate user sessions, tutorial state, standings overrides, and tournament finished status to Supabase. Remove all LocalStorage references. | M1 | IN_PROGRESS (Conv: f7deb219-f0a7-4ff3-a005-3715e39733a8) |
| M3 | Remove Simulator & Mocks (R2) | Purge simulator UI panel and buttons from `index.html` and delete all simulator logic, simulated state, mock users, and mock user references from `app.js`. | M2 | IN_PROGRESS (Conv: f7deb219-f0a7-4ff3-a005-3715e39733a8) |
| M4 | Backend Leaderboard UI (R4) | Port point and badge rendering to fetch paginated leaderboard records from the `leaderboard` database view. | M1, M2 | IN_PROGRESS (Conv: f7deb219-f0a7-4ff3-a005-3715e39733a8) |
| M5 | Real Push Notifications Integration (R5) | Remove local notification simulation code, ensure client-side push notification subscription registration works properly, and Service Worker processes standard push payloads. | M2 | IN_PROGRESS (Conv: f7deb219-f0a7-4ff3-a005-3715e39733a8) |
| M6 | E2E Testing Suite (E2E Track) | Design, implement, and verify E2E tests covering all features, boundary cases, and real-world scenarios. | None | CANCELLED |
| M7 | E2E Pass & Verification | Run the test suite on the optimized platform and execute the Forensic Auditor to certify zero-cheating compliance. | M2, M3, M4, M5 | IN_PROGRESS (Conv: f7deb219-f0a7-4ff3-a005-3715e39733a8) |

## Interface Contracts
### Supabase View: `leaderboard`
- **Fields**:
  - `user_id` (UUID)
  - `cedula` (TEXT)
  - `name` (TEXT)
  - `predictions_count` (INT)
  - `exacts_count` (INT)
  - `outcomes_count` (INT)
  - `successful_wildcards_count` (INT)
  - `match_points` (NUMERIC)
  - `group_leader_points` (NUMERIC)
  - `badges_points` (NUMERIC)
  - `total_points` (NUMERIC)
  - `calculated_badges` (TEXT[])
  - `rank` (BIGINT)

### PostgreSQL Trigger: `trg_check_prediction_lockout`
- **Target**: `BEFORE INSERT OR UPDATE ON predictions`
- **Logic**: Rejects prediction creation/modification if `now() >= matches.match_date - INTERVAL '10 minutes'` or if match outcomes exist, unless the current user is an admin.

### PostgreSQL Trigger: `trg_check_special_predictions_lockout`
- **Target**: `BEFORE INSERT OR UPDATE ON group_leader_predictions`
- **Logic**: Rejects special prediction creation/modification if `now() >= '2026-06-18 14:00:00+00'::TIMESTAMPTZ` (June 18, 2026, at 10:00 AM VET), unless the current user is an admin.

## Code Layout
- `/index.html` - App interface.
- `/style.css` - Custom styling.
- `/app.js` - Main client-side logic.
- `/supabase-js.js` - Supabase JS SDK client library (read-only).
- `/sw.js` - Service worker handling push events.
- `/world_cup_data.js` - Local static match lists and fixtures (used for offline display).
- `/schema.sql` - Database schema script containing tables, views, functions, triggers, and policy configurations.
