# Control de Gastos

Plataforma web para llevar los gastos de la familia, de los padres y de proyectos compartidos a partir de los movimientos de **Registro Contable (Money Manager, de Realbyte)**. Cada persona entra con su correo y contraseña y solo ve lo que el administrador le asignó.

## Qué hace

**El administrador (tú):**
- **Sincroniza** los movimientos de la app desde el portal Wi‑Fi del iPhone. Cada uno conserva su ID de la app.
- **Bandeja:** asigna cada movimiento a un control o proyecto, con su TIPO (compartido o de quién es) y su mes, o lo marca como "no aplica".
- **Dividir:** reparte un movimiento entre varios controles o proyectos (por ejemplo L 5,000: L 3,000 a un proyecto y L 2,000 a Familia). Lo que quede sin repartir sigue en la bandeja.
- **Cambios:** al sincronizar, detecta los movimientos ya asignados que se modificaron o se borraron en la app. Para cada uno decides: aplicar el cambio, mantener tu fila, quitarla o conservarla como manual. También marca los registros asignados más de una vez (duplicados) para quitarlos; la base de datos no deja asignar un registro por más de su monto.
- **Participantes por mes:** en cada mes de Familia o Padres eliges quién participa (por ejemplo, Jennifer solo en un mes). Solo ellos aparecen en TIPO y en la distribución de ese mes.
- **Por validar:** revisa lo que registran los demás. Puede ligarlo a un registro de la app (te sugiere los que coinciden por monto y fecha), aprobarlo como manual o rechazarlo con un motivo.
- **Usuarios:** activa cuentas, indica cómo aparece cada persona en TIPO y marca qué controles y proyectos puede ver.
- **Proyectos:** crea proyectos, dales una clave para que la bandeja los reconozca, y ciérralos al terminar.
- **Exporta a Excel** con el formato de las hojas mensuales y sus fórmulas de distribución, y genera un **reporte PDF** del mes o del proyecto.
- Al hacer clic en la descripción de cualquier fila se abre su **detalle**: cuenta, categoría, subcategoría, contenido, monto en la app, en qué partes se repartió, quién lo registró y validó.

**Los demás usuarios (por ejemplo tu esposa o tus papás):**
- Ven en **Inicio** sus controles y proyectos, con lo que les toca aportar en el mes.
- Ven el detalle y el resumen de distribución de lo que tienen asignado.
- Registran gastos e ingresos. Quedan **por validar** y no cuentan en los saldos hasta que el administrador los aprueba.
- Pueden corregir o borrar lo que registraron mientras siga por validar, y ven el motivo si se rechaza.

La seguridad no depende de la página. La aplican las reglas de la base de datos (Row Level Security de Supabase), así que nadie puede leer ni cambiar lo que no le corresponde aunque modifique la página.

## Archivos

| Archivo | Para qué |
|---|---|
| `index.html` | La plataforma |
| `config.js` | Dirección y clave pública de tu proyecto de Supabase |
| `supabase.sql` | Crea las tablas, permisos y reglas en Supabase |
| `servidor.py` | Servidor local opcional para sincronizar pegando solo el enlace del iPhone |
| `Iniciar Control de Gastos.command` | Abre `servidor.py` con doble clic en la Mac |

## Instalación (una sola vez)

### 1. Crea la base de datos en Supabase

