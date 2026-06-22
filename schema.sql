-- ============================================================================
-- PROJECT: POLLA MUNDIALISTA - DATABASE SCHEMA SCRIPT
-- DEFINITION: PostgreSQL Views, Functions, Triggers, and RLS Policies
-- SOURCE: .agents/explorer_setup/analysis.md
-- ============================================================================

-- ----------------------------------------------------------------------------
-- SECTION 1: ROW-LEVEL SECURITY (RLS) POLICIES ON 'predictions'
-- Description:
--   Ensures that users can only select, insert, update, or delete their own
--   predictions, except for admin users who can view all predictions.
--   Additionally, anyone can view predictions once the match has entered
--   its lockout window (10 minutes before kickoff) to allow comparison views.
-- ----------------------------------------------------------------------------

-- Enable Row-Level Security
ALTER TABLE predictions ENABLE ROW LEVEL SECURITY;

-- Clean up existing policies if they exist for idempotency
DROP POLICY IF EXISTS select_predictions_policy ON predictions;
DROP POLICY IF EXISTS insert_predictions_policy ON predictions;
DROP POLICY IF EXISTS update_predictions_policy ON predictions;
DROP POLICY IF EXISTS delete_predictions_policy ON predictions;

-- 1. SELECT Policy:
--   Users can view their own predictions, admins can view all predictions,
--   and other users can view them only after the lockout period (10 minutes before kickoff).
CREATE POLICY select_predictions_policy ON predictions
FOR SELECT
USING (
  auth.uid() = user_id 
  OR EXISTS (
    SELECT 1 FROM profiles 
    WHERE id = auth.uid() AND COALESCE(is_admin, FALSE) = TRUE
  )
  OR EXISTS (
    SELECT 1 FROM matches 
    WHERE matches.match_no = predictions.match_no 
    AND (
      now() >= (matches.match_date - INTERVAL '10 minutes')
      OR (matches.home_score IS NOT NULL AND matches.away_score IS NOT NULL)
    )
  )
);

-- 2. INSERT Policy:
--   Users can only insert predictions where the user_id matches their authenticated user ID.
CREATE POLICY insert_predictions_policy ON predictions
FOR INSERT
WITH CHECK (
  auth.uid() = user_id
);

-- 3. UPDATE Policy:
--   Users can only update predictions that they own.
CREATE POLICY update_predictions_policy ON predictions
FOR UPDATE
USING (
  auth.uid() = user_id
)
WITH CHECK (
  auth.uid() = user_id
);

-- 4. DELETE Policy:
--   Users can only delete predictions that they own.
CREATE POLICY delete_predictions_policy ON predictions
FOR DELETE
USING (
  auth.uid() = user_id
);


-- ----------------------------------------------------------------------------
-- SECTION 2: TIME-SHIELDING LOCKOUT FUNCTIONS AND TRIGGERS
-- Description:
--   Protects prediction submissions (for matches and group leaders) from 
--   being modified after kickoff limits or when results are registered.
-- ----------------------------------------------------------------------------

-- A. Lockout check trigger for 'predictions' table
CREATE OR REPLACE FUNCTION check_prediction_lockout()
RETURNS TRIGGER AS $$
DECLARE
    v_kickoff TIMESTAMPTZ;
    v_home_score INT;
    v_away_score INT;
    v_tournament_finished TEXT;
    v_is_admin BOOLEAN;
BEGIN
    -- 1. Check if the current user is an admin (bypass checks if true)
    SELECT COALESCE(is_admin, FALSE) INTO v_is_admin
    FROM profiles
    WHERE id = auth.uid();
    
    IF v_is_admin THEN
        RETURN NEW;
    END IF;

    -- NEW: Restrict predictions to match range #41 to #72 for non-admin users
    IF NEW.match_no < 41 OR NEW.match_no > 72 THEN
        RAISE EXCEPTION 'Este partido no está disponible para pronósticos de usuarios.';
    END IF;

    -- 2. Check tournament completion state
    SELECT value INTO v_tournament_finished
    FROM app_config
    WHERE key = 'tournament_finished';
    
    IF v_tournament_finished = 'true' THEN
        RAISE EXCEPTION 'El torneo ha concluido. No se permiten más predicciones.';
    END IF;

    -- 3. Fetch match details (kickoff and real scores)
    SELECT match_date, home_score, away_score
    INTO v_kickoff, v_home_score, v_away_score
    FROM matches
    WHERE match_no = NEW.match_no;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El partido especificado no existe.';
    END IF;

    -- 4. Block if match has ended / real outcomes exist
    IF v_home_score IS NOT NULL AND v_away_score IS NOT NULL THEN
        RAISE EXCEPTION 'El partido ya tiene un marcador registrado. No se puede pronosticar.';
    END IF;

    -- 5. Lockout check: 10 minutes before kickoff
    IF now() >= (v_kickoff - INTERVAL '10 minutes') THEN
        RAISE EXCEPTION 'Límite de tiempo excedido. Los pronósticos se cierran 10 minutos antes del partido.';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Clean up and create trigger for 'predictions' table
