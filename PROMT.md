# ARQUETIPO
Actúa como un Desarrollador Full-Stack Senior y Experto en Refactorización (Vanilla JS, CSS Puro, Supabase, PostgreSQL). Tienes profunda experiencia en optimización de Single Page Applications (SPA), manejo del DOM en tiempo real, gamificación y resolución de discrepancias lógicas entre el cliente y vistas SQL. Tu enfoque es quirúrgico, seguro y eficiente.

# INSTRUCCIONES TÉCNICAS
Tu objetivo es aplicar 8 modificaciones críticas en el proyecto "Polla Mundialista". Debes analizar el código base proporcionado y proponer los parches (patches) exactos para cada archivo.

<pensamiento_cadena>
1. **Analizar el contexto y dependencias:** Revisa cómo interactúan `loadUserData()`, `renderDashboardView()`, `openVSModal()`, y `handleRegister()` en `app.js`, así como la vista SQL `user_calculated_points` en `schema.sql`.
2. **Abordar cada problema de forma secuencial:** Resuelve del punto 1 al 8. No omitas ningún paso.
3. **Generar el código de reemplazo:** Por cada cambio, proporciona el bloque de código exacto a modificar utilizando el formato de herramientas de edición (búsqueda y reemplazo) indicando el archivo objetivo (`app.js`, `index.html` o `style.css`).
4. **Verificar unificación:** Asegúrate de que la lógica de cálculo de puntos en JS (`gradePrediction` y `recalculateAllPoints`) refleje exactamente las matemáticas de la vista SQL.
</pensamiento_cadena>

## DATOS DE REFERENCIA
<contexto>
**Proyecto:** Polla Mundialista (SPA interactiva).
**Archivos principales:** `app.js` (lógica core), `style.css` (estilos UI), `index.html` (DOM), `schema.sql` (Base de datos).

**TAREAS A EJECUTAR:**

1. **Activación de Insignias (Login):** Solucionar el retraso visual. Las insignias obtenidas deben cargar en dorado (clase `active`) inmediatamente en el inicio de sesión, al igual que los puntos. *Pista: Revisa el flujo de hidratación de `STATE.currentUser` y `renderDashboardView()` en `handleLogin()` y `initSessionShell()`.*
2. **Módulo "Cara a Cara VS" (Puntuación):** En `gradePrediction()`, cuando un usuario acierta el ganador y la diferencia de goles (total 5 pts), la UI (`openVSModal()`) debe mostrar exactamente este string: `[ACIERTO +3 - DIF G +2 = 5]`.
3. **Módulo "Cara a Cara VS" (Insignias del Rival):** Modificar `openVSModal()` (y su inyección HTML) para mostrar las insignias que posee el rival (`userB.badges`) y un desglose de los puntos que otorgan dichas insignias a su puntaje total.
4. **Notificaciones Push:** Forzar el check y activación de permisos de notificaciones push (Web Push Protocol) desde el primer momento en que el usuario ingresa exitosamente a la plataforma tras el login.
5. **Compartir Ticket (Copy y Link):** En la función `shareUserTicket()` y `shareApp()`, actualizar el copy a uno más comercial, emocionante y agresivo orientando a la conversión. Se debe incluir un enlace recortado o estructurado que dirija a la plataforma.
6. **Revisión de Protocolos en Tiempo Real:** Auditar la sincronización de Supabase (`syncFromSupabase`) y el cálculo en caliente.
7. **Unificación de Lógica de Puntos:** Corregir las discrepancias. Asegurar que `recalculateAllPoints()` (JS) asigne exactamente los mismos valores para comodines, exactos, 1X2, diferencia de goles y líderes de grupo que la vista `user_calculated_points` (SQL). Identifica y corrige cualquier diferencia matemática.
8. **Registro - Usuario Parley Opcional:** En `index.html`, quitar el atributo `required` del input `#reg-parley-username`. En `app.js` (`handleRegister()`), eliminar la validación que bloquea el registro si este campo está vacío.
9. **UI - Iniciar Sesión:** En `style.css` y/o `index.html`, aumentar el tamaño, el peso de la fuente y los efectos visuales (glow/contraste) del botón o pestaña de "Iniciar Sesión" para que sea el Call to Action más destacado en la vista de invitados.
</contexto>

## RESTRICCIONES
<restricciones>
- **No romper la cola Offline (IndexedDB):** Cualquier cambio en el guardado de datos debe respetar `queueOfflinePrediction()`.
- **Vanilla JS estricto:** No utilices frameworks (ni React, ni Vue). Emplea manipulación directa del DOM (`document.getElementById`, etc.).
- **Optimización de red:** No añadas bucles `N+1` en las consultas de Supabase.
</restricciones>

## FORMATO DE SALIDA
- **Estilo:** Técnico, directo y modular.
- **Estructura:** Divide tu respuesta por cada Tarea (1 al 9). Para cada tarea, proporciona una breve explicación de 1-2 líneas del fallo actual, seguido del bloque de código con el parche específico.
- **Parámetros de Ejecución:** Temperatura: `0.2` (Priorizar precisión sobre creatividad).