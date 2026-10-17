# Rediseño de VLC — análisis del vídeo «Redesigned VLC»

Fuente: `Redesigned VLC.mp4` (canal **Juxtopposed**). 20:59 min, 1920×1080 a 60 fps.
Método: 164 cortes de escena detectados, muestreo a 1 fotograma por segundo en los tramos sin cortes y
44 fotogramas clave en alta resolución (carpeta [`keyframes/`](keyframes)).
El audio (narración) **no** se ha transcrito: este equipo no tiene herramienta de voz a texto. Las conclusiones salen
de lo que se ve: interfaz, rótulos y gráficos de la encuesta.

> En 20:00 el autor dice: *«this redesign will be open-source and free — links in the description»*.
> Lo más valioso sería el archivo de diseño enlazado en la descripción del vídeo de YouTube (probablemente Figma),
> porque tiene medidas y colores exactos. Los valores de este documento son aproximaciones medidas sobre fotogramas comprimidos.

## 1. Estructura del vídeo

| Tiempo | Capítulo | Contenido |
|---|---|---|
| 0:00–1:15 | Intro | Comentarios de usuarios («parece de 2000-2010», «los iconos están anticuados», «funciones escondidas en menús»), encuesta propia y correo con el equipo de VLC (Jean-Baptiste Kempf). «You should keep the traffic cone»: **el cono se queda**. |
| 0:33 | *styles* | Comparativa de estilos (VLC 3, VLC 4, reproductores modernos). |
| 1:32 | *layout* | Dónde mira y pulsa la gente (gráficos de la encuesta). Prototipos de barra de controles. |
| 3:54 | *player* | Iteraciones del reproductor: barra de progreso, transporte, volumen, iconos, popup de pistas, subtítulos y aviso de «continuar viendo». |
| 9:19 | *library* | VLC 3 y VLC 4 actuales contra la nueva biblioteca: barra lateral, migas de pan, orden, cuadrícula/lista, Música, Red, Listas, cola. Investigación en Mobbin. |
| 15:35 | *settings* | Preferencias simples/avanzadas de VLC 3 («look through advanced interface settings…») contra los nuevos ajustes globales; plugins, editor de barras y «Personalizar reproductor». |
| 19:00 | Personalización | Encuesta de personalización, asistente de bienvenida (carpeta multimedia, tema y color), perfiles. |
| 20:09–20:59 | Presentación | «The All-Time Favorite Media Player is Back — With a Brand New UI». Montaje final y lemas **«More is Less»** y **«Your Player, Your VLC»**. |

## 2. Datos de la encuesta y decisiones que justifican

Unas 1.437–1.439 respuestas por pregunta.

| Pregunta | Resultado | Decisión de diseño |
|---|---|---|
| ¿Cómo pausas/reanudas en escritorio? | **87,3 % teclado**, 8,1 % botón | Los atajos son de primera clase: menú «Atajos de teclado» y categoría *Controles* en ajustes. Se mantienen los atajos de VLC. |
| ¿Con qué frecuencia usas atajos? | Siempre 27 %, a menudo 37 %, a veces 21,8 %, rara vez 11,4 % | Ídem. Los atajos también aparecen en los menús. |
| ¿Dónde buscas primero el título del medio? | **86,8 % arriba** | El título va **centrado en la barra de título**, no en la barra de controles. |
| ¿Dónde esperas el icono de subtítulos? | **80,8 % abajo a la derecha** | Botón de subtítulos en el grupo derecho de la barra de controles. |
| ¿Con qué frecuencia cambias la pista de vídeo? | **55,2 % nunca** | La pista de vídeo queda escondida (pestaña Vídeo del popup), no en la barra. |
| ¿Cuánto quieres personalizar? | Ninguna 8,2 % · mínima 15,4 % · básica 24,1 % · interfaz 17,6 % · skins/scripts 13,1 % · total 20,7 % | Personalización **por capas**: asistente (tema y color), ajustes, «Personalizar reproductor» (barra arrastrable), perfiles y extensiones. |