DROP TRIGGER IF EXISTS trg_check_prediction_lockout ON predictions;
CREATE TRIGGER trg_check_prediction_lockout
BEFORE INSERT OR UPDATE ON predictions
FOR EACH ROW
EXECUTE FUNCTION check_prediction_lockout();


-- B. Lockout check trigger for 'group_leader_predictions' (Special predictions)
CREATE OR REPLACE FUNCTION check_special_predictions_lockout()
RETURNS TRIGGER AS $$
DECLARE
    v_is_admin BOOLEAN;
BEGIN
    -- 1. Check if the current user is an admin (bypass checks if true)
    SELECT COALESCE(is_admin, FALSE) INTO v_is_admin
    FROM profiles
    WHERE id = auth.uid();
    
    IF v_is_admin THEN
        RETURN NEW;
    END IF;

    -- 2. Lockout check: Group stage kickoff deadline (June 23, 2026 at 12:00 PM VET / 4:00 PM UTC)
    IF now() >= '2026-06-23 16:00:00+00'::TIMESTAMPTZ THEN
        RAISE EXCEPTION 'El período para seleccionar líderes de grupo ha expirado.';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Clean up and create trigger for 'group_leader_predictions' table
DROP TRIGGER IF EXISTS trg_check_special_predictions_lockout ON group_leader_predictions;
CREATE TRIGGER trg_check_special_predictions_lockout
BEFORE INSERT OR UPDATE ON group_leader_predictions
FOR EACH ROW
EXECUTE FUNCTION check_special_predictions_lockout();


-- ----------------------------------------------------------------------------
-- SECTION 2B: DATABASE STRENGTHENING AND INTEGRITY CONSTRAINTS
-- Description:
--   Añade restricciones CHECK para asegurar que los marcadores estén entre 0 y 99.
--   Añade un trigger para proteger roles administrativos de actualizaciones por cliente.
-- ----------------------------------------------------------------------------

-- 1. Restricción de rango de marcadores en predictions (0 a 99 goles)
ALTER TABLE public.predictions DROP CONSTRAINT IF EXISTS check_predictions_scores;
ALTER TABLE public.predictions ADD CONSTRAINT check_predictions_scores 
  CHECK (home_score >= 0 AND home_score <= 99 AND away_score >= 0 AND away_score <= 99);

-- 2. Restricción de rango de marcadores en matches (0 a 99 goles)
ALTER TABLE public.matches DROP CONSTRAINT IF EXISTS check_matches_scores;
ALTER TABLE public.matches ADD CONSTRAINT check_matches_scores 
  CHECK ((home_score IS NULL) OR (home_score >= 0 AND home_score <= 99 AND away_score >= 0 AND away_score <= 99));

-- 3. Trigger para bloquear por completo la modificación de roles administrativos desde el cliente
CREATE OR REPLACE FUNCTION protect_profile_roles()
RETURNS TRIGGER AS $$
BEGIN
  IF (OLD.is_admin IS DISTINCT FROM NEW.is_admin OR OLD.is_mock IS DISTINCT FROM NEW.is_mock) THEN
    IF current_setting('role', true) IN ('authenticated', 'anon') THEN
      RAISE EXCEPTION 'Acción rechazada: No se permite modificar roles administrativos (is_admin, is_mock) a través de la API del cliente.';
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recrear el trigger en la tabla profiles
DROP TRIGGER IF EXISTS trg_protect_profile_roles ON public.profiles;
CREATE TRIGGER trg_protect_profile_roles
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION protect_profile_roles();


-- ----------------------------------------------------------------------------
-- SECTION 3: VIEWS FOR STANDINGS AND LEADERBOARD CALCULATIONS
-- Description:
--   Computes dynamic standings, users' calculated points, and sorts the leaderboard.
-- ----------------------------------------------------------------------------

-- Clean up existing views in reverse dependency order
DROP VIEW IF EXISTS leaderboard CASCADE;
DROP VIEW IF EXISTS user_calculated_points CASCADE;
DROP VIEW IF EXISTS real_group_leaders CASCADE;
DROP VIEW IF EXISTS team_standings CASCADE;
DROP VIEW IF EXISTS group_status CASCADE;