1. Crea una cuenta gratis en [supabase.com](https://supabase.com) y un proyecto nuevo (región sugerida: la más cercana, por ejemplo *East US*). Guarda la contraseña de la base de datos en un lugar seguro.
2. Entra a **SQL Editor → New query**, pega todo el contenido de `supabase.sql` y presiona **Run**. Debe terminar con "Success".
3. Ve a **Authentication → URL Configuration**. En **Site URL** pon la dirección donde vas a publicar la plataforma (paso 2), por ejemplo `https://tu-usuario.github.io/control-gastos/`. En **Redirect URLs** agrega esa misma dirección y `http://localhost:8765/`.
4. Ve a **Project Settings → API** y copia **Project URL** y la clave **anon public**.

### 2. Publica la plataforma en GitHub Pages

1. Abre `config.js` y pega los dos datos del paso anterior:
   ```js
   window.CG_CONFIG = {
     supabaseUrl: 'https://abcdefgh.supabase.co',
     supabaseAnonKey: 'eyJhbGciOi...'
   };
   ```
   La clave *anon public* está hecha para ir en páginas públicas; lo que protege los datos son las reglas de `supabase.sql`.
2. Crea un repositorio en GitHub (por ejemplo `control-gastos`) y sube todos los archivos.
3. En **Settings → Pages**, en *Source*, elige **Deploy from a branch**, rama `main`, carpeta `/ (root)`. En uno o dos minutos queda en `https://tu-usuario.github.io/control-gastos/`.

> El repositorio puede ser público: no contiene datos ni contraseñas. Tus datos viven en Supabase.

### 3. Crea tu cuenta de administrador

Abre la plataforma, elige **Crear una cuenta** y regístrate con tu correo. **La primera cuenta que se crea es la del administrador**, así que hazlo tú antes de compartir el enlace. Confirma el correo que te llega y entra.

Luego, en **Ajustes**:
- Escribe las personas de cada control. Por ejemplo, en Familia: `JONATHAN CANALES, ELBA KATTAN`; en Padres: `ANTONIO CANALES, EDITH RUEDA`.
- Elige desde qué fecha quieres ver movimientos en la bandeja.

### 4. Invita a tu familia

1. Comparte el enlace de la plataforma (en **Usuarios → Copiar enlace**).
2. Cada persona crea su cuenta con su correo y confirma el correo que le llega. Verá "Tu cuenta espera acceso".
3. En **Usuarios**, la cuenta aparece como "Esperando acceso". Márcala como activa, escribe cómo aparece en TIPO (por ejemplo `ELBA KATTAN`) y elige qué puede ver: Familia, Padres o proyectos específicos.

Puedes quitar accesos o desactivar una cuenta en cualquier momento. Si alguien olvida su contraseña, usa "Olvidé mi contraseña" en la entrada.

## Sincronizar con Registro Contable

Solo el administrador sincroniza.

### Con el servidor local (recomendado: pegas el enlace y listo)

1. Doble clic en **`Iniciar Control de Gastos.command`**. Se abre una ventana de Terminal (déjala abierta) y la plataforma en `http://localhost:8765`.
2. En el iPhone abre Registro Contable y activa el servicio Wi‑Fi. Deja el teléfono desbloqueado y en el mismo Wi‑Fi que la Mac.
3. Presiona **Sincronizar** y pega la dirección que muestra la app (por ejemplo `192.168.1.164:8888`). Arranca solo.

La dirección se guarda; las siguientes veces basta con presionar **Sincronizar**.

**La primera vez:**
- Si macOS dice que es de un desarrollador no identificado: clic derecho sobre el archivo → **Abrir** → **Abrir**.
- Si la Mac no tiene Python 3, la ventana te lo indica (se instala con `xcode-select --install`).

Para que tu página de GitHub Pages también use el servidor local (funciona en Chrome), crea `servidor.json` junto a `servidor.py`:
```json
{"permitir": ["https://tu-usuario.github.io"]}
```

### Sin servidor: favorito del navegador

En **Ajustes → Sincronización**, arrastra **Enviar a Control de Gastos** a la barra de favoritos (se hace una sola vez). Luego, para sincronizar: presiona **Sincronizar**, pega la dirección del iPhone, presiona **Abrir portal**, toca el favorito y después **Copiar datos**, y regresa a pegar con Cmd+V.

Se traen los movimientos del año anterior y del actual. Lo ya asignado no cambia por sí solo: lo nuevo aparece en la bandeja, y si algo asignado se modificó o se borró en la app, aparece en la pestaña **Cambios** para que decidas.

## Actualizar desde una versión anterior

1. En Supabase, **SQL Editor → New query**, pega el `supabase.sql` nuevo y presiona **Run**. No borra datos: solo agrega lo necesario.
2. Sube el `index.html` nuevo a GitHub (reemplazando el anterior). En uno o dos minutos la página se actualiza.

Hazlo en ese orden: la página nueva necesita las columnas que agrega el SQL.

## Respaldos

En **Ajustes → Respaldo** descargas un `.json` con todo: controles, movimientos, accesos y lo sincronizado. Supabase guarda además respaldos automáticos en sus planes de pago.

## Detalles técnicos

- Frontend: HTML, CSS y JavaScript en un solo archivo, sin compilación. Usa [supabase-js 2.45.4](https://github.com/supabase/supabase-js) (jsDelivr), [ExcelJS 4.4.0](https://github.com/exceljs/exceljs), [jsPDF 2.5.1](https://github.com/parallax/jsPDF) y jspdf-autotable 3.8.2 (cdnjs, solo al exportar) y las fuentes Archivo e IBM Plex Mono.
- Base de datos: tablas `perfiles`, `controles`, `accesos`, `movimientos`, `tx_mes`, `ignorados` y `ajustes`, con RLS. Un usuario ve los controles donde tiene acceso; lo que inserta se fuerza a `pendiente` mediante un trigger. `tx_mes`, `ignorados` y `ajustes` son solo para el administrador. La primera cuenta registrada queda como administrador. Un registro de la app puede estar en varias filas de `movimientos` (reparto); cada fila guarda los datos de la app al asignarse (`app_monto`, `app_fecha`, `app_detalle`, `app_cuenta`, `app_categoria`) para detectar cambios. `controles.personas_mes` guarda los participantes de cada mes.
- `servidor.py`: servidor HTTP de la biblioteca estándar de Python. Sirve la plataforma y expone `GET /api/portal?base=…&desde=…&hasta=…`, que lee `/moneyBook/getDataByPeriod` del portal de la app. Solo acepta direcciones de la red local.
- Formato del portal: `GET /moneyBook/getDataByPeriod?startDate=AAAA-MM-DD&endDate=AAAA-MM-DD&mbid=1&assetId=` devuelve XML con `id`, `mbDate`, `inOutCode` (0 ingreso, 1 gasto, 3 traslado), `payType`, `mbCategory`, `subCategory`, `mbContent`, `mbDetailContent` y `mbCash`.
