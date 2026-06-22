-- =============================================================================
-- POLLA MUNDIALISTA — ACTUALIZACIONES FASE FINAL
-- Descripción:
--   1. Restringir pronósticos de usuarios al rango de partidos #41 al #72.
--   2. Modificar el deadline de líderes de grupo (Especiales) al 23/06/2026 12:00 PM VET (16:00 UTC).
--   3. Ajustar la insignia 'Ganador Frecuente' a un mínimo de 12 aciertos simples.
--   4. Reiniciar puntajes (Opción 2A): eliminar pronósticos de partidos #1 al #40.
-- Instrucciones: Ejecutar todo este archivo en el SQL Editor de Supabase.
-- =============================================================================

-- 1. Actualizar el trigger de bloqueo de pronósticos para restringir partidos #41 al #72
CREATE OR REPLACE FUNCTION check_prediction_lockout()
RETURNS TRIGGER AS $$
DECLARE
    v_kickoff TIMESTAMPTZ;
    v_home_score INT;
    v_away_score INT;
    v_tournament_finished TEXT;
    v_is_admin BOOLEAN;
BEGIN
    -- A. El administrador se salta todas las restricciones
    SELECT COALESCE(is_admin, FALSE) INTO v_is_admin
    FROM public.profiles
    WHERE id = auth.uid();
    
    IF v_is_admin THEN
        RETURN NEW;
    END IF;

    -- B. Restringir pronósticos únicamente al rango de partidos #41 al #72
    IF NEW.match_no < 41 OR NEW.match_no > 72 THEN
        RAISE EXCEPTION 'Este partido no está disponible para pronósticos de usuarios regulares (Rango permitido: #41 al #72).';
    END IF;

    -- C. Validar si el torneo ya terminó
    SELECT value INTO v_tournament_finished
    FROM public.app_config
    WHERE key = 'tournament_finished';
    
    IF v_tournament_finished = 'true' THEN
        RAISE EXCEPTION 'El torneo ha concluido. No se permiten más predicciones.';
    END IF;

    -- D. Obtener los detalles del partido
    SELECT match_date, home_score, away_score
    INTO v_kickoff, v_home_score, v_away_score
    FROM public.matches
    WHERE match_no = NEW.match_no;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El partido especificado no existe.';
    END IF;

    -- E. Bloquear si ya tiene un resultado registrado
    IF v_home_score IS NOT NULL AND v_away_score IS NOT NULL THEN
        RAISE EXCEPTION 'El partido ya tiene un marcador registrado. No se puede pronosticar.';
    END IF;

    -- F. Bloqueo de 10 minutos antes del kickoff
    IF now() >= (v_kickoff - INTERVAL '10 minutes') THEN
        RAISE EXCEPTION 'Límite de tiempo excedido. Los pronósticos se cierran 10 minutos antes del partido.';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 2. Actualizar el deadline de líderes de grupo (Especiales) al 23/06/2026 12:00 PM VET (16:00 UTC)
CREATE OR REPLACE FUNCTION check_special_predictions_lockout()
RETURNS TRIGGER AS $$
DECLARE
  v_is_admin BOOLEAN;
  v_deadline TIMESTAMPTZ := '2026-06-23 16:00:00+00'; -- 12:00 PM VET en UTC
BEGIN
  -- A. El administrador se salta todas las restricciones
  SELECT COALESCE(is_admin, FALSE) INTO v_is_admin
  FROM public.profiles WHERE id = auth.uid();
  IF v_is_admin THEN RETURN NEW; END IF;

  -- B. Bloqueo estricto del deadline oficial
  IF now() >= v_deadline THEN
    RAISE EXCEPTION 'El período para seleccionar líderes de grupo ha expirado.';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 3. Actualizar la vista de posiciones y de puntuaciones para ajustar 'Ganador Frecuente' a >= 12 aciertos y soportar group_standings_overrides
DROP VIEW IF EXISTS public.leaderboard CASCADE;
DROP VIEW IF EXISTS public.user_calculated_points CASCADE;
DROP VIEW IF EXISTS public.real_group_leaders CASCADE;
DROP VIEW IF EXISTS public.team_standings CASCADE;