-- 1. View: group_status
--   Determines if all matches in each group stage have finished.
CREATE OR REPLACE VIEW group_status AS
SELECT 
  group_letter,
  (COUNT(*) FILTER (WHERE home_score IS NULL OR away_score IS NULL) = 0) AS all_finished
FROM matches
WHERE stage = 'group'
GROUP BY group_letter;

-- 2. View: team_standings
--   Calculates dynamic team standings for each group from matches data, respecting manual overrides.
CREATE OR REPLACE VIEW team_standings AS
WITH team_stats AS (
  -- Home match statistics
  SELECT 
    m.group_letter,
    m.home_code AS team_code,
    COUNT(m.match_no) FILTER (WHERE m.home_score IS NOT NULL AND m.away_score IS NOT NULL) AS played,
    COUNT(m.match_no) FILTER (WHERE m.home_score > m.away_score) AS wins,
    COUNT(m.match_no) FILTER (WHERE m.home_score = m.away_score AND m.home_score IS NOT NULL) AS draws,
    COUNT(m.match_no) FILTER (WHERE m.home_score < m.away_score) AS losses,
    COALESCE(SUM(m.home_score), 0) AS gf,
    COALESCE(SUM(m.away_score), 0) AS ga
  FROM matches m
  WHERE m.stage = 'group'
  GROUP BY m.group_letter, m.home_code
  
  UNION ALL
  
  -- Away match statistics
  SELECT 
    m.group_letter,
    m.away_code AS team_code,
    COUNT(m.match_no) FILTER (WHERE m.home_score IS NOT NULL AND m.away_score IS NOT NULL) AS played,
    COUNT(m.match_no) FILTER (WHERE m.home_score < m.away_score) AS wins,
    COUNT(m.match_no) FILTER (WHERE m.home_score = m.away_score AND m.home_score IS NOT NULL) AS draws,
    COUNT(m.match_no) FILTER (WHERE m.home_score > m.away_score) AS losses,
    COALESCE(SUM(m.away_score), 0) AS gf,
    COALESCE(SUM(m.home_score), 0) AS ga
  FROM matches m
  WHERE m.stage = 'group'
  GROUP BY m.group_letter, m.away_code
),
aggregated_stats AS (
  -- Combine home and away statistics
  SELECT 
    group_letter,
    team_code,
    SUM(played) as played,
    SUM(wins) as wins,
    SUM(draws) as draws,
    SUM(losses) as losses,
    SUM(gf) as gf,
    SUM(ga) as ga,
    (SUM(gf) - SUM(ga)) as gd,
    (SUM(wins) * 3 + SUM(draws) * 1) as pts
  FROM team_stats
  GROUP BY group_letter, team_code
),
overrides AS (
  SELECT COALESCE(
    (SELECT value::jsonb FROM app_config WHERE key = 'group_standings_overrides'),
    '{}'::jsonb
  ) as data
),
ordered_stats AS (
  SELECT 
    a.group_letter,
    a.team_code,
    a.played,
    a.wins,
    a.draws,
    a.losses,
    a.gf,
    a.ga,
    a.gd,
    a.pts,
    COALESCE(
      (
        SELECT idx - 1
        FROM overrides o,
             jsonb_array_elements_text(o.data->a.group_letter) WITH ORDINALITY AS elem(val, idx)
        WHERE val = a.team_code
        LIMIT 1
      ),
      -1
    ) AS override_pos
  FROM aggregated_stats a
)
SELECT 
  group_letter,
  team_code,
  ROW_NUMBER() OVER (
    PARTITION BY group_letter 
    ORDER BY 
      CASE WHEN override_pos >= 0 THEN override_pos ELSE 9999 END ASC,
      pts DESC, 
      gd DESC, 
      gf DESC,
      team_code ASC
  ) as rank
FROM ordered_stats;

-- 3. View: real_group_leaders
--   Filters the team_standings view to get the leader (rank = 1) for each group.
CREATE OR REPLACE VIEW real_group_leaders AS
SELECT group_letter, team_code
FROM team_standings
WHERE rank = 1;

