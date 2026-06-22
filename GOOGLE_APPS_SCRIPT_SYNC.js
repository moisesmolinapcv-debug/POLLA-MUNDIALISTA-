/**
 * POLLA MUNDIALISTA — Google Apps Script (v2 — CORS-SAFE)
 * Módulo M4: Sincronización de usuarios desde la app web hacia Google Sheets
 *
 * ⚠️ IMPORTANTE: Este script usa doGet() en lugar de doPost() para evitar
 *    el bloqueo CORS que ocurre con peticiones POST desde navegadores.
 *
 * INSTRUCCIONES DE DESPLIEGUE (PASO A PASO):
 * ============================================
 * 1. Ve a: https://script.google.com/
 * 2. Abre el proyecto "Polla Mundialista Sync" (o crea uno nuevo)
 * 3. Borra TODO el contenido y pega este código completo
 * 4. Reemplaza SPREADSHEET_ID con el ID de tu Google Sheet:
 *    - Abre tu hoja en Google Sheets
 *    - La URL será: docs.google.com/spreadsheets/d/[AQUI_ESTÁ_EL_ID]/edit
 * 5. Haz clic en "Implementar" → "NUEVA implementación" (no editar la existente)
 * 6. Tipo: "Aplicación web"
 * 7. Ejecutar como: "Yo (tu cuenta)"
 * 8. Quién tiene acceso: "Cualquier usuario" (Anyone)
 * 9. Haz clic en "Implementar" → Autoriza los permisos → Copia la URL generada
 * 10. Pega esa URL NUEVA en app.js en la variable APPS_SCRIPT_URL
 *
 * COLUMNAS EN EL GOOGLE SHEET:
 * A: Cédula | B: Nombre | C: Usuario Parley | D: Correo | E: Teléfono
 * F: F. Nacimiento | G: Puntos | H: Exactos | I: Aciertos 1X2 | J: Insignias | K: Última Sincronización
 */

// 🔧 CONFIGURA TU SPREADSHEET ID AQUÍ (reemplaza el texto entre comillas):
const SPREADSHEET_ID = 'REEMPLAZAR_CON_TU_SPREADSHEET_ID';
const SHEET_NAME = 'Usuarios';

/**
 * Punto de entrada HTTP GET — recibe el sync desde la app web
 * Los datos llegan como parámetro "data" codificado en Base64 para evitar CORS.
 */
