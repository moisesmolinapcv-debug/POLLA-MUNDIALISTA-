-- =============================================================================
-- POLLA MUNDIALISTA — SUPABASE SETUP COMPLETO v2.0
-- Autor: Parley.la
-- Instrucciones: Ejecutar TODO este archivo de una sola vez en el SQL Editor
--                de un proyecto de Supabase NUEVO y VACÍO.
-- =============================================================================


-- =============================================================================
-- SECCIÓN 1: CREACIÓN DE TABLAS BASE
-- =============================================================================

-- 1.1 PROFILES: Perfiles de usuario
CREATE TABLE IF NOT EXISTS profiles (
  id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  cedula      TEXT UNIQUE NOT NULL,
  name        TEXT NOT NULL,
  phone       TEXT,
  email       TEXT,
  dob         TEXT,
  parley_username TEXT,
  is_admin    BOOLEAN DEFAULT FALSE,
  is_mock     BOOLEAN DEFAULT FALSE,
  badges      TEXT[] DEFAULT ARRAY[]::TEXT[],
  tutorial_seen BOOLEAN DEFAULT FALSE,
  created_at  TIMESTAMPTZ DEFAULT now()
);

-- 1.2 MATCHES: Partidos del Mundial
CREATE TABLE IF NOT EXISTS matches (
  match_no    INTEGER PRIMARY KEY,
  stage       TEXT NOT NULL,                         -- 'group' | 'round_of_32' | 'round_of_16' | 'quarter' | 'semi' | 'third' | 'final'
  group_letter TEXT,                                  -- 'A' ... 'L' (solo para fase de grupos)
  home_code   TEXT NOT NULL,
  away_code   TEXT NOT NULL,
  home_name   TEXT NOT NULL,
  away_name   TEXT NOT NULL,
  venue       TEXT,
  match_date  TIMESTAMPTZ NOT NULL,
  home_score  INTEGER DEFAULT NULL,
  away_score  INTEGER DEFAULT NULL,
  CONSTRAINT check_matches_scores CHECK ((home_score IS NULL) OR (home_score >= 0 AND home_score <= 99 AND away_score >= 0 AND away_score <= 99))
);

-- 1.3 PREDICTIONS: Pronósticos de partidos
CREATE TABLE IF NOT EXISTS predictions (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  match_no    INTEGER NOT NULL REFERENCES matches(match_no) ON DELETE CASCADE,
  home_score  INTEGER NOT NULL,
  away_score  INTEGER NOT NULL,
  wildcard    BOOLEAN DEFAULT FALSE,
  created_at  TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, match_no),
  CONSTRAINT check_predictions_scores CHECK (home_score >= 0 AND home_score <= 99 AND away_score >= 0 AND away_score <= 99)
);

-- 1.4 GROUP_LEADER_PREDICTIONS: Pronósticos de líderes de grupo
CREATE TABLE IF NOT EXISTS group_leader_predictions (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  group_letter TEXT NOT NULL,
  team_code    TEXT NOT NULL,
  created_at   TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, group_letter)
);