-- 4. View: user_calculated_points
--   Computes points and statistics per user.
--   Rules:
--     - Exact score: 6 points. Wildcard doubles to 12.
--     - Outcome correct (win/loss/draw):
--       - Base: 3 points. Wildcard doubles to 6.
--       - If outcome is correct, not a draw, and goal difference is exact: +2 points. Wildcard doubles to +4 (total 10).
--     - Correct Group Leader: 5 points (only calculated once all group stage matches are finished).
--     - Badges points:
--       - Pronosticador Activo (>= 25 predictions): 5 pts
--       - Ganador Frecuente (>= 12 correct outcomes): 10 pts
--       - Ojo Clínico (>= 3 exact predictions): 15 pts
--       - Oráculo de Grupos (>= 6 correct group leaders): 15 pts
--       - HAT-TRICK VIP (assigned badge): 20 pts
CREATE OR REPLACE VIEW user_calculated_points AS
WITH match_preds AS (
  SELECT
    p.user_id,
    COUNT(*) FILTER (WHERE p.home_score IS NOT NULL AND p.away_score IS NOT NULL) AS predictions_count,
    SUM(
      CASE 
        WHEN m.home_score IS NULL OR m.away_score IS NULL OR p.home_score IS NULL OR p.away_score IS NULL THEN 0
        WHEN p.home_score = m.home_score AND p.away_score = m.away_score THEN 6 * (CASE WHEN p.wildcard THEN 2 ELSE 1 END)
        WHEN SIGN(p.home_score - p.away_score) = SIGN(m.home_score - m.away_score) THEN
          (3 + CASE WHEN m.home_score != m.away_score AND (p.home_score - p.away_score) = (m.home_score - m.away_score) THEN 2 ELSE 0 END)
          * (CASE WHEN p.wildcard THEN 2 ELSE 1 END)
        ELSE 0
      END
    ) AS match_points,
    COUNT(*) FILTER (
      WHERE m.home_score IS NOT NULL AND m.away_score IS NOT NULL 
      AND p.home_score = m.home_score AND p.away_score = m.away_score
    ) AS exacts_count,
    COUNT(*) FILTER (
      WHERE m.home_score IS NOT NULL AND m.away_score IS NOT NULL 
      AND SIGN(p.home_score - p.away_score) = SIGN(m.home_score - m.away_score)
    ) AS outcomes_count,
    COUNT(*) FILTER (
      WHERE m.home_score IS NOT NULL AND m.away_score IS NOT NULL 
      AND p.wildcard 
      AND (
        (p.home_score = m.home_score AND p.away_score = m.away_score)
        OR SIGN(p.home_score - p.away_score) = SIGN(m.home_score - m.away_score)
      )
    ) AS successful_wildcards_count
  FROM predictions p
  JOIN matches m ON p.match_no = m.match_no
  GROUP BY p.user_id
),
group_preds AS (
  SELECT 
    glp.user_id,
    SUM(
      CASE 
        WHEN gs.all_finished AND glp.team_code = rgl.team_code THEN 5
        ELSE 0
      END
    ) AS group_leader_points,
    COUNT(*) FILTER (
      WHERE gs.all_finished AND glp.team_code = rgl.team_code
    ) AS correct_leaders_count
  FROM group_leader_predictions glp
  JOIN real_group_leaders rgl ON glp.group_letter = rgl.group_letter
  JOIN group_status gs ON glp.group_letter = gs.group_letter
  GROUP BY glp.user_id
)
SELECT 
  prof.id AS user_id,
  prof.cedula,
  prof.name,
  prof.is_admin,
  prof.is_mock,
  COALESCE(mp.predictions_count, 0) AS predictions_count,
  COALESCE(mp.exacts_count, 0) AS exacts_count,
  COALESCE(mp.outcomes_count, 0) AS outcomes_count,
  COALESCE(mp.successful_wildcards_count, 0) AS successful_wildcards_count,
  COALESCE(mp.match_points, 0) AS match_points,
  COALESCE(gp.group_leader_points, 0) AS group_leader_points,
  COALESCE(gp.correct_leaders_count, 0) AS correct_leaders_count,
  
  -- Calculate individual badge criteria points
  (
    (CASE WHEN COALESCE(mp.exacts_count, 0) >= 3 THEN 15 ELSE 0 END) +
    (CASE WHEN COALESCE(mp.outcomes_count, 0) >= 12 THEN 10 ELSE 0 END) +
    (CASE WHEN COALESCE(mp.predictions_count, 0) >= 25 THEN 5 ELSE 0 END) +
    (CASE WHEN COALESCE(gp.correct_leaders_count, 0) >= 6 THEN 15 ELSE 0 END) +
    (CASE WHEN COALESCE(prof.badges, ARRAY[]::text[]) @> ARRAY['HAT-TRICK VIP']::text[] THEN 20 ELSE 0 END)
  ) AS badges_points,
  
  -- Sum total points (match points + group leader points + badges points)
  (
    COALESCE(mp.match_points, 0) + 
    COALESCE(gp.group_leader_points, 0) + 
    (
      (CASE WHEN COALESCE(mp.exacts_count, 0) >= 3 THEN 15 ELSE 0 END) +
      (CASE WHEN COALESCE(mp.outcomes_count, 0) >= 12 THEN 10 ELSE 0 END) +
      (CASE WHEN COALESCE(mp.predictions_count, 0) >= 25 THEN 5 ELSE 0 END) +
      (CASE WHEN COALESCE(gp.correct_leaders_count, 0) >= 6 THEN 15 ELSE 0 END) +
      (CASE WHEN COALESCE(prof.badges, ARRAY[]::text[]) @> ARRAY['HAT-TRICK VIP']::text[] THEN 20 ELSE 0 END)
    )
  ) AS total_points,
  
  -- Formulate the active badges array
  ARRAY_REMOVE(
    ARRAY[
      CASE WHEN COALESCE(mp.exacts_count, 0) >= 3 THEN 'Ojo Clínico' END,
      CASE WHEN COALESCE(mp.outcomes_count, 0) >= 12 THEN 'Ganador Frecuente' END,
      CASE WHEN COALESCE(mp.predictions_count, 0) >= 25 THEN 'Pronosticador Activo' END,
      CASE WHEN COALESCE(gp.correct_leaders_count, 0) >= 6 THEN 'Oráculo de Grupos' END,
      CASE WHEN COALESCE(prof.badges, ARRAY[]::text[]) @> ARRAY['HAT-TRICK VIP']::text[] THEN 'HAT-TRICK VIP' END
    ],
    NULL
  ) AS calculated_badges