CREATE OR REPLACE VIEW public.team_standings AS
WITH team_stats AS (
  SELECT m.group_letter, m.home_code AS team_code,
    COUNT(m.match_no) FILTER (WHERE m.home_score IS NOT NULL AND m.away_score IS NOT NULL) AS played,
    COUNT(m.match_no) FILTER (WHERE m.home_score > m.away_score) AS wins,
    COUNT(m.match_no) FILTER (WHERE m.home_score = m.away_score AND m.home_score IS NOT NULL) AS draws,
    COUNT(m.match_no) FILTER (WHERE m.home_score < m.away_score) AS losses,
    COALESCE(SUM(m.home_score), 0) AS gf, COALESCE(SUM(m.away_score), 0) AS ga
  FROM public.matches m WHERE m.stage = 'group' GROUP BY m.group_letter, m.home_code
  UNION ALL
  SELECT m.group_letter, m.away_code AS team_code,
    COUNT(m.match_no) FILTER (WHERE m.home_score IS NOT NULL AND m.away_score IS NOT NULL) AS played,
    COUNT(m.match_no) FILTER (WHERE m.home_score < m.away_score) AS wins,
    COUNT(m.match_no) FILTER (WHERE m.home_score = m.away_score AND m.home_score IS NOT NULL) AS draws,
    COUNT(m.match_no) FILTER (WHERE m.home_score > m.away_score) AS losses,
    COALESCE(SUM(m.away_score), 0) AS gf, COALESCE(SUM(m.home_score), 0) AS ga
  FROM public.matches m WHERE m.stage = 'group' GROUP BY m.group_letter, m.away_code
),
agg AS (
  SELECT group_letter, team_code,
    SUM(played) as played, SUM(wins) as wins, SUM(draws) as draws, SUM(losses) as losses,
    SUM(gf) as gf, SUM(ga) as ga, (SUM(gf)-SUM(ga)) as gd, (SUM(wins)*3+SUM(draws)) as pts
  FROM team_stats GROUP BY group_letter, team_code
),
overrides AS (
  SELECT COALESCE(
    (SELECT value::jsonb FROM public.app_config WHERE key = 'group_standings_overrides'),
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
  FROM agg a
)
SELECT group_letter, team_code,
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

CREATE OR REPLACE VIEW public.real_group_leaders AS
SELECT group_letter, team_code FROM public.team_standings WHERE rank = 1;

CREATE OR REPLACE VIEW public.user_calculated_points AS
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
  FROM public.predictions p
  JOIN public.matches m ON p.match_no = m.match_no
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
  FROM public.group_leader_predictions glp
  JOIN public.real_group_leaders rgl ON glp.group_letter = rgl.group_letter
  JOIN public.group_status gs ON glp.group_letter = gs.group_letter
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
  
  -- Insignias con el nuevo umbral (>= 12 aciertos simples para Ganador Frecuente)
  (
    (CASE WHEN COALESCE(mp.exacts_count, 0) >= 3 THEN 15 ELSE 0 END) +
    (CASE WHEN COALESCE(mp.outcomes_count, 0) >= 12 THEN 10 ELSE 0 END) +
    (CASE WHEN COALESCE(mp.predictions_count, 0) >= 25 THEN 5 ELSE 0 END) +
    (CASE WHEN COALESCE(gp.correct_leaders_count, 0) >= 6 THEN 15 ELSE 0 END) +
    (CASE WHEN COALESCE(prof.badges, ARRAY[]::text[]) @> ARRAY['HAT-TRICK VIP']::text[] THEN 20 ELSE 0 END)
  ) AS badges_points,
  
  -- Puntos Totales actualizados
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
  
  -- Array de insignias recalculado
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
FROM public.profiles prof
LEFT JOIN match_preds mp ON prof.id = mp.user_id
LEFT JOIN group_preds gp ON prof.id = gp.user_id;


-- Recrear la vista dependiente 'leaderboard'
CREATE OR REPLACE VIEW public.leaderboard AS
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
FROM public.user_calculated_points
WHERE COALESCE(is_admin, FALSE) = FALSE AND COALESCE(is_mock, FALSE) = FALSE;


-- 4. Reiniciar Puntuaciones (Opción 2A): eliminar pronósticos de partidos #1 al #40
DELETE FROM public.predictions WHERE match_no < 41;