-- 1.5 APP_CONFIG: Configuración global de la app
CREATE TABLE IF NOT EXISTS app_config (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

-- Valores por defecto del config
INSERT INTO app_config (key, value)
VALUES
  ('tournament_finished', 'false'),
  ('group_standings_overrides', '{}')
ON CONFLICT (key) DO NOTHING;

-- 1.6 PUSH_SUBSCRIPTIONS: Suscripciones Web Push
CREATE TABLE IF NOT EXISTS push_subscriptions (
  cedula        TEXT PRIMARY KEY,
  subscription  JSONB NOT NULL,
  created_at    TIMESTAMPTZ DEFAULT now()
);

-- 1.7 LEAGUES: Ligas privadas
CREATE TABLE IF NOT EXISTS leagues (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name      TEXT NOT NULL,
  code      TEXT UNIQUE NOT NULL,
  owner_id  UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 1.8 LEAGUE_MEMBERS: Miembros de ligas privadas
CREATE TABLE IF NOT EXISTS league_members (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  league_id   UUID NOT NULL REFERENCES leagues(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  joined_at   TIMESTAMPTZ DEFAULT now(),
  UNIQUE(league_id, user_id)
);


-- =============================================================================
-- SECCIÓN 2: ROW LEVEL SECURITY (RLS)
-- =============================================================================

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE predictions ENABLE ROW LEVEL SECURITY;
ALTER TABLE group_leader_predictions ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE push_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE leagues ENABLE ROW LEVEL SECURITY;
ALTER TABLE league_members ENABLE ROW LEVEL SECURITY;

-- Limpiar políticas previas si existieran
DROP POLICY IF EXISTS profiles_select_policy ON profiles;
DROP POLICY IF EXISTS profiles_insert_policy ON profiles;
DROP POLICY IF EXISTS profiles_update_policy ON profiles;
DROP POLICY IF EXISTS profiles_delete_policy ON profiles;
DROP POLICY IF EXISTS select_predictions_policy ON predictions;
DROP POLICY IF EXISTS insert_predictions_policy ON predictions;
DROP POLICY IF EXISTS update_predictions_policy ON predictions;
DROP POLICY IF EXISTS delete_predictions_policy ON predictions;
DROP POLICY IF EXISTS select_group_leaders_policy ON group_leader_predictions;
DROP POLICY IF EXISTS insert_group_leaders_policy ON group_leader_predictions;
DROP POLICY IF EXISTS update_group_leaders_policy ON group_leader_predictions;
DROP POLICY IF EXISTS delete_group_leaders_policy ON group_leader_predictions;
DROP POLICY IF EXISTS matches_select_policy ON matches;
DROP POLICY IF EXISTS matches_update_policy ON matches;
DROP POLICY IF EXISTS app_config_select_policy ON app_config;
DROP POLICY IF EXISTS app_config_upsert_policy ON app_config;
DROP POLICY IF EXISTS push_sub_select_policy ON push_subscriptions;
DROP POLICY IF EXISTS push_sub_upsert_policy ON push_subscriptions;
DROP POLICY IF EXISTS push_sub_delete_policy ON push_subscriptions;
DROP POLICY IF EXISTS leagues_select_policy ON leagues;
DROP POLICY IF EXISTS leagues_insert_policy ON leagues;
DROP POLICY IF EXISTS leagues_delete_policy ON leagues;
DROP POLICY IF EXISTS league_members_select_policy ON league_members;
DROP POLICY IF EXISTS league_members_insert_policy ON league_members;
DROP POLICY IF EXISTS league_members_delete_policy ON league_members;

-- PROFILES
CREATE POLICY profiles_select_policy ON profiles FOR SELECT USING (TRUE);
CREATE POLICY profiles_insert_policy ON profiles FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY profiles_update_policy ON profiles FOR UPDATE USING (
  auth.uid() = id
  OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND COALESCE(is_admin, FALSE) = TRUE)
);
CREATE POLICY profiles_delete_policy ON profiles FOR DELETE USING (
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND COALESCE(is_admin, FALSE) = TRUE)
);

-- MATCHES: Todos pueden ver; solo admins pueden actualizar
CREATE POLICY matches_select_policy ON matches FOR SELECT USING (TRUE);
CREATE POLICY matches_update_policy ON matches FOR UPDATE USING (
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND COALESCE(is_admin, FALSE) = TRUE)
);

-- APP_CONFIG: Todos pueden leer; solo admins pueden escribir
CREATE POLICY app_config_select_policy ON app_config FOR SELECT USING (TRUE);
CREATE POLICY app_config_upsert_policy ON app_config FOR ALL USING (
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND COALESCE(is_admin, FALSE) = TRUE)
);

-- PREDICTIONS
CREATE POLICY select_predictions_policy ON predictions FOR SELECT USING (
  auth.uid() = user_id
  OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND COALESCE(is_admin, FALSE) = TRUE)
  OR EXISTS (
    SELECT 1 FROM matches
    WHERE matches.match_no = predictions.match_no
    AND (
      now() >= (matches.match_date - INTERVAL '10 minutes')
      OR (matches.home_score IS NOT NULL AND matches.away_score IS NOT NULL)
    )
  )
);
CREATE POLICY insert_predictions_policy ON predictions FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY update_predictions_policy ON predictions FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY delete_predictions_policy ON predictions FOR DELETE USING (auth.uid() = user_id);

