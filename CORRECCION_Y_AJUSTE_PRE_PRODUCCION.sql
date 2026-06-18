-- =============================================================================
-- POLLA MUNDIALISTA — CORRECCIÓN Y AJUSTE DE PRE-PRODUCCIÓN
-- Ejecutar en el SQL Editor de Supabase (una sola vez)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. RESTRICCIONES DE UNICIDAD DE DATOS (SEGURIDAD Y EVITAR CLONES)
-- -----------------------------------------------------------------------------

-- Agregar restricciones UNIQUE a email, phone y parley_username en profiles.
-- Nota: En Postgres, múltiples valores NULL no violan la restricción UNIQUE, 
-- por lo que los registros existentes sin teléfono o usuario no darán error.
ALTER TABLE profiles ADD CONSTRAINT profiles_email_key UNIQUE (email);
ALTER TABLE profiles ADD CONSTRAINT profiles_phone_key UNIQUE (phone);
ALTER TABLE profiles ADD CONSTRAINT profiles_parley_username_key UNIQUE (parley_username);


-- -----------------------------------------------------------------------------
-- 2. AJUSTE DE RANGO DE PARTIDOS OCULTOS (#1 AL #32)
-- -----------------------------------------------------------------------------

-- Marcar partidos del #1 al #32 como ocultos
UPDATE matches SET hidden = TRUE WHERE match_no BETWEEN 1 AND 32;

-- Asegurar que los partidos a partir del #33 estén visibles y predictibles
UPDATE matches SET hidden = FALSE WHERE match_no >= 33;


-- -----------------------------------------------------------------------------
-- 3. REESTRUCTURACIÓN DE LA VISTA DE PUNTOS (CÁLCULO SOBRE TODOS LOS JUEGOS)
-- -----------------------------------------------------------------------------

-- Limpiar vistas dependientes para recrear
DROP VIEW IF EXISTS leaderboard CASCADE;
DROP VIEW IF EXISTS user_calculated_points CASCADE;

-- Recrear vista con el cálculo homogeneo (sin excluir partidos por ser hidden)
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
  JOIN matches m ON p.match_no = m.match_no -- Se calcula sobre TODOS los partidos de predictions
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

-- Recrear vista pública del Leaderboard (excluye admins y mocks de la competencia)
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


-- -----------------------------------------------------------------------------
-- 4. TRIGGER DE NUEVO USUARIO SEGURO Y DEFINIDO (CON PREFIJO DE ESQUEMA PUBLIC)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  -- Usamos public.profiles con prefijo explícito de esquema para evitar fallos de resolución (search_path)
  INSERT INTO public.profiles (id, cedula, name, email, phone, dob, parley_username)
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

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION handle_new_user();