## 3. Principios

1. **«More is Less»**: toda la potencia de VLC, pero con divulgación progresiva. Lo básico va a la vista y lo avanzado detrás de
   «Show Preferences» / «Advanced Options ›».
2. **Se conserva la identidad**: cono, naranja y atajos clásicos.
3. **Oscuro, plano y sobrio**: iconos lineales de trazo fino, superficies grises en capas y el naranja solo para el estado activo.
4. **Todo a 1–2 clics**: pistas, subtítulos y velocidad en un popup del reproductor, no en menús anidados de 4 niveles
   (crítica explícita a `Playback > … > Custom Bookmarks > Manage`, fotograma 01).

## 4. Especificación por zonas

### 4.1 Ventana y barra de título ([33](keyframes/33-barra-lateral.jpg), [09](keyframes/09-biblioteca-titulo-carpeta.jpg))
- Izquierda: cono · «…» (menú principal) · botón de barra lateral · contexto/ruta (p. ej. carpeta «S01», o «▶ Videos» en el reproductor).
- Centro: **título del medio**.
- Derecha: minimizar, maximizar, **pantalla completa**, cerrar (4 botones).

### 4.2 Barra lateral ([33](keyframes/33-barra-lateral.jpg), [34](keyframes/34-listas.jpg), [16](keyframes/16-barra-lateral-compacta.jpg))
- Home, Videos, Music, Network, Playlists, Recent, separador y **Add item**.
- El elemento activo lleva icono y texto en naranja.
- **Modo compacto** de solo iconos (16).

### 4.3 Inicio ([39](keyframes/39-inicio-watch-next.jpg))
- «Watch Next ›»: fila de tarjetas para continuar viendo.

### 4.4 Biblioteca de vídeo ([32](keyframes/32-biblioteca-cuadricula.jpg), [10](keyframes/10-biblioteca-orden.jpg), [11](keyframes/11-biblioteca-menu-mas.jpg))
- Cabecera:
  - izquierda: ← →, migas de pan `Videos ▸ Shows ▸ The Wand ▸ S01`;
  - derecha: «15 items», ordenar, cuadrícula/lista, búsqueda y «…».
- Ordenar: Unwatched First ✓ · Watched First · Newest First · Oldest First · Title A-Z · Title Z-A.
- «…» de carpeta: Add File · Add Folder · Edit Subtitle Tracks · Edit Audio Tracks · Resync · Info.
- Tarjetas 16:9 con miniatura y nombre de archivo. **Barra de progreso naranja** en la parte inferior y los vistos atenuados.
- El título de carpeta aparece grande con flecha atrás (09).

### 4.5 Música ([12](keyframes/12-musica-categorias.jpg), [12b](keyframes/12b-musica-artista.jpg))
- «Music · 4 items»: Add, Songs, Albums, Artists, Genres (filas con icono).
- Página de artista con lista de pistas y miniatura.
- Botón «abrir en ventana» (↗) en la cabecera.

### 4.6 Red ([14](keyframes/14-red-pagina.jpg), [13](keyframes/13-red-index.jpg))
- Add Network Stream · Podcasts · Radio. Las listas M3U se abren como carpeta (`Network ▸ Index`, «110 items», canales de TV).
- Diálogo «Open Network Stream»: URL de red (varias líneas, «You can enter multiple links») y nombre de lista opcional
  («The playlist will be saved and displayed with this title»), con Cancel / Save.

### 4.7 Listas y cola ([34](keyframes/34-listas.jpg), [35](keyframes/35-cola.jpg), [08](keyframes/08-reproductor-con-cola.jpg))
- Listas: «+ Create playlist» y las listas creadas.
- Cola (panel derecho del reproductor):
  - cabecera «2 items - 47m» con ordenar, repetir, aleatorio, − y +;
  - filas con asa de arrastre «=» o ▶ naranja si es la actual, más la duración.