-- GROUP_LEADER_PREDICTIONS
CREATE POLICY select_group_leaders_policy ON group_leader_predictions FOR SELECT USING (
  auth.uid() = user_id
  OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND COALESCE(is_admin, FALSE) = TRUE)
);
CREATE POLICY insert_group_leaders_policy ON group_leader_predictions FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY update_group_leaders_policy ON group_leader_predictions FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY delete_group_leaders_policy ON group_leader_predictions FOR DELETE USING (auth.uid() = user_id);

-- PUSH_SUBSCRIPTIONS
CREATE POLICY push_sub_select_policy ON push_subscriptions FOR SELECT USING (
  cedula = (SELECT cedula FROM profiles WHERE id = auth.uid())
  OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND COALESCE(is_admin, FALSE) = TRUE)
);
CREATE POLICY push_sub_upsert_policy ON push_subscriptions FOR ALL USING (
  cedula = (SELECT cedula FROM profiles WHERE id = auth.uid())
);
CREATE POLICY push_sub_delete_policy ON push_subscriptions FOR DELETE USING (
  cedula = (SELECT cedula FROM profiles WHERE id = auth.uid())
);

-- LEAGUES
CREATE POLICY leagues_select_policy ON leagues FOR SELECT USING (TRUE);
CREATE POLICY leagues_insert_policy ON leagues FOR INSERT WITH CHECK (auth.uid() = owner_id);
CREATE POLICY leagues_delete_policy ON leagues FOR DELETE USING (auth.uid() = owner_id);

-- LEAGUE_MEMBERS
CREATE POLICY league_members_select_policy ON league_members FOR SELECT USING (TRUE);
CREATE POLICY league_members_insert_policy ON league_members FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY league_members_delete_policy ON league_members FOR DELETE USING (
  auth.uid() = user_id
  OR EXISTS (
    SELECT 1 FROM leagues
    WHERE leagues.id = league_members.league_id AND leagues.owner_id = auth.uid()
  )
);


-- =============================================================================
-- SECCIÓN 3: TRIGGERS DE SEGURIDAD TEMPORAL (LOCKOUT CLOCK)
-- =============================================================================

-- 3A. Bloqueo de predicciones de partidos
CREATE OR REPLACE FUNCTION check_prediction_lockout()
RETURNS TRIGGER AS $$
DECLARE
  v_kickoff     TIMESTAMPTZ;
  v_home_score  INT;
  v_away_score  INT;
  v_tournament_finished TEXT;
  v_is_admin    BOOLEAN;
BEGIN
  SELECT COALESCE(is_admin, FALSE) INTO v_is_admin
  FROM profiles WHERE id = auth.uid();
  IF v_is_admin THEN RETURN NEW; END IF;

  -- NEW: Restrict predictions to match range #41 to #72 for non-admin users
  IF NEW.match_no < 41 OR NEW.match_no > 72 THEN
    RAISE EXCEPTION 'Este partido no está disponible para pronósticos de usuarios.';
  END IF;

  SELECT value INTO v_tournament_finished
  FROM app_config WHERE key = 'tournament_finished';
  IF v_tournament_finished = 'true' THEN
    RAISE EXCEPTION 'El torneo ha concluido. No se permiten más predicciones.';
  END IF;

  SELECT match_date, home_score, away_score
  INTO v_kickoff, v_home_score, v_away_score
  FROM matches WHERE match_no = NEW.match_no;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'El partido especificado no existe.';
  END IF;

  IF v_home_score IS NOT NULL AND v_away_score IS NOT NULL THEN
    RAISE EXCEPTION 'El partido ya tiene marcador. No se puede pronosticar.';
  END IF;

  IF now() >= (v_kickoff - INTERVAL '10 minutes') THEN
    RAISE EXCEPTION 'Tiempo límite excedido. Los pronósticos se cierran 10 minutos antes del partido.';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_check_prediction_lockout ON predictions;
CREATE TRIGGER trg_check_prediction_lockout
BEFORE INSERT OR UPDATE ON predictions
FOR EACH ROW EXECUTE FUNCTION check_prediction_lockout();

