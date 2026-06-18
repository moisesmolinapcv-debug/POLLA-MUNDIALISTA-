-- =============================================================================
-- POLLA MUNDIALISTA — REFINAMIENTO PRE-PRODUCCIÓN
-- Ejecutar en el SQL Editor de Supabase (una sola vez, en orden)
-- Cubre: M1 (datos sensibles + deadline dinámico) + M5 (ocultar partidos)
-- =============================================================================


-- =============================================================================
-- MÓDULO 1-A: Agregar columnas nuevas a 'profiles'
-- =============================================================================

-- Columna para forzar cambio de contraseña tras reset por admin
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS must_change_password BOOLEAN DEFAULT FALSE;

-- Columna para teléfono (por si no existe ya)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS phone TEXT;

-- Columna para fecha de nacimiento (por si no existe ya)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS dob TEXT;

-- Columna para usuario de Parley (por si no existe ya)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS parley_username TEXT;


-- =============================================================================
-- MÓDULO 1-B: Corregir trigger handle_new_user()
-- Ahora copia phone, dob y parley_username de raw_user_meta_data a profiles
-- =============================================================================

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO profiles (id, cedula, name, email, phone, dob, parley_username)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'cedula', NEW.email),
    COALESCE(NEW.raw_user_meta_data->>'name', 'Usuario'),
    NEW.email,
    NEW.raw_user_meta_data->>'phone',
    NEW.raw_user_meta_data->>'dob',
    NEW.raw_user_meta_data->>'parley_username'
  ) ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recrear el trigger para que use la función actualizada
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION handle_new_user();


-- =============================================================================
-- MÓDULO 1-C: Deadline dinámico para pronósticos de líderes de grupo
-- Reemplaza la fecha hardcodeada por un valor configurable en app_config
-- =============================================================================

-- Insertar la nueva clave de configuración del deadline
-- Valor inicial: 22 de Junio 2026 a las 10:00 AM VET (14:00 UTC) — ajusta según necesites
INSERT INTO app_config (key, value)
VALUES ('special_predictions_deadline', '2026-06-22 14:00:00+00')
ON CONFLICT (key) DO NOTHING;

-- Actualizar el trigger para leer el deadline desde app_config en lugar de tenerlo hardcodeado
CREATE OR REPLACE FUNCTION check_special_predictions_lockout()
RETURNS TRIGGER AS $$
DECLARE
  v_is_admin BOOLEAN;
  v_deadline TIMESTAMPTZ;
BEGIN
  -- 1. Admin siempre puede pasar
  SELECT COALESCE(is_admin, FALSE) INTO v_is_admin
  FROM profiles WHERE id = auth.uid();
  IF v_is_admin THEN RETURN NEW; END IF;

  -- 2. Leer deadline dinámico desde app_config
  SELECT value::TIMESTAMPTZ INTO v_deadline
  FROM app_config WHERE key = 'special_predictions_deadline';

  -- 3. Si hay deadline configurado y ya pasó, bloquear
  IF v_deadline IS NOT NULL AND now() >= v_deadline THEN
    RAISE EXCEPTION 'El período para seleccionar líderes de grupo ha expirado.';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recrear el trigger
DROP TRIGGER IF EXISTS trg_check_special_predictions_lockout ON group_leader_predictions;
CREATE TRIGGER trg_check_special_predictions_lockout
BEFORE INSERT OR UPDATE ON group_leader_predictions
FOR EACH ROW EXECUTE FUNCTION check_special_predictions_lockout();


-- =============================================================================
-- MÓDULO 5-A: Agregar columna 'hidden' a la tabla matches
-- =============================================================================

ALTER TABLE matches ADD COLUMN IF NOT EXISTS hidden BOOLEAN DEFAULT FALSE;

-- Marcar los partidos #1 al #24 como ocultos (ya se jugaron antes del lanzamiento)
UPDATE matches SET hidden = TRUE WHERE match_no BETWEEN 1 AND 24;


-- =============================================================================
-- MÓDULO 5-B: Actualizar la vista user_calculated_points
-- Los puntos de pronósticos SOLO se calculan sobre partidos NO ocultos
-- IMPORTANTE: team_standings, group_status y real_group_leaders
-- NO se modifican — siguen usando TODOS los partidos para calcular standings
-- =============================================================================