### 4.8 Reproductor ([37](keyframes/37-barra-progreso.jpg), [17](keyframes/17-aviso-continuar-viendo.jpg), [03](keyframes/03-reproductor-subtitulos-popup.jpg))
- **Barra de controles** (una sola fila, de izquierda a derecha):
  - anterior, play/pausa (píldora naranja, icono oscuro) y siguiente;
  - tiempo transcurrido, **barra de progreso gruesa** y tiempo total;
  - altavoz y **cuña de volumen** (degradado verde→naranja);
  - onda de audio (pistas de audio), subtítulos, ajustes (engranaje con ▶) y lista.
- Barra de progreso:
  - pista oscura con radio;
  - lo reproducido en naranja translúcido, con cabezal naranja vertical y redondeado;
  - puede mostrar **segmentos/marcas** (capítulos o marcadores) y, opcionalmente, la línea de subtítulos o la forma de onda.
- **Aviso de reanudación** centrado sobre los controles: «You already watched till 00:00:02 [Continue Watching] ×».
- Subtítulos dibujados sobre el vídeo, en el tercio inferior.

### 4.9 Popup de pista (engranaje / audio / subtítulos)
- Pestañas: **Playback · Video · Audio · Subtitles** (activa en naranja con subrayado).
- **Playback** ([06](keyframes/06-pista-reproduccion-velocidad.jpg), [07](keyframes/07-pista-reproduccion-opciones.jpg)):
  - Show Subtitle Timeline on Seekbar, Show Waveform on Seekbar, Reverse (interruptores);
  - Sleep Timer (Off…);
  - Speed: campo «1x» y deslizador 0.25–2 con marcas.
- **Video** ([05](keyframes/05-pista-video-tab.jpg)):
  - volteo None/Horizontal/Vertical, Rotate (0 deg), Zoom (1:1 Original), HDR (Auto);
  - Resolution (Best Available), Aspect Ratio, Crop, Render (Local) y sección Filters.
- **Subtitles** ([03](keyframes/03-reproductor-subtitulos-popup.jpg), [36](keyframes/36-pista-subtitulos-defaults.jpg)):
  - Embedded Tracks (None, Track 1 - English) y External Tracks (archivo con ✓, editar y +);
  - Defaults: pista e idioma;
  - Synchronization: retraso −10…+10 s con deslizador, Subtitle Speed (fps), Duration Factor;
  - Appearance: formato incrustado, fuente, color de texto y de contorno, desplazamiento, tamaño, grosor de contorno y opacidad de fondo;
  - botón «Show Preferences».

### 4.10 Menú principal «…» ([15](keyframes/15-menu-principal-completo.jpg), [18](keyframes/18-menu-principal-final.jpg), [28](keyframes/28-menu-perfiles.jpg), [29](keyframes/29-menu-perfiles-submenu.jpg))
- Open File (Ctrl+O) · Open Multiple Files (Ctrl+Shift+O) · Open Directory (Ctrl+F) · Open Disc (Ctrl+D) · Open Network Stream (Ctrl+N)
  · Open Capture Device (Ctrl+C) · Open Location from Clipboard (Ctrl+V) · Open Recent › · Save Playlist to File (Ctrl+Y)
  · Convert/Save (Ctrl+R) · Stream (Ctrl+S) · **Profile (Movies) ›** [Movies ✓, Shows, Music, Work, + New] · Keyboard Shortcuts
  · Customize Player · Plugins & Extensions › · Settings (Ctrl+P) · About VLC (Shift+F1).
- Icono lineal en cada entrada y atajo alineado a la derecha.

### 4.11 Ajustes globales ([20](keyframes/20-ajustes-general.jpg)–[26](keyframes/26-ajustes-subtitulos-2.jpg))
- Ventana única con **búsqueda** arriba a la izquierda. Categorías:
  - **App**: General, Interface, Privacy, Controls;
  - **Media**: Playback, Video, Audio, Subtitles, Library;
  - **System**: Network, Performance, Recording, Extensions.
