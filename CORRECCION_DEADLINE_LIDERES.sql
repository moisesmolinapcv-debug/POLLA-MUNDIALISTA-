-- =============================================================================
-- PARCHE: HARDCODEO DE DEADLINE Y BLINDAJE DE SEGURIDAD LÍDERES DE GRUPO
-- =============================================================================

-- Actualizar la función trigger para usar el deadline oficial y esquema público
CREATE OR REPLACE FUNCTION check_special_predictions_lockout()
RETURNS TRIGGER AS $$
DECLARE
  v_is_admin BOOLEAN;
  v_deadline TIMESTAMPTZ := '2026-06-22 15:00:00+00'; -- 11:00 AM VET en UTC
BEGIN
  -- 1. Administrador siempre puede editar/guardar
  SELECT COALESCE(is_admin, FALSE) INTO v_is_admin
  FROM public.profiles WHERE id = auth.uid();
  IF v_is_admin THEN RETURN NEW; END IF;

  -- 2. Bloqueo estricto del deadline oficial
  IF now() >= v_deadline THEN
    RAISE EXCEPTION 'El período para seleccionar líderes de grupo ha expirado.';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recrear el trigger para garantizar que se apliquen las modificaciones
DROP TRIGGER IF EXISTS trg_check_special_predictions_lockout ON group_leader_predictions;
CREATE TRIGGER trg_check_special_predictions_lockout
BEFORE INSERT OR UPDATE ON group_leader_predictions
FOR EACH ROW EXECUTE FUNCTION check_special_predictions_lockout();

-- Limpiar la clave obsoleta de la tabla de configuraciones
DELETE FROM app_config WHERE key = 'special_predictions_deadline';
