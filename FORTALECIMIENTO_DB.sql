-- =============================================================================
-- POLLA MUNDIALISTA — FORTALECIMIENTO DE SEGURIDAD (BASE DE DATOS)
-- Descripción:
--   1. Añade CHECK constraints en predictions y matches para asegurar marcadores entre 0 y 99.
--   2. Bloquea de forma absoluta la actualización de roles is_admin e is_mock
--      desde la API del cliente (roles authenticated/anon), permitiendo cambios
--      únicamente a través del panel de Supabase (postgres/service_role).
-- Instrucciones: Ejecutar todo este archivo en el SQL Editor de Supabase.
-- =============================================================================

-- 1. Restricción de rango de marcadores en predictions (0 a 99 goles)
ALTER TABLE public.predictions DROP CONSTRAINT IF EXISTS check_predictions_scores;
ALTER TABLE public.predictions ADD CONSTRAINT check_predictions_scores 
  CHECK (home_score >= 0 AND home_score <= 99 AND away_score >= 0 AND away_score <= 99);

-- 2. Restricción de rango de marcadores en matches (0 a 99 goles)
ALTER TABLE public.matches DROP CONSTRAINT IF EXISTS check_matches_scores;
ALTER TABLE public.matches ADD CONSTRAINT check_matches_scores 
  CHECK ((home_score IS NULL) OR (home_score >= 0 AND home_score <= 99 AND away_score >= 0 AND away_score <= 99));

-- 3. Trigger para bloquear por completo la modificación de roles administrativos desde el cliente
CREATE OR REPLACE FUNCTION public.protect_profile_roles()
RETURNS TRIGGER AS $$
BEGIN
  -- Si intentan cambiar is_admin o is_mock a través de la API del cliente (authenticated/anon)
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
  FOR EACH ROW EXECUTE FUNCTION public.protect_profile_roles();