- **General**:
  - Appearance: idioma de la interfaz, tema Dark/Light/System y 9 colores de acento;
  - Startup: diálogos de confirmación, buscar actualizaciones;
  - Diagnostics: modo desarrollador, guardar log, archivo de log, detalle del log;
  - al pie, «Advanced Options ›».
- **Privacy**:
  - History: guardar elementos recientes, recordar la posición de reproducción, no recordar mientras se ve, borrar historial;
  - Network: carátulas e info de Internet, enviar pistas, usuario de last.fm…
- **Controls**: atajos de teclado (editar), rueda del ratón, cantidades de salto, gestos.
- **Video**: Output, Picture (brillo, contraste, saturación, gamma), Deinterlacing y Framing (aspect ratio).
- **Subtitles**:
  - Tracks & Languages (activar, idioma preferido, codificación);
  - Loading Subtitles (carga automática, coincidencia de nombre «Title with extra characters»);
  - Appearance (fuente, tamaño relativo/píxeles, color, contorno, sombra, fondo, posición vertical);
  - Timing y On-Screen Messages.
- Interruptores ON/OFF en naranja; desplegables y deslizadores naranjas.

### 4.12 Personalizar reproductor ([27](keyframes/27-personalizar-reproductor.jpg))
- Rejilla de elementos para arrastrar a la barra:
  - **Estructura y transporte**: Spacer, Divider, Playback Speed, Forward/Backward 10 s, Stop, Repeat, Shuffle;
  - **Vídeo**: Record, Snapshot, Picture in Picture, HDR, Zoom;
  - **Navegación y app**: Right Sidebar, Quit VLC, VLC Settings, Go Home;
  - **Información**: Thumbnail, File Name, Artist Name, Folder Name, Playlist Name, Properties;
  - **Otros**: Replay, Chapters, Favorite, Bookmark, Bookmarks, Playlist.
- Botones Cancel/Save.

### 4.13 Bienvenida ([31](keyframes/31-bienvenida-tema-color.jpg), [38](keyframes/38-tema-acento.jpg))
1. «Welcome to VLC!»: texto, «Choose a Media Folder to get started with» (`~/Videos`, Browse) y Next.
2. «Select your preferred theme and color»: Light/Dark/System y 9 acentos (naranja, rojo, mostaza, verde, turquesa, azul, morado,
   magenta, gris), con Back/Next. La vista previa del reproductor se recolorea en vivo.

### 4.14 Tokens visuales (aproximados, a confirmar con el archivo original)
- **Colores**:
  - fondo ≈ #121212; panel lateral ≈ #181818; superficies #1E1E1E / #262626; líneas #2C2C2C;
  - texto #EDEDED, atenuado #9A9A9A;
  - acento naranja ≈ #FF8800 (en la píldora, tono más tostado ≈ #D9700A).
- **Tipografía**: sans geométrica tipo **Inter**, con cifras tabulares en los tiempos.
- **Iconos**: lineales de trazo fino; los de transporte, rellenos con esquinas redondeadas.
- **Radios**: 6–8 px en tarjetas, botones y popups.

## 5. Antes y después (referencia)

| Área | VLC 3 (instalado) | VLC 4 actual (`master`) | Rediseño |
|---|---|---|---|
| Navegación | Barra de menús Media/Playback/Audio/Video/Subtitle/Tools/View/Help | Home, Video, Music, Browse, Discover ([42](keyframes/42-vlc4-actual-inicio.jpg)) | Home, Videos, Music, **Network**, **Playlists**, **Recent** + menú «…» |
| Biblioteca | Árbol + iconos de cono ([41](keyframes/41-vlc-actual-biblioteca.jpg)) | Miniaturas negras sin progreso ([43](keyframes/43-vlc4-actual-carpeta.jpg)) | Miniaturas reales, progreso, orden «no vistos primero» |
| Pistas/subtítulos | Menús anidados y Herramientas › Preferencias ([19](keyframes/19-vlc-actual-prefs-subtitulos.jpg)) | Panel lateral | Popup con 4 pestañas en el reproductor |
| Ajustes | Simple/Avanzado con 9 iconos de cono | Igual (Qt Widgets) | Ventana única buscable por categorías |