-- 3B. Bloqueo de pronósticos de líderes de grupo
CREATE OR REPLACE FUNCTION check_special_predictions_lockout()
RETURNS TRIGGER AS $$
DECLARE v_is_admin BOOLEAN;
BEGIN
  SELECT COALESCE(is_admin, FALSE) INTO v_is_admin
  FROM profiles WHERE id = auth.uid();
  IF v_is_admin THEN RETURN NEW; END IF;

  IF now() >= '2026-06-23 16:00:00+00'::TIMESTAMPTZ THEN
    RAISE EXCEPTION 'El período para seleccionar líderes de grupo ha expirado.';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_check_special_predictions_lockout ON group_leader_predictions;
CREATE TRIGGER trg_check_special_predictions_lockout
BEFORE INSERT OR UPDATE ON group_leader_predictions
FOR EACH ROW EXECUTE FUNCTION check_special_predictions_lockout();

-- 3C. Auto-crear perfil al registrarse un usuario en auth
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO profiles (id, cedula, name, email)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'cedula', NEW.email),
    COALESCE(NEW.raw_user_meta_data->>'name', 'Usuario'),
    NEW.email
  ) ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- 3D. Bloqueo de modificación de roles administrativos desde el cliente
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

DROP TRIGGER IF EXISTS trg_protect_profile_roles ON profiles;
CREATE TRIGGER trg_protect_profile_roles
  BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION protect_profile_roles();


-- =============================================================================
-- SECCIÓN 4: VISTAS DEL LEADERBOARD (CÁLCULO EN BACKEND)
-- =============================================================================

DROP VIEW IF EXISTS leaderboard CASCADE;
DROP VIEW IF EXISTS user_calculated_points CASCADE;
DROP VIEW IF EXISTS real_group_leaders CASCADE;
DROP VIEW IF EXISTS team_standings CASCADE;
DROP VIEW IF EXISTS group_status CASCADE;

-- 4.1 Estado de grupos (¿todos los partidos finalizados?)
CREATE OR REPLACE VIEW group_status AS
SELECT
  group_letter,
  (COUNT(*) FILTER (WHERE home_score IS NULL OR away_score IS NULL) = 0) AS all_finished
FROM matches
WHERE stage = 'group'
GROUP BY group_letter;

-- 4.2 Tabla de posiciones por equipo (soporta overrides de app_config y fallback de team_code)
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

-- 4.3 Líderes reales de cada grupo
CREATE OR REPLACE VIEW real_group_leaders AS
SELECT group_letter, team_code FROM team_standings WHERE rank = 1;

