/**
 * POLLA MUNDIALISTA — Google Apps Script
 * Módulo M4: Sincronización de usuarios desde la app web hacia Google Sheets
 *
 * INSTRUCCIONES DE DESPLIEGUE (PASO A PASO):
 * ============================================
 * 1. Ve a: https://script.google.com/
 * 2. Crea un nuevo proyecto → ponle nombre: "Polla Mundialista Sync"
 * 3. Borra el contenido del editor y pega TODO este código
 * 4. Reemplaza SPREADSHEET_ID con el ID de tu Google Sheet:
 *    - Abre tu hoja de Google Sheets
 *    - El ID está en la URL: docs.google.com/spreadsheets/d/[ESTE_ES_EL_ID]/edit
 * 5. Haz clic en "Implementar" → "Nueva implementación"
 * 6. Tipo: "Aplicación web"
 * 7. Ejecutar como: "Yo (tu cuenta)"
 * 8. Quién tiene acceso: "Cualquier usuario"
 * 9. Haz clic en "Implementar" → Copia la URL generada
 * 10. Pega esa URL en app.js, reemplazando 'REEMPLAZAR_CON_URL_DEL_APPS_SCRIPT'
 *
 * COLUMNAS EN EL GOOGLE SHEET:
 * A: Cédula | B: Nombre | C: Usuario Parley | D: Correo | E: Teléfono
 * F: F. Nacimiento | G: Puntos | H: Exactos | I: Aciertos 1X2 | J: Insignias | K: Última Sincronización
 */

// 🔧 CONFIGURA TU SPREADSHEET ID AQUÍ:
const SPREADSHEET_ID = 'REEMPLAZAR_CON_TU_SPREADSHEET_ID';
const SHEET_NAME = 'Usuarios';

/**
 * Punto de entrada HTTP POST — recibe el sync desde la app
 */
function doPost(e) {
  try {
    const body = JSON.parse(e.postData.contents);

    if (body.action !== 'sync' || !Array.isArray(body.users)) {
      return jsonResponse({ error: 'Payload inválido' }, 400);
    }

    const result = syncUsersToSheet(body.users);
    return jsonResponse({ success: true, updated: result.updated, inserted: result.inserted });

  } catch (err) {
    console.error('Error en doPost:', err);
    return jsonResponse({ error: err.toString() }, 500);
  }
}

/**
 * Sincroniza el array de usuarios al Google Sheet
 * - Si el usuario (por cédula) ya existe: actualiza su fila
 * - Si no existe: inserta una nueva fila
 */
function syncUsersToSheet(users) {
  const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
  let sheet = ss.getSheetByName(SHEET_NAME);

  // Crear la hoja si no existe
  if (!sheet) {
    sheet = ss.insertSheet(SHEET_NAME);
  }

  // Asegurar que los encabezados existan
  ensureHeaders(sheet);

  const now = new Date().toLocaleString('es-VE', { timeZone: 'America/Caracas' });
  let inserted = 0;
  let updated = 0;

  // Leer todas las cédulas existentes para búsqueda eficiente
  const lastRow = sheet.getLastRow();
  let existingCedulas = {};

  if (lastRow > 1) {
    const cedulaCol = sheet.getRange(2, 1, lastRow - 1, 1).getValues();
    cedulaCol.forEach((row, idx) => {
      if (row[0]) existingCedulas[row[0].toString().trim()] = idx + 2; // +2 porque row 1 = headers
    });
  }

  users.forEach(u => {
    const rowData = [
      u.cedula || '',
      u.nombre || '',
      u.parley_username || '',
      u.correo || '',
      u.telefono || '',
      u.fecha_nacimiento || '',
      u.puntos || 0,
      u.exactos || 0,
      u.aciertos_1x2 || 0,
      u.insignias || '',
      now
    ];

    const cedulaKey = (u.cedula || '').toString().trim();

    if (existingCedulas[cedulaKey]) {
      // Actualizar fila existente
      const rowIndex = existingCedulas[cedulaKey];
      sheet.getRange(rowIndex, 1, 1, rowData.length).setValues([rowData]);
      updated++;
    } else {
      // Insertar nueva fila
      sheet.appendRow(rowData);
      existingCedulas[cedulaKey] = sheet.getLastRow();
      inserted++;
    }
  });

  // Auto-ajustar columnas
  sheet.autoResizeColumns(1, 11);

  return { updated, inserted };
}

/**
 * Crea los encabezados si la fila 1 está vacía
 */
function ensureHeaders(sheet) {
  const headers = [
    'CÉDULA', 'NOMBRE COMPLETO', 'USUARIO PARLEY', 'CORREO ELECTRÓNICO',
    'TELÉFONO', 'F. NACIMIENTO', 'PUNTOS', 'EXACTOS', 'ACIERTOS 1X2',
    'INSIGNIAS', 'ÚLTIMA SINCRONIZACIÓN'
  ];

  const firstRow = sheet.getRange(1, 1, 1, headers.length).getValues()[0];
  const isEmpty = firstRow.every(cell => cell === '');

  if (isEmpty) {
    sheet.getRange(1, 1, 1, headers.length).setValues([headers]);

    // Estilo de encabezados
    const headerRange = sheet.getRange(1, 1, 1, headers.length);
    headerRange.setBackground('#0E1626');
    headerRange.setFontColor('#FFD700');
    headerRange.setFontWeight('bold');
    headerRange.setFontSize(10);
    sheet.setFrozenRows(1);
  }
}

/**
 * Respuesta JSON helper
 */
function jsonResponse(data, statusCode) {
  return ContentService
    .createTextOutput(JSON.stringify(data))
    .setMimeType(ContentService.MimeType.JSON);
}

/**
 * Test manual — ejecutar desde el editor para probar sin la app
 */
function testSync() {
  const testUsers = [
    {
      cedula: 'V-12345678',
      nombre: 'Juan Pérez',
      parley_username: 'juanperez99',
      correo: 'juan@test.com',
      telefono: '04141234567',
      fecha_nacimiento: '1990-05-15',
      puntos: 42,
      exactos: 3,
      aciertos_1x2: 8,
      insignias: 'Ojo Clínico; HAT-TRICK VIP'
    }
  ];
  const result = syncUsersToSheet(testUsers);
  console.log('Test sync result:', JSON.stringify(result));
}