## 6. Lo que falta en la recreación WPF local (`VlcPlayer/`)

Ya implementado: tema, acentos, barra lateral, migas de pan, orden, cuadrícula/lista, cola, popup de 4 pestañas (básico),
menú «…», ajustes por categorías, bienvenida (tema), barra de transporte, progreso, volumen e Inter.

Pendiente según el vídeo:
- **Barra de título y lateral**:
  - título del medio centrado en la barra de título;
  - pantalla Inicio «Watch Next»;
  - barra lateral compacta.
- **Reproductor**:
  - aviso de reanudación con el estilo del vídeo (abajo, sobre los controles);
  - icono de engranaje con ▶;
  - marcas de capítulos/marcadores en la barra de progreso;
  - línea de subtítulos y forma de onda opcionales en la barra.
- **Popup de pista**:
  - Playback: Sleep Timer, Reverse, opciones de la barra;
  - Video: rotar, voltear, HDR y resolución;
  - Subtitles: separar pistas incrustadas y externas, sincronización por velocidad y factor de duración, y la apariencia completa.
- **Biblioteca, Música y Red**:
  - menú «…» de carpeta (Edit Subtitle/Audio Tracks, Resync, Info);
  - página de artista;
  - Network con Podcasts y Radio;
  - M3U navegable como carpeta.
- **Menú y personalización**:
  - **Perfiles** (Movies/Shows/Music/Work);
  - **Personalizar reproductor** (barra arrastrable);
  - paso «carpeta multimedia» en la bienvenida.
- **Ajustes**: categorías Privacy, Performance, Recording, Extensions y Network, más el enlace «Advanced Options ›».

## 7. Índice de fotogramas clave

| Archivo | Muestra |
|---|---|
| 01 | VLC actual: menú contextual de lista (problema) |
| 02 | Encuesta: subtítulos abajo a la derecha (80,8 %) |
| 03 | Popup de subtítulos (pistas incrustadas/externas) |
| 04 | VLC actual: diálogo de abrir archivos |
| 05 | Popup de pista › Vídeo |
| 06–07 | Popup de pista › Reproducción (velocidad, línea temporal, forma de onda, reverse, temporizador) |
| 08 | Reproductor con cola lateral |
| 09 | Cabecera de carpeta «The Wand» |
| 10 | Menú de orden |
| 11 | Menú «…» de carpeta |
| 12 / 12b | Música (categorías) / página de artista |
| 13 / 14 | Red: lista M3U navegable / página Red |
| 15 / 18 | Menú principal «…» (parte alta / parte baja) |
| 16 | Barra lateral compacta |
| 17 | Aviso «You already watched till…» |
| 19 | VLC actual: preferencias de subtítulos |
| 20–26 | Ajustes: General, acento, Privacidad, Controles, Vídeo, Subtítulos 1 y 2 |
| 27 | Personalizar reproductor |
| 28–29 | Menú con perfiles |
| 30 | Encuesta de personalización |
| 31 / 38 | Bienvenida: tema y color |
| 32 | Biblioteca en cuadrícula (presentación final) |
| 33 / 34 | Barra lateral / Listas |
| 35 | Cola |
| 36 | Popup › Subtítulos (valores por defecto y sincronización) |
| 37 | Barra de progreso (detalle) |
| 39 | Inicio «Watch Next» |
| 40 | Lema final «Your Player, Your VLC» |
| 41–43 | VLC 3 biblioteca / VLC 4 Inicio / VLC 4 carpeta (estado actual) |