-- 4.4 Puntos calculados por usuario
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
  JOIN matches m ON p.match_no = m.match_no
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
    (CASE WHEN COALESCE(mp.outcomes_count, 0) >= 12 THEN 10 ELSE 0 END) +
    (CASE WHEN COALESCE(mp.predictions_count, 0) >= 25 THEN 5 ELSE 0 END) +
    (CASE WHEN COALESCE(gp.correct_leaders_count, 0) >= 6 THEN 15 ELSE 0 END) +
    (CASE WHEN COALESCE(prof.badges, ARRAY[]::text[]) @> ARRAY['HAT-TRICK VIP']::text[] THEN 20 ELSE 0 END)
  ) AS badges_points,
  (
    COALESCE(mp.match_points, 0) +
    COALESCE(gp.group_leader_points, 0) +
    (CASE WHEN COALESCE(mp.exacts_count, 0) >= 3 THEN 15 ELSE 0 END) +
    (CASE WHEN COALESCE(mp.outcomes_count, 0) >= 12 THEN 10 ELSE 0 END) +
    (CASE WHEN COALESCE(mp.predictions_count, 0) >= 25 THEN 5 ELSE 0 END) +
    (CASE WHEN COALESCE(gp.correct_leaders_count, 0) >= 6 THEN 15 ELSE 0 END) +
    (CASE WHEN COALESCE(prof.badges, ARRAY[]::text[]) @> ARRAY['HAT-TRICK VIP']::text[] THEN 20 ELSE 0 END)
  ) AS total_points,
  ARRAY_REMOVE(ARRAY[
    CASE WHEN COALESCE(mp.exacts_count, 0) >= 3 THEN 'Ojo Clínico' END,
    CASE WHEN COALESCE(mp.outcomes_count, 0) >= 12 THEN 'Ganador Frecuente' END,
    CASE WHEN COALESCE(mp.predictions_count, 0) >= 25 THEN 'Pronosticador Activo' END,
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
-- SECCIÓN 5: DATOS DE LOS PARTIDOS — COPA MUNDIAL FIFA 2026
-- Todas las fechas en UTC (Venezuela = UTC-4, así que 15:00 UTC = 11:00 AM VET)
-- =============================================================================

INSERT INTO matches (match_no, stage, group_letter, home_code, away_code, home_name, away_name, venue, match_date) VALUES
-- JORNADA 1
(1,  'group', 'A', 'A1', 'A2', 'México',           'Sudáfrica',         'Mexico City',          '2026-06-11 19:00:00+00'),
(2,  'group', 'A', 'A3', 'A4', 'Rep. de Corea',    'Rép. Checa',        'Guadalajara',          '2026-06-12 02:00:00+00'),
(3,  'group', 'B', 'B1', 'B2', 'Canadá',           'Bosnia-Herzegovina','Toronto',              '2026-06-12 19:00:00+00'),
(4,  'group', 'D', 'D1', 'D2', 'EE.UU.',           'Paraguay',          'Los Angeles',          '2026-06-13 01:00:00+00'),
(5,  'group', 'C', 'C3', 'C4', 'Haití',            'Escocia',           'Boston',               '2026-06-14 01:00:00+00'),
(6,  'group', 'D', 'D3', 'D4', 'Australia',        'Turquía',           'Vancouver',            '2026-06-14 04:00:00+00'),
(7,  'group', 'C', 'C1', 'C2', 'Brasil',           'Marruecos',         'New York/New Jersey',  '2026-06-13 22:00:00+00'),
(8,  'group', 'B', 'B3', 'B4', 'Catar',            'Suiza',             'San Francisco',        '2026-06-13 19:00:00+00'),
(9,  'group', 'E', 'E3', 'E4', 'Costa de Marfil',  'Ecuador',           'Philadelphia',         '2026-06-14 23:00:00+00'),
(10, 'group', 'E', 'E1', 'E2', 'Alemania',         'Curazao',           'Houston',              '2026-06-14 17:00:00+00'),
(11, 'group', 'F', 'F1', 'F2', 'Países Bajos',     'Japón',             'Dallas',               '2026-06-14 20:00:00+00'),
(12, 'group', 'F', 'F3', 'F4', 'Suecia',           'Túnez',             'Monterrey',            '2026-06-15 02:00:00+00'),
(13, 'group', 'H', 'H3', 'H4', 'Arabia Saudita',   'Uruguay',           'Miami',                '2026-06-15 22:00:00+00'),
(14, 'group', 'H', 'H1', 'H2', 'España',           'Cabo Verde',        'Atlanta',              '2026-06-15 16:00:00+00'),
(15, 'group', 'G', 'G3', 'G4', 'Irán',             'Nueva Zelanda',     'Los Angeles',          '2026-06-16 01:00:00+00'),
(16, 'group', 'G', 'G1', 'G2', 'Bélgica',          'Egipto',            'Seattle',              '2026-06-15 19:00:00+00'),
(17, 'group', 'I', 'I1', 'I2', 'Francia',          'Senegal',           'New York/New Jersey',  '2026-06-16 19:00:00+00'),
(18, 'group', 'I', 'I3', 'I4', 'Irak',             'Noruega',           'Boston',               '2026-06-16 22:00:00+00'),
(19, 'group', 'J', 'J1', 'J2', 'Argentina',        'Argelia',           'Kansas City',          '2026-06-17 01:00:00+00'),
(20, 'group', 'J', 'J3', 'J4', 'Austria',          'Jordania',          'San Francisco',        '2026-06-17 04:00:00+00'),
(21, 'group', 'L', 'L3', 'L4', 'Ghana',            'Panamá',            'Toronto',              '2026-06-17 23:00:00+00'),
(22, 'group', 'L', 'L1', 'L2', 'Inglaterra',       'Croacia',           'Dallas',               '2026-06-17 20:00:00+00'),
(23, 'group', 'K', 'K1', 'K2', 'Portugal',         'RD Congo',          'Houston',              '2026-06-17 17:00:00+00'),
(24, 'group', 'K', 'K3', 'K4', 'Uzbekistán',       'Colombia',          'Mexico City',          '2026-06-18 02:00:00+00'),
-- JORNADA 2
(25, 'group', 'A', 'A4', 'A2', 'Rép. Checa',       'Sudáfrica',         'Atlanta',              '2026-06-18 16:00:00+00'),
(26, 'group', 'B', 'B4', 'B2', 'Suiza',            'Bosnia-Herzegovina','Los Angeles',          '2026-06-18 19:00:00+00'),
(27, 'group', 'B', 'B1', 'B3', 'Canadá',           'Catar',             'Vancouver',            '2026-06-18 22:00:00+00'),
(28, 'group', 'A', 'A1', 'A3', 'México',           'Rep. de Corea',     'Guadalajara',          '2026-06-19 01:00:00+00'),
(29, 'group', 'C', 'C1', 'C3', 'Brasil',           'Haití',             'Philadelphia',         '2026-06-20 00:30:00+00'),
(30, 'group', 'C', 'C4', 'C2', 'Escocia',          'Marruecos',         'Boston',               '2026-06-19 22:00:00+00'),
(31, 'group', 'D', 'D4', 'D2', 'Turquía',          'Paraguay',          'San Francisco',        '2026-06-20 03:00:00+00'),
(32, 'group', 'D', 'D1', 'D3', 'EE.UU.',           'Australia',         'Seattle',              '2026-06-19 19:00:00+00'),
(33, 'group', 'E', 'E1', 'E3', 'Alemania',         'Costa de Marfil',   'Toronto',              '2026-06-20 20:00:00+00'),
(34, 'group', 'E', 'E4', 'E2', 'Ecuador',          'Curazao',           'Kansas City',          '2026-06-21 00:00:00+00'),
(35, 'group', 'F', 'F1', 'F3', 'Países Bajos',     'Suecia',            'Houston',              '2026-06-20 17:00:00+00'),
(36, 'group', 'F', 'F4', 'F2', 'Túnez',            'Japón',             'Monterrey',            '2026-06-21 04:00:00+00'),
(37, 'group', 'H', 'H4', 'H2', 'Uruguay',          'Cabo Verde',        'Miami',                '2026-06-21 22:00:00+00'),
(38, 'group', 'H', 'H1', 'H3', 'España',           'Arabia Saudita',    'Atlanta',              '2026-06-21 16:00:00+00'),
(39, 'group', 'G', 'G1', 'G3', 'Bélgica',          'Irán',              'Los Angeles',          '2026-06-21 19:00:00+00'),
(40, 'group', 'G', 'G4', 'G2', 'Nueva Zelanda',    'Egipto',            'Vancouver',            '2026-06-22 01:00:00+00'),
(41, 'group', 'I', 'I4', 'I2', 'Noruega',          'Senegal',           'New York/New Jersey',  '2026-06-23 00:00:00+00'),
(42, 'group', 'I', 'I1', 'I3', 'Francia',          'Irak',              'Philadelphia',         '2026-06-22 21:00:00+00'),
(43, 'group', 'J', 'J1', 'J3', 'Argentina',        'Austria',           'Dallas',               '2026-06-22 17:00:00+00'),
(44, 'group', 'J', 'J4', 'J2', 'Jordania',         'Argelia',           'San Francisco',        '2026-06-23 03:00:00+00'),
(45, 'group', 'L', 'L1', 'L3', 'Inglaterra',       'Ghana',             'Boston',               '2026-06-23 20:00:00+00'),
(46, 'group', 'L', 'L4', 'L2', 'Panamá',           'Croacia',           'Toronto',              '2026-06-23 23:00:00+00'),
(47, 'group', 'K', 'K1', 'K3', 'Portugal',         'Uzbekistán',        'Houston',              '2026-06-23 17:00:00+00'),
(48, 'group', 'K', 'K4', 'K2', 'Colombia',         'RD Congo',          'Guadalajara',          '2026-06-24 02:00:00+00'),
-- JORNADA 3
(49, 'group', 'C', 'C4', 'C1', 'Escocia',          'Brasil',            'Miami',                '2026-06-24 22:00:00+00'),
(50, 'group', 'C', 'C2', 'C3', 'Marruecos',        'Haití',             'Atlanta',              '2026-06-24 22:00:00+00'),
(51, 'group', 'B', 'B4', 'B1', 'Suiza',            'Canadá',            'Vancouver',            '2026-06-24 19:00:00+00'),
(52, 'group', 'B', 'B2', 'B3', 'Bosnia-Herzegovina','Catar',            'Seattle',              '2026-06-24 19:00:00+00'),
(53, 'group', 'A', 'A4', 'A1', 'Rép. Checa',       'México',            'Mexico City',          '2026-06-25 01:00:00+00'),
(54, 'group', 'A', 'A2', 'A3', 'Sudáfrica',        'Rep. de Corea',     'Monterrey',            '2026-06-25 01:00:00+00'),
(55, 'group', 'E', 'E2', 'E3', 'Curazao',          'Costa de Marfil',   'Philadelphia',         '2026-06-25 20:00:00+00'),
(56, 'group', 'E', 'E4', 'E1', 'Ecuador',          'Alemania',          'New York/New Jersey',  '2026-06-25 20:00:00+00'),
(57, 'group', 'F', 'F2', 'F3', 'Japón',            'Suecia',            'Dallas',               '2026-06-25 23:00:00+00'),
(58, 'group', 'F', 'F4', 'F1', 'Túnez',            'Países Bajos',      'Kansas City',          '2026-06-25 23:00:00+00'),
(59, 'group', 'D', 'D4', 'D1', 'Turquía',          'EE.UU.',            'Los Angeles',          '2026-06-26 02:00:00+00'),
(60, 'group', 'D', 'D2', 'D3', 'Paraguay',         'Australia',         'San Francisco',        '2026-06-26 02:00:00+00'),
(61, 'group', 'I', 'I4', 'I1', 'Noruega',          'Francia',           'Boston',               '2026-06-26 19:00:00+00'),
(62, 'group', 'I', 'I2', 'I3', 'Senegal',          'Irak',              'Toronto',              '2026-06-26 19:00:00+00'),
(63, 'group', 'G', 'G2', 'G3', 'Egipto',           'Irán',              'Seattle',              '2026-06-27 03:00:00+00'),
(64, 'group', 'G', 'G4', 'G1', 'Nueva Zelanda',    'Bélgica',           'Vancouver',            '2026-06-27 03:00:00+00'),
(65, 'group', 'H', 'H2', 'H3', 'Cabo Verde',       'Arabia Saudita',    'Houston',              '2026-06-27 00:00:00+00'),
(66, 'group', 'H', 'H4', 'H1', 'Uruguay',          'España',            'Guadalajara',          '2026-06-27 00:00:00+00'),
(67, 'group', 'L', 'L4', 'L1', 'Panamá',           'Inglaterra',        'New York/New Jersey',  '2026-06-27 21:00:00+00'),
(68, 'group', 'L', 'L2', 'L3', 'Croacia',          'Ghana',             'Philadelphia',         '2026-06-27 21:00:00+00'),
(69, 'group', 'J', 'J2', 'J3', 'Argelia',          'Austria',           'Kansas City',          '2026-06-28 02:00:00+00'),
(70, 'group', 'J', 'J4', 'J1', 'Jordania',         'Argentina',         'Dallas',               '2026-06-28 02:00:00+00'),
(71, 'group', 'K', 'K2', 'K3', 'RD Congo',         'Uzbekistán',        'Houston',              '2026-06-28 21:00:00+00'),
(72, 'group', 'K', 'K4', 'K1', 'Colombia',         'Portugal',          'Guadalajara',          '2026-06-28 21:00:00+00'),
-- RONDA DE 32 (placeholders — se actualizan según resultados)
(73,  'round_of_32', NULL, '1A', '2B', 'TBD', 'TBD', 'TBD', '2026-06-29 19:00:00+00'),
(74,  'round_of_32', NULL, '1B', '2A', 'TBD', 'TBD', 'TBD', '2026-06-29 23:00:00+00'),
(75,  'round_of_32', NULL, '1C', '2D', 'TBD', 'TBD', 'TBD', '2026-06-30 19:00:00+00'),
(76,  'round_of_32', NULL, '1D', '2C', 'TBD', 'TBD', 'TBD', '2026-06-30 23:00:00+00'),
(77,  'round_of_32', NULL, '1E', '2F', 'TBD', 'TBD', 'TBD', '2026-07-01 19:00:00+00'),
(78,  'round_of_32', NULL, '1F', '2E', 'TBD', 'TBD', 'TBD', '2026-07-01 23:00:00+00'),
(79,  'round_of_32', NULL, '1G', '2H', 'TBD', 'TBD', 'TBD', '2026-07-02 19:00:00+00'),
(80,  'round_of_32', NULL, '1H', '2G', 'TBD', 'TBD', 'TBD', '2026-07-02 23:00:00+00'),
(81,  'round_of_32', NULL, '1I', '2J', 'TBD', 'TBD', 'TBD', '2026-07-03 19:00:00+00'),
(82,  'round_of_32', NULL, '1J', '2I', 'TBD', 'TBD', 'TBD', '2026-07-03 23:00:00+00'),
(83,  'round_of_32', NULL, '1K', '2L', 'TBD', 'TBD', 'TBD', '2026-07-04 19:00:00+00'),
(84,  'round_of_32', NULL, '1L', '2K', 'TBD', 'TBD', 'TBD', '2026-07-04 23:00:00+00'),
-- OCTAVOS DE FINAL
(85,  'round_of_16', NULL, 'TBD', 'TBD', 'TBD', 'TBD', 'TBD', '2026-07-06 19:00:00+00'),
(86,  'round_of_16', NULL, 'TBD', 'TBD', 'TBD', 'TBD', 'TBD', '2026-07-06 23:00:00+00'),
(87,  'round_of_16', NULL, 'TBD', 'TBD', 'TBD', 'TBD', 'TBD', '2026-07-07 19:00:00+00'),
(88,  'round_of_16', NULL, 'TBD', 'TBD', 'TBD', 'TBD', 'TBD', '2026-07-07 23:00:00+00'),
(89,  'round_of_16', NULL, 'TBD', 'TBD', 'TBD', 'TBD', 'TBD', '2026-07-08 19:00:00+00'),
(90,  'round_of_16', NULL, 'TBD', 'TBD', 'TBD', 'TBD', 'TBD', '2026-07-08 23:00:00+00'),
(91,  'round_of_16', NULL, 'TBD', 'TBD', 'TBD', 'TBD', 'TBD', '2026-07-09 19:00:00+00'),
(92,  'round_of_16', NULL, 'TBD', 'TBD', 'TBD', 'TBD', 'TBD', '2026-07-09 23:00:00+00'),
-- CUARTOS DE FINAL
(93,  'quarter', NULL, 'TBD', 'TBD', 'TBD', 'TBD', 'TBD', '2026-07-11 19:00:00+00'),
(94,  'quarter', NULL, 'TBD', 'TBD', 'TBD', 'TBD', 'TBD', '2026-07-11 23:00:00+00'),
(95,  'quarter', NULL, 'TBD', 'TBD', 'TBD', 'TBD', 'TBD', '2026-07-12 19:00:00+00'),
(96,  'quarter', NULL, 'TBD', 'TBD', 'TBD', 'TBD', 'TBD', '2026-07-12 23:00:00+00'),
-- SEMIFINALES
(97,  'semi',    NULL, 'TBD', 'TBD', 'TBD', 'TBD', 'TBD', '2026-07-14 23:00:00+00'),
(98,  'semi',    NULL, 'TBD', 'TBD', 'TBD', 'TBD', 'TBD', '2026-07-15 23:00:00+00'),
-- TERCER PUESTO
(99,  'third',   NULL, 'TBD', 'TBD', 'TBD', 'TBD', 'TBD', '2026-07-18 19:00:00+00'),
-- FINAL
(100, 'final',   NULL, 'TBD', 'TBD', 'TBD', 'TBD', 'TBD', '2026-07-19 20:00:00+00')
ON CONFLICT (match_no) DO NOTHING;


-- =============================================================================
-- SECCIÓN 6: INSTRUCCIONES PARA CREAR EL USUARIO ADMINISTRADOR
-- =============================================================================
-- IMPORTANTE: Después de ejecutar este script, debes:
-- 1. Ir a Authentication → Users → "Invite User"
-- 2. Crear el usuario con el correo del admin (ej: admin@parley.la)
-- 3. Luego ejecutar el siguiente UPDATE reemplazando el UUID con el del nuevo usuario:
--
-- UPDATE profiles
-- SET is_admin = TRUE, cedula = 'V-12345678', name = 'Administrador Parley'
-- WHERE id = 'UUID_DEL_USUARIO_ADMIN_AQUI';
--
-- =============================================================================
-- ✅ FIN DEL SCRIPT. Si no hubo errores, el proyecto está listo.
-- =============================================================================