function doGet(e) {
  // Cabeceras CORS permisivas para cualquier origen
  const output = ContentService.createTextOutput();
  output.setMimeType(ContentService.MimeType.JSON);

  try {
    // Los datos vienen codificados en Base64 en el parámetro "data"
    const encodedData = e.parameter.data;
    if (!encodedData) {
      output.setContent(JSON.stringify({ error: 'No data parameter provided' }));
      return output;
    }

    // Decodificar Base64 → JSON string → objeto
    const jsonString = Utilities.newBlob(
      Utilities.base64Decode(encodedData)
    ).getDataAsString();
    const body = JSON.parse(jsonString);

    if (body.action !== 'sync' || !Array.isArray(body.users)) {
      output.setContent(JSON.stringify({ error: 'Payload inválido' }));
      return output;
    }

    const result = syncUsersToSheet(body.users);
    output.setContent(JSON.stringify({ success: true, updated: result.updated, inserted: result.inserted }));
    return output;

  } catch (err) {
    console.error('Error en doGet:', err);
    output.setContent(JSON.stringify({ error: err.toString() }));
    return output;
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
    const cedulaKey = (u.cedula || '').toString().trim();
    let rowData;

    if (existingCedulas[cedulaKey]) {
      // Actualizar fila existente preservando estadísticas si no vienen en el payload (caso Webhook)
      const rowIndex = existingCedulas[cedulaKey];
      const existingRowValues = sheet.getRange(rowIndex, 1, 1, 11).getValues()[0];

      rowData = [
        u.cedula !== undefined ? u.cedula : existingRowValues[0],
        u.nombre !== undefined ? u.nombre : existingRowValues[1],
        u.parley_username !== undefined ? u.parley_username : existingRowValues[2],
        u.correo !== undefined ? u.correo : existingRowValues[3],
        u.telefono !== undefined ? u.telefono : existingRowValues[4],
        u.fecha_nacimiento !== undefined ? u.fecha_nacimiento : existingRowValues[5],
        u.puntos !== undefined ? u.puntos : existingRowValues[6],
        u.exactos !== undefined ? u.exactos : existingRowValues[7],
        u.aciertos_1x2 !== undefined ? u.aciertos_1x2 : existingRowValues[8],
        u.insignias !== undefined ? u.insignias : existingRowValues[9],
        now
      ];

      sheet.getRange(rowIndex, 1, 1, rowData.length).setValues([rowData]);
      updated++;
    } else {
      // Insertar nueva fila (inicializar estadísticas en 0 si no se envían)
      rowData = [
        u.cedula || '',
        u.nombre || '',
        u.parley_username || '',
        u.correo || '',
        u.telefono || '',
        u.fecha_nacimiento || '',
        u.puntos !== undefined ? u.puntos : 0,
        u.exactos !== undefined ? u.exactos : 0,
        u.aciertos_1x2 !== undefined ? u.aciertos_1x2 : 0,
        u.insignias !== undefined ? u.insignias : '',
        now
      ];

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
 * Punto de entrada HTTP POST — recibe llamadas en tiempo real desde el Webhook de Supabase.
 * No sufre de CORS porque es una llamada de servidor a servidor.
 */
function doPost(e) {
  const output = ContentService.createTextOutput();
  output.setMimeType(ContentService.MimeType.JSON);

  try {
    if (!e || !e.postData || !e.postData.contents) {
      output.setContent(JSON.stringify({ error: 'No post data received' }));
      return output;
    }

    const payload = JSON.parse(e.postData.contents);
    console.log('Webhook payload received:', JSON.stringify(payload));

    // Validar tabla
    if (payload.table !== 'profiles') {
      output.setContent(JSON.stringify({ error: 'Unsupported table: ' + payload.table }));
      return output;
    }

    if (payload.type === 'INSERT' || payload.type === 'UPDATE') {
      const record = payload.record;
      if (!record) {
        output.setContent(JSON.stringify({ error: 'No record data found' }));
        return output;
      }

      // Evitar sincronizar administradores o usuarios de prueba
      if (record.is_admin || record.is_mock) {
        output.setContent(JSON.stringify({ success: true, message: 'Skipped admin/mock user' }));
        return output;
      }

      // Mapear campos de 'profiles' a la estructura requerida
      const user = {
        cedula: record.cedula,
        nombre: record.name,
        parley_username: record.parley_username,
        correo: record.email,
        telefono: record.phone,
        fecha_nacimiento: record.dob
        // Puntos, exactos, aciertos e insignias quedan undefined para ser preservados
      };

      const result = syncUsersToSheet([user]);
      output.setContent(JSON.stringify({ success: true, action: payload.type, result }));
      return output;

    } else if (payload.type === 'DELETE') {
      const record = payload.old_record || payload.record;
      if (record && record.cedula) {
        const result = deleteUserFromSheet(record.cedula);
        output.setContent(JSON.stringify({ success: true, action: 'DELETE', result }));
        return output;
      }
      output.setContent(JSON.stringify({ success: true, message: 'DELETE event ignored (no cedula)' }));
      return output;
    }

    output.setContent(JSON.stringify({ error: 'Unsupported event type: ' + payload.type }));
    return output;

  } catch (err) {
    console.error('Error en doPost:', err);
    output.setContent(JSON.stringify({ error: err.toString() }));
    return output;
  }
}

/**
 * Elimina una fila del Google Sheet buscando por cédula
 */
function deleteUserFromSheet(cedula) {
  const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
  let sheet = ss.getSheetByName(SHEET_NAME);
  if (!sheet) return { deleted: 0 };

  const lastRow = sheet.getLastRow();
  if (lastRow <= 1) return { deleted: 0 };

  const cedulaCol = sheet.getRange(2, 1, lastRow - 1, 1).getValues();
  const cedulaToFind = cedula.toString().trim();
  
  for (let i = 0; i < cedulaCol.length; i++) {
    if (cedulaCol[i][0] && cedulaCol[i][0].toString().trim() === cedulaToFind) {
      const rowIndex = i + 2; // +2 por índice 1-based y fila de encabezados
      sheet.deleteRow(rowIndex);
      return { deleted: 1 };
    }
  }
  return { deleted: 0 };
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
 * Test manual — ejecutar desde el editor de Apps Script para verificar
 * que el SPREADSHEET_ID es correcto y tiene acceso
 */
function testSync() {
  const testUsers = [
    {
      cedula: 'V-12345678',
      nombre: 'Juan Pérez (TEST)',
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
  console.log('✅ Test sync result:', JSON.stringify(result));
}