FROM profiles prof
LEFT JOIN match_preds mp ON prof.id = mp.user_id
LEFT JOIN group_preds gp ON prof.id = gp.user_id;

-- 5. View: leaderboard
--   Public-Facing Leaderboard View (Excluding Admin and Mock Users).
--   Sorting rules:
--     1. Total Points (descending)
--     2. Exact score count (descending)
--     3. Non-exact outcomes count (descending)
--     4. Successful wildcards count (descending)
--     5. User Cedula (ascending)
CREATE OR REPLACE VIEW leaderboard AS
SELECT 
  user_id,
  cedula,
  name,
  predictions_count,
  exacts_count,
  outcomes_count,
  successful_wildcards_count,
  match_points,
  group_leader_points,
  badges_points,
  total_points,
  calculated_badges,
  ROW_NUMBER() OVER (
    ORDER BY 
      total_points DESC,
      exacts_count DESC,
      (outcomes_count - exacts_count) DESC,
      successful_wildcards_count DESC,
      cedula ASC
  ) as rank
FROM user_calculated_points
WHERE COALESCE(is_admin, FALSE) = FALSE AND COALESCE(is_mock, FALSE) = FALSE;


-- ----------------------------------------------------------------------------
-- SECTION 4: PERFORMANCE OPTIMIZATION (MATERIALIZED VIEW REFERSH TRIGGER)
-- Description:
--   To optimize performance under high load, 'leaderboard' can be converted
--   into a Materialized View. In that case, we can refresh it on demand 
--   when match scores are updated using the following trigger.
-- ----------------------------------------------------------------------------

/*
-- To migrate 'leaderboard' to a materialized view, run:
DROP VIEW IF EXISTS leaderboard;
CREATE MATERIALIZED VIEW leaderboard AS
SELECT 
  user_id,
  cedula,
  name,
  predictions_count,
  exacts_count,
  outcomes_count,
  successful_wildcards_count,
  match_points,
  group_leader_points,
  badges_points,
  total_points,
  calculated_badges,
  ROW_NUMBER() OVER (
    ORDER BY 
      total_points DESC,
      exacts_count DESC,
      (outcomes_count - exacts_count) DESC,
      successful_wildcards_count DESC,
      cedula ASC
  ) as rank
FROM user_calculated_points
WHERE COALESCE(is_admin, FALSE) = FALSE AND COALESCE(is_mock, FALSE) = FALSE;

-- Concurrent refresh requires a unique index:
CREATE UNIQUE INDEX ON leaderboard (user_id);

-- Trigger function to refresh the materialized view
CREATE OR REPLACE FUNCTION refresh_leaderboard()
RETURNS TRIGGER AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY leaderboard;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Trigger to refresh the materialized view on match score updates
DROP TRIGGER IF EXISTS trg_refresh_leaderboard ON matches;
CREATE TRIGGER trg_refresh_leaderboard
AFTER UPDATE OF home_score, away_score ON matches
FOR EACH STATEMENT
EXECUTE FUNCTION refresh_leaderboard();
*/