-- Limpiar vistas en orden de dependencia
DROP VIEW IF EXISTS leaderboard CASCADE;
DROP VIEW IF EXISTS user_calculated_points CASCADE;
DROP VIEW IF EXISTS real_group_leaders CASCADE;
DROP VIEW IF EXISTS team_standings CASCADE;
DROP VIEW IF EXISTS group_status CASCADE;

-- 4.1 Estado de grupos (usa TODOS los partidos, incluyendo ocultos)
CREATE OR REPLACE VIEW group_status AS
SELECT
  group_letter,
  (COUNT(*) FILTER (WHERE home_score IS NULL OR away_score IS NULL) = 0) AS all_finished
FROM matches
WHERE stage = 'group'
GROUP BY group_letter;

-- 4.2 Tabla de posiciones por equipo (usa TODOS los partidos, incluyendo ocultos)
CREATE OR REPLACE VIEW team_standings AS
WITH team_stats AS (
  SELECT m.group_letter, m.home_code AS team_code,
    COUNT(m.match_no) FILTER (WHERE m.home_score IS NOT NULL AND m.away_score IS NOT NULL) AS played,
    COUNT(m.match_no) FILTER (WHERE m.home_score > m.away_score) AS wins,
    COUNT(m.match_no) FILTER (WHERE m.home_score = m.away_score AND m.home_score IS NOT NULL) AS draws,
    COUNT(m.match_no) FILTER (WHERE m.home_score < m.away_score) AS losses,
    COALESCE(SUM(m.home_score), 0) AS gf, COALESCE(SUM(m.away_score), 0) AS ga
  FROM matches m WHERE m.stage = 'group' GROUP BY m.group_letter, m.home_code
  UNION ALL
  SELECT m.group_letter, m.away_code AS team_code,
    COUNT(m.match_no) FILTER (WHERE m.home_score IS NOT NULL AND m.away_score IS NOT NULL) AS played,
    COUNT(m.match_no) FILTER (WHERE m.home_score < m.away_score) AS wins,
    COUNT(m.match_no) FILTER (WHERE m.home_score = m.away_score AND m.home_score IS NOT NULL) AS draws,
    COUNT(m.match_no) FILTER (WHERE m.home_score > m.away_score) AS losses,
    COALESCE(SUM(m.away_score), 0) AS gf, COALESCE(SUM(m.home_score), 0) AS ga
  FROM matches m WHERE m.stage = 'group' GROUP BY m.group_letter, m.away_code
),
agg AS (
  SELECT group_letter, team_code,
    SUM(played) as played, SUM(wins) as wins, SUM(draws) as draws, SUM(losses) as losses,
    SUM(gf) as gf, SUM(ga) as ga, (SUM(gf)-SUM(ga)) as gd, (SUM(wins)*3+SUM(draws)) as pts
  FROM team_stats GROUP BY group_letter, team_code
)
SELECT group_letter, team_code,
  ROW_NUMBER() OVER (PARTITION BY group_letter ORDER BY pts DESC, gd DESC, gf DESC) as rank
FROM agg;

-- 4.3 Líderes reales de cada grupo
CREATE OR REPLACE VIEW real_group_leaders AS
SELECT group_letter, team_code FROM team_standings WHERE rank = 1;

