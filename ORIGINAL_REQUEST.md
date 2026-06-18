# Original User Request

## Initial Request — 2026-06-18T03:03:32Z

Optimizar y blindar la plataforma "Polla Mundialista" de Parley.la, removiendo la persistencia local (LocalStorage), eliminando el simulador de tiempo y partidos del frontend, migrando los cálculos pesados de leaderboard e insignias al backend (Supabase), y asegurando el proceso contra manipulaciones de tiempo.

Working directory: c:/Users/DELL/OneDrive/Escritorio/POLLA
Integrity mode: development

## Requirements

### R1. Remoción de LocalStorage para Estado del Juego
Se debe eliminar toda lectura y escritura en `localStorage` relacionada con datos del torneo (pronósticos, perfiles de usuarios, streaks, asignación de insignias o variables administrativas del torneo). La persistencia de los datos del juego debe depender exclusivamente de las consultas y mutaciones en Supabase. Las únicas claves de almacenamiento local toleradas son las que maneja internamente la SDK de Supabase para la sesión o la preferencia de notificaciones del dispositivo específico.

### R2. Eliminación Completa del Simulador y Datos Ficticios
Remover del código del frontend (`app.js`, `index.html`) toda interfaz visual, variable de estado (`STATE.simulatedTime`, `STATE.simulatorEnabled`, `STATE.realTimeOffset`), generadores de usuarios de prueba (mock users), y funciones condicionales del simulador. La aplicación debe operar únicamente en base al tiempo real del sistema y datos verídicos de Supabase.

### R3. Blindaje de Seguridad Temporal y Validación en Base de Datos (Supabase PostgreSQL RLS)
Implementar validaciones en el backend para evitar que los usuarios guarden o editen pronósticos de partidos una vez iniciados. Esto se debe lograr configurando Row Level Security (RLS) y restricciones (triggers o políticas) en la tabla `predictions` en PostgreSQL (Supabase) que comparen el tiempo del servidor (`now()`) contra la fecha de inicio del encuentro antes de autorizar cualquier `INSERT` o `UPDATE`.

### R4. Leaderboard Optimizado y Paginado en Backend
Migrar el recálculo y ordenamiento de puntos de todos los usuarios (incluyendo streaks y badges de rendimiento) desde el cliente hacia la base de datos PostgreSQL de Supabase. El frontend debe consultar y cargar la clasificación de forma paginada (ej. bloques de 50 usuarios) en lugar de descargar el set de datos completo de todos los usuarios para calcularlo en local.

### R5. Arquitectura de Notificaciones Push Reales
Desacoplar la simulación de notificaciones local (`triggerLocalNotificationSim`) basada en temporizadores del frontend. El Service Worker (`sw.js`) debe recibir eventos `push` auténticos del servidor de notificaciones de Supabase y el cliente debe enfocarse únicamente en el registro correcto de suscripciones en la tabla `push_subscriptions`.

## Acceptance Criteria

### Integridad del Código y Almacenamiento
- [ ] No existen llamadas a `localStorage.setItem` o `localStorage.getItem` en `app.js` para persistir datos del torneo o resultados de grupos.
- [ ] Todo el código e interfaz del simulador (paneles, botones, variables de simulación de tiempo) ha sido removido de `app.js` e `index.html`.

### Seguridad y Consistencia de Datos
- [ ] Un intento de guardar o actualizar una fila en `predictions` mediante una petición directa a Supabase fuera del horario límite (después del inicio del partido) es rechazado por la base de datos con un error de Postgres.
- [ ] El cálculo de clasificaciones y asignación de insignias se ejecuta en el backend, y el frontend carga los datos paginados sin congelar la interfaz ni descargar toda la lista de usuarios.

### Notificaciones y Service Worker
- [ ] El archivo `sw.js` gestiona eventos `push` del navegador utilizando datos de payloads auténticos enviados desde el backend.
- [ ] Se han removido las funciones de simulación local de notificaciones del cliente (`triggerLocalNotificationSim`).