-- 4.4 Puntos calculados por usuario
-- CLAVE: El JOIN de predictions con matches filtra COALESCE(m.hidden, FALSE) = FALSE
-- Esto excluye los partidos #1-#24 del cálculo de puntos del usuario
CREATE OR REPLACE VIEW user_calculated_points AS
WITH match_preds AS (
  SELECT p.user_id,
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
      AND ((p.home_score = m.home_score AND p.away_score = m.away_score)
        OR SIGN(p.home_score - p.away_score) = SIGN(m.home_score - m.away_score))
    ) AS successful_wildcards_count
  FROM predictions p
  -- ✅ Solo cuenta partidos que NO están ocultos
  JOIN matches m ON p.match_no = m.match_no AND COALESCE(m.hidden, FALSE) = FALSE
  GROUP BY p.user_id
),
group_preds AS (
  SELECT glp.user_id,
    SUM(CASE WHEN gs.all_finished AND glp.team_code = rgl.team_code THEN 5 ELSE 0 END) AS group_leader_points,
    COUNT(*) FILTER (WHERE gs.all_finished AND glp.team_code = rgl.team_code) AS correct_leaders_count
  FROM group_leader_predictions glp
  JOIN real_group_leaders rgl ON glp.group_letter = rgl.group_letter
  JOIN group_status gs ON glp.group_letter = gs.group_letter
  GROUP BY glp.user_id
)
SELECT
  prof.id AS user_id, prof.cedula, prof.name, prof.is_admin, prof.is_mock,
  COALESCE(mp.predictions_count, 0) AS predictions_count,
  COALESCE(mp.exacts_count, 0) AS exacts_count,
  COALESCE(mp.outcomes_count, 0) AS outcomes_count,
  COALESCE(mp.successful_wildcards_count, 0) AS successful_wildcards_count,
  COALESCE(mp.match_points, 0) AS match_points,
  COALESCE(gp.group_leader_points, 0) AS group_leader_points,
  COALESCE(gp.correct_leaders_count, 0) AS correct_leaders_count,
  (
    (CASE WHEN COALESCE(mp.exacts_count, 0) >= 3 THEN 15 ELSE 0 END) +
    (CASE WHEN COALESCE(mp.outcomes_count, 0) >= 15 THEN 10 ELSE 0 END) +
    (CASE WHEN COALESCE(mp.predictions_count, 0) >= 50 THEN 5 ELSE 0 END) +
    (CASE WHEN COALESCE(gp.correct_leaders_count, 0) >= 6 THEN 15 ELSE 0 END) +
    (CASE WHEN COALESCE(prof.badges, ARRAY[]::text[]) @> ARRAY['HAT-TRICK VIP']::text[] THEN 20 ELSE 0 END)
  ) AS badges_points,
  (
    COALESCE(mp.match_points, 0) +
    COALESCE(gp.group_leader_points, 0) +
    (CASE WHEN COALESCE(mp.exacts_count, 0) >= 3 THEN 15 ELSE 0 END) +
    (CASE WHEN COALESCE(mp.outcomes_count, 0) >= 15 THEN 10 ELSE 0 END) +
    (CASE WHEN COALESCE(mp.predictions_count, 0) >= 50 THEN 5 ELSE 0 END) +
    (CASE WHEN COALESCE(gp.correct_leaders_count, 0) >= 6 THEN 15 ELSE 0 END) +
    (CASE WHEN COALESCE(prof.badges, ARRAY[]::text[]) @> ARRAY['HAT-TRICK VIP']::text[] THEN 20 ELSE 0 END)
  ) AS total_points,
  ARRAY_REMOVE(ARRAY[
    CASE WHEN COALESCE(mp.exacts_count, 0) >= 3 THEN 'Ojo Clínico' END,
    CASE WHEN COALESCE(mp.outcomes_count, 0) >= 15 THEN 'Ganador Frecuente' END,
    CASE WHEN COALESCE(mp.predictions_count, 0) >= 50 THEN 'Pronosticador Activo' END,
    CASE WHEN COALESCE(gp.correct_leaders_count, 0) >= 6 THEN 'Oráculo de Grupos' END,
    CASE WHEN COALESCE(prof.badges, ARRAY[]::text[]) @> ARRAY['HAT-TRICK VIP']::text[] THEN 'HAT-TRICK VIP' END
  ], NULL) AS calculated_badges
FROM profiles prof
LEFT JOIN match_preds mp ON prof.id = mp.user_id
LEFT JOIN group_preds gp ON prof.id = gp.user_id;

-- 4.5 Vista pública del Leaderboard (excluye admins y mocks)
CREATE OR REPLACE VIEW leaderboard AS
SELECT
  user_id, cedula, name,
  predictions_count, exacts_count, outcomes_count,
  successful_wildcards_count, match_points, group_leader_points,
  badges_points, total_points, calculated_badges,
  ROW_NUMBER() OVER (
    ORDER BY total_points DESC, exacts_count DESC,
    (outcomes_count - exacts_count) DESC,
    successful_wildcards_count DESC, cedula ASC
  ) as rank
FROM user_calculated_points
WHERE COALESCE(is_admin, FALSE) = FALSE AND COALESCE(is_mock, FALSE) = FALSE;


-- =============================================================================
-- ✅ FIN DEL SCRIPT DE REFINAMIENTO
-- Verificaciones post-ejecución:
--   1. SELECT * FROM profiles LIMIT 5;  → Debe tener columnas phone, dob, parley_username, must_change_password
--   2. SELECT match_no, hidden FROM matches WHERE match_no BETWEEN 1 AND 25; → #1-#24 deben ser TRUE, #25 FALSE
--   3. SELECT key, value FROM app_config; → Debe incluir 'special_predictions_deadline'
--   4. SELECT * FROM leaderboard LIMIT 5; → Debe funcionar sin errores
-- =============================================================================
