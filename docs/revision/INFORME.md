# Revisión de código y plan de rediseño de VLC

| | |
|---|---|
| **Repositorio** | `skofiel/vlc` (copia de VideoLAN VLC) |
| **Rama revisada** | `master`, la rama por defecto del fork |
| **Commit** | `4953f0be3ea61dd5fc62f2c333e540d2b166ccbc` (16‑10‑2026) |
| **Versión** | `4.0.0-dev` (`configure.ac:5`, `AC_INIT([vlc], [4.0.0-dev])`) |
| **Interfaz** | Qt 6 (≥ 6.2) + QML en `modules/gui/qt`. No es la interfaz Qt Widgets clásica de la rama 3.0.x. |
| **Alcance** | `modules/gui/qt`, `src/player`, `src/playlist`, `src/input`, parsers de subtítulos y listas de reproducción, decodificadores de subtítulos, accesibilidad e i18n |
| **Método** | Lectura de código, con callers, locks y propiedad de los objetos comprobados para cada hallazgo. Las citas se han verificado literalmente con `grep -F` sobre el commit indicado. **No se ha compilado VLC.** Ningún hallazgo se ha reproducido en ejecución. |
| **Cambios en el código de VLC** | Ninguno. Este documento es lo único que se añade. |

---

## Índice

1. [Resumen ejecutivo](#1-resumen-ejecutivo)
2. [Tabla priorizada de hallazgos](#2-tabla-priorizada-de-hallazgos)
3. [Hallazgos en detalle](#3-hallazgos-en-detalle)
   - 3.1 [Interfaz Qt/QML: ciclo de vida, hilos, señales, fugas, punteros nulos](#31-interfaz-qtqml-modulesguiqt)
   - 3.2 [Núcleo: `src/player`, `src/playlist`, `src/input`](#32-núcleo-srcplayer-srcplaylist-srcinput)
   - 3.3 [Entradas no confiables: subtítulos y listas](#33-entradas-no-confiables-subtítulos-y-listas)
   - 3.4 [Accesibilidad e internacionalización](#34-accesibilidad-e-internacionalización)
4. [Mejoras recomendadas (no son bugs)](#4-mejoras-recomendadas-no-son-bugs)
5. [Mapa de la interfaz para el rediseño](#5-mapa-de-la-interfaz-para-el-rediseño)
6. [Especificación «Redesigned VLC»](#6-especificación-redesigned-vlc)
7. [Plan por fases](#7-plan-por-fases)
8. [Anexo: metodología y límites](#8-anexo-metodología-y-límites)

---

## 1. Resumen ejecutivo

- **55 hallazgos**: 12 de severidad **Alta**, 21 **Media** y 22 **Baja**. Ninguno es Crítico. No he encontrado ejecución remota de código claramente explotable. El defecto más cercano es una escritura fuera de límites en `ram.c` (SEC‑01).
- **Los riesgos más serios son de estabilidad, no de seguridad:**
  - cuatro **interbloqueos** (CORE‑02, CORE‑03, QT‑01 y QT‑02);
  - varios **accesos a puntero nulo** que el usuario puede provocar con una acción normal (CORE‑01, CORE‑04, QT‑06 y QT‑07).
- **Errores de lógica con impacto directo en el usuario:**
  - al borrar el elemento que se está reproduciendo, la reproducción se detiene aunque queden elementos detrás (CORE‑05);
  - el comparador de ordenación no es antisimétrico (CORE‑06);
  - ordenar por tamaño falla en cuanto hay un stream en la lista (CORE‑07);
  - un dispositivo de red no desaparece de la lista al apagarse, o desaparece cuando no debe (QT‑04).
- **Entradas no confiables:** los parsers clásicos de `subtitle.c` están bien acotados. Los problemas están en `modules/demux/playlist/*`:
  - `ram.c`: lectura y escritura fuera de límites (SEC‑01);
  - `b4s.c`: puntero nulo (SEC‑03);
  - `xspf.c`: amplificación de memoria (SEC‑04);
  - `wpl.c`: uso de memoria ya liberada (SEC‑05).

  También en `subsusf.c` (puntero nulo, SEC‑02). El fuzzer actual **no cubre los módulos de listas**, porque usa la URL `vlc://nop` y estos módulos se seleccionan por extensión.
- **Accesibilidad e i18n:**
  - Los botones de ventana CSD no tienen nombre accesible (A11Y‑01).
  - En las vistas de tabla no se puede abrir el menú contextual con el teclado (A11Y‑02).
  - Los contrastes de la paleta clara no llegan a WCAG AA (A11Y‑05).
  - La interfaz QML **nunca se refleja** en idiomas RTL (A11Y‑07).
  - Con Meson, **no se extrae ninguna cadena `qsTr`** de QML, y faltan tres archivos en `POTFILES.in` (I18N‑01).
- **Rediseño:** la arquitectura ya ofrece casi todos los puntos de extensión necesarios:
  - paletas en `systempalette.cpp`, con `ColorContext` por conjunto de colores;
  - tamaños en `VLCStyle.qml`;
  - controles intercambiables en `PlayerControlbarControls.qml`;
  - barra lateral en `navigationmodel.cpp`;
  - página de pistas en `TracksMenu.qml`.

  Faltan tres piezas:
  - una **fuente tipográfica global**, que hoy no existe;
  - **menús QML**: todos los menús son `QMenu` nativos;
  - **ajustes en QML**: las preferencias son Qt Widgets.

  La sección 6 especifica el rediseño y la 7 lo reparte en fases. Las fases 0 y 1 (estabilidad e i18n) deberían ir antes del cambio visual.

---

## 2. Tabla priorizada de hallazgos

Prioridad: **P0** = corregir antes de cualquier trabajo de rediseño, **P1** = siguiente iteración, **P2** = cuando se toque el área.

Confianza: **Alta** = flujo verificado en el código. **Media** = verificado, pero depende de que se dé un orden temporal concreto o de un comportamiento externo.

| ID | Prio | Sev. | Conf. | Ubicación | Resumen |
|---|---|---|---|---|---|
| CORE‑01 | P0 | Alta | Alta | `src/input/input.c:2388` | Acceso a puntero nulo en «capítulo anterior» si el título no tiene capítulos |
| CORE‑02 | P0 | Alta | Alta | `src/input/input.c:849`, `:3276` | Se envía `INPUT_EVENT_ATTACHMENTS` con `item->lock` tomado: inversión de locks e interbloqueo |
| CORE‑03 | P0 | Alta | Media | `src/player/metadata.c:174`, `src/audio_output/meter.c:189` | Interbloqueo ABBA entre `metadata_listeners_lock` y `meter->lock` |
| CORE‑04 | P0 | Alta | Alta | `src/playlist/export.c:78`, `:87` | Etiquetas `goto` intercambiadas: `fclose(NULL)` y fuga de `FILE*` |
| QT‑01 | P0 | Alta | Alta | `modules/gui/qt/medialibrary/thumbnailcollector.cpp:26` | Interbloqueo ABBA y uso tras liberar al destruir `ThumbnailCollector` |
| QT‑02 | P0 | Alta | Media | `modules/gui/qt/network/networkmediamodel.cpp:445`, `:521` | El semáforo de preparse puede no liberarse y bloquear el hilo de la interfaz |
| SEC‑01 | P0 | Alta | Alta | `modules/demux/playlist/ram.c:401‑447` | `ParseClipInfo` lee y escribe `'\0'` fuera del búfer |
| A11Y‑01 | P1 | Alta | Alta | `modules/gui/qt/widgets/qml/CSDWindowButton.qml:27` | Los botones minimizar, maximizar y cerrar (CSD) no tienen nombre accesible |
| A11Y‑02 | P1 | Alta | Alta | `modules/gui/qt/widgets/qml/TableViewDelegateExt.qml:306‑344` | El menú contextual de las tablas no se puede abrir con el teclado |
| A11Y‑05 | P1 | Alta | Alta | `modules/gui/qt/style/systempalette.cpp:495‑513` | Contrastes de la paleta clara por debajo de WCAG AA (verde 1,17:1, enlaces 2,9:1) |
| A11Y‑07 | P1 | Alta | Media | `modules/gui/qt/qt.cpp:958` | La interfaz QML no se refleja nunca en idiomas RTL |
| I18N‑01 | P0 | Alta | Alta | `po/meson.build:6‑17`, `po/POTFILES.in` | Meson no extrae `qsTr` ni los plurales de `qtr`, y faltan archivos en `POTFILES.in` (3 de Qt detectados en la revisión, 135 en total, ver 7.2) |
| CORE‑05 | P1 | Media | Alta | `src/playlist/content.c:140` | Usa el tamaño de la lista ya reducido: se detiene la reproducción aunque queden elementos |
| CORE‑06 | P1 | Media | Alta | `src/playlist/sort.c:325` | `CompareOptionalIntegers` mira `a` en lugar de `has_a`, así que el comparador no es antisimétrico |
| CORE‑07 | P1 | Media | Alta | `src/playlist/sort.c:185`, `:456` | Ordenar por tamaño o fecha falla entero si un elemento no tiene `.stat` |
| CORE‑08 | P1 | Media | Alta | `src/player/player.c:2200` | En la ruta de error de `vlc_player_New` se borra un callback que nunca se registró |
| QT‑03 | P1 | Media | Alta | `modules/gui/qt/network/mediatreelistener.hpp:52‑54` | `cb` se destruye antes de quitar el listener: uso tras liberar |
| QT‑04 | P1 | Media | Alta | `modules/gui/qt/network/networkdevicemodel.cpp:107`, `:362` | `removeSource` tiene el retorno invertido y su `erase` borra un solo iterador |
| QT‑05 | P1 | Media | Alta | `modules/gui/qt/dialogs/dialogs/dialogmodel.cpp:256`, `:283` | Se escribe `m_shuttingDown` y `m_provider` sin el mutex: un aviso se pierde y la aplicación se cuelga |
| QT‑06 | P1 | Media | Alta | `modules/gui/qt/dialogs/dialogs_provider.cpp:427` | `assert(inputItem)` deja pasar un puntero nulo en las compilaciones de release |
| QT‑07 | P1 | Media | Media | `modules/gui/qt/medialibrary/medialib.cpp:66‑70` | Se añade un `Media` nulo a la playlist y falla `input_item_Hold(NULL)` |
| QT‑08 | P1 | Media | Alta | `modules/gui/qt/maininterface/video_window_handler.cpp:201`, `:217` | Puntero `QScreen*` colgante que nunca se pone a nulo |
| QT‑09 | P2 | Media | Media | `modules/gui/qt/dialogs/extensions/extensions.cpp:136‑143` | Se pasa un `extension_dialog_t*` sin propiedad a una lambda encolada |
| SEC‑02 | P1 | Media | Alta | `modules/codec/subsusf.c:578`, `:445` | Un `<style>` sin `name` provoca `strcasecmp(NULL, …)` |
| SEC‑03 | P1 | Media | Alta | `modules/demux/playlist/b4s.c:187‑189` | Un `<entry>` sin `Playstring` provoca `vlc_xml_decode(NULL)` |
| SEC‑04 | P1 | Media | Alta | `modules/demux/playlist/xspf.c:462‑471` | Un `<vlc:id>` enorme provoca reservas de varios GB |
| SEC‑07 | P2 | Media | Media | `modules/demux/playlist/playlist.c:149‑153`, `:193` | Las listas remotas pueden apuntar a `file://` o a rutas UNC, y el fallback no sanea la URI |
| A11Y‑03 | P2 | Media | Media | `modules/gui/qt/playlist/qml/PlaylistDelegate.qml:31` | Las filas de la cola y de las tablas no exponen su rol ni si están seleccionadas |
| A11Y‑04 | P2 | Media | Alta | `.../controlbarcontrols/VolumeWidget.qml:77`, `RecordButton.qml:32`, `LoopButton.qml:28` | El estado de silencio, grabación y repetición solo se ve por el icono o el color |
| A11Y‑06 | P2 | Media | Alta | `modules/gui/qt/dialogs/help/help.cpp:144‑166` | En «Acerca de», «Licencia», «Autores» y «Créditos» solo responden al ratón |
| I18N‑02 | P2 | Media | Alta | `.../medialibrary/qml/VideoAllSubDisplay.qml:185`, `plugins.cpp:970` | Plurales construidos a mano o ausentes |
| I18N‑03 | P2 | Media | Alta | `plugins.cpp:1127`, `gototime.cpp:55` y otros | Cadenas traducibles concatenadas o con HTML dentro |
| I18N‑04 | P2 | Media | Alta | `.../player/qml/TracksPageAudio.qml:41`, `PlaybackSpeedButton.qml:74` | Números con formato fijo, y `valueFromText` depende de la longitud de la traducción |
| CORE‑09 | P2 | Baja | Alta | `src/player/medialib.c:50`, `:298` | Fuga de `input->ml.states` en la segunda restauración y en las salidas tempranas |
| CORE‑10 | P2 | Baja | Alta | `src/player/title.c:138‑158` | Fugas en la ruta de error de `vlc_player_title_list_Create` |
| CORE‑11 | P2 | Baja | Alta | `src/playlist/content.c:65`, `:349` | Se ignora el fallo de `randomizer_Add` y el randomizer queda desincronizado |
| CORE‑12 | P2 | Baja | Media | `src/player/aout.c:216` | `DelCallbacks` sobre un aout que nunca registró los callbacks |
| CORE‑13 | P2 | Baja | Alta | `src/player/timer.c:758` | `ts_interval` se trunca a 32 bits en una API pública |
| CORE‑14 | P2 | Baja | Alta | `src/player/player.c:1917`, `:1937` | El `assert` admite `DATA_ES`, pero `cat2vars[]` solo llega hasta `SPU_ES` |
| CORE‑15 | P2 | Baja | Alta | `src/player/player.c:513`, `:978` | Fuga parcial si falla una de las dos reservas, y `%ld` con un `size_t` |
| QT‑10 | P2 | Baja | Alta | `modules/gui/qt/medialibrary/mlbookmarkmodel.cpp:543` | `initModel` añade listeners del player sin quitar el anterior (latente) |
| QT‑11 | P2 | Baja | Media | `modules/gui/qt/maininterface/video_window_handler.cpp:68` | Se lee `QWindow::windowStates()` desde el hilo del vout |
| QT‑12 | P1 | Baja | Alta | `modules/gui/qt/player/qml/PlayerControlbarControls.qml:46‑47` | `FRAME_PREV` y `FRAME_NEXT` intercambiados: el perfil «One‑liner» muestra «Fotograma anterior» |
| QT‑13 | P2 | Baja | Alta | `modules/gui/qt/style/systempalette.cpp:634` | `setColorAlpha("#lightGrey400", 0.2)` construye un `QColor` inválido |
| QT‑14 | P2 | Baja | Alta | `modules/gui/qt/maininterface/qml/MainDisplay.qml:125‑127` | La página `mlsettings` apunta a `MLFoldersSettings.qml`, que no existe |
| QT‑15 | P2 | Baja | Alta | `modules/gui/qt/player/qml/controlbarcontrols/VolumeWidget.qml:322‑335` | El ajuste de volumen con el botón derecho usa pasos fijos hasta 1,25 e ignora `qt-max-volume` |
| SEC‑05 | P2 | Baja | Alta | `modules/demux/playlist/wpl.c:170`, `:225‑227` | Uso de memoria liberada y de un puntero sin inicializar en `msg_Err` |
| SEC‑06 | P2 | Baja | Alta | `modules/codec/subsdec.c:485‑493` | `AppendCharacter` tiene coste O(n²) (DoS de CPU) |
| SEC‑08 | P2 | Baja | Alta | `modules/demux/playlist/asx.c:285`, `:756` | Fugas por elementos repetidos, y `ENTRYREF` con la condición invertida |
| SEC‑09 | P2 | Baja | Alta | `modules/demux/subtitle.c:915‑920` | Desbordamiento con signo en `subtitle_cmp` |
| SEC‑10 | P2 | Baja | Media | `modules/codec/scte27.c:456‑461` | El reensamblado de segmentos no tiene límite |
| SEC‑11 | P2 | Baja | Alta | `modules/demux/playlist/wms.c:76‑78` | `strncmp` de 11 bytes sobre un peek de 10 |
| A11Y‑08 | P2 | Baja | Alta | `modules/gui/qt/widgets/qml/TextAutoScroller.qml:54‑57` | Animaciones infinitas y ninguna opción de reducir el movimiento |
| A11Y‑09 | P2 | Baja | Media | `modules/gui/qt/dialogs/toolbar/qml/ToolbarEditorDialog.qml:31‑35` | Tamaños fijos en px que no siguen la escala de la interfaz |
| I18N‑05 | P2 | Baja | Alta | `FullscreenButton.qml:32`, `Dialogs.qml:372`, `vlctick.cpp` | Mayúsculas incoherentes y cadenas casi duplicadas |

---

## 3. Hallazgos en detalle

Las rutas son relativas a la raíz del repositorio. Los fragmentos están copiados literalmente del commit `4953f0b`.

### 3.1 Interfaz Qt/QML (`modules/gui/qt`)

#### QT‑01: `ThumbnailCollector`, interbloqueo ABBA y uso tras liberar al destruirse
- **Ubicación:**
  - `modules/gui/qt/medialibrary/thumbnailcollector.cpp:26‑31` (deleter);
  - `:62` (callback);
  - `thumbnailcollector.hpp:54‑60` (orden de los miembros).
- **Severidad:** Alta · **Confianza:** Alta

```cpp
    , m_ml_event_handle(nullptr, [this](vlc_ml_event_callback_t *cb)
    {
        assert(m_ml);
        QMutexLocker lock(&m_mut);
        m_ml->unregisterEventListener(cb);
    })
```
```cpp
    const auto self = reinterpret_cast<ThumbnailCollector *>(data);
    QMutexLocker lock(&self->m_mut);
```

**Explicación:**
- `vlc_ml_event_send` (`src/misc/medialibrary.c:57‑63`) llama a los callbacks con `p_priv->lock` tomado, y `vlc_ml_event_unregister_callback` (`:84`) toma ese mismo lock. Los dos hilos lo adquieren en orden contrario:
  - hilo de la interfaz: `m_mut` → `p_ml->lock`;
  - hilo de la ML: `p_ml->lock` → `m_mut`.
- Además, `m_pending` y `m_thumbnails` están declarados **después** de `m_ml_event_handle`, así que se destruyen antes que él. Durante ese intervalo el callback sigue registrado y puede leer `m_pending` ya destruido.

**Escenario:** se hace scroll rápido por la cuadrícula de playlists o de géneros. QML destruye un `CustomCoverImageResponse` (`mlcustomcover.cpp:249`) justo cuando llega `VLC_ML_EVENT_MEDIA_THUMBNAIL_GENERATED`, y la interfaz se queda congelada.

**Arreglo:**
```diff
     , m_ml_event_handle(nullptr, [this](vlc_ml_event_callback_t *cb)
     {
         assert(m_ml);
-        QMutexLocker lock(&m_mut);
         m_ml->unregisterEventListener(cb);   // el lock de la ML ya serializa
     })
+
+ThumbnailCollector::~ThumbnailCollector()
+{
+    m_ml_event_handle.reset();   // desregistrar ANTES de destruir m_pending/m_thumbnails
+}
```

#### QT‑02: `NetworkMediaModel`, el semáforo de preparse puede no liberarse
- **Ubicación:** `modules/gui/qt/network/networkmediamodel.cpp:445‑451` y `:521‑531`
- **Severidad:** Alta · **Confianza:** Media (depende de que el nodo se elimine durante el preparse)

```cpp
        m_preparseSem.acquire();
        if (m_parserReq != NULL)
        {
            vlc_preparser_req_Release( m_parserReq );
            m_parserReq = NULL;
        }
        m_parserReq = vlc_media_tree_Preparse( tree.get(), parser, m_treeItem.media.get() );
```
```cpp
    if (!d->m_preparseSem.tryAcquire())
    {
        auto parser = d->m_ctx->getNetworkPreparser();
        if (likely(parser != NULL))
        {
            if (d->m_parserReq != NULL)
                vlc_preparser_Cancel( parser, d->m_parserReq );
            //wait for the callback call on cancel
            d->m_preparseSem.acquire();
```

**Explicación:**
- El semáforo empieza en 1 y solo se libera en `onItemPreparseEnded`.
- `media_subtree_preparse_ended` (`src/media_source/media_tree.c:171‑176`) **no notifica** nada si el nodo ya no está en el árbol.
- Si el servidor (UPnP o SMB) desaparece mientras se lista la carpeta:
  1. el semáforo se queda en 0;
  2. `Cancel` no hace nada porque la petición ya terminó;
  3. el `acquire()` del destructor bloquea el hilo de la interfaz para siempre.
- Además, el callback libera el semáforo por **cualquier** nodo del árbol, no solo por el propio. Si hay dos modelos sobre el mismo árbol, el contador supera 1.

**Arreglo:**
- Sustituir el semáforo por un indicador de «petición en curso» que solo se use en el hilo de la interfaz.
- En el destructor, cancelar sin esperar.
- Como mínimo:
  - liberar el semáforo solo si `node->p_item == m_treeItem.media`;
  - tratar `vlc_media_tree_Preparse()==NULL` como si ya se hubiera liberado;
  - usar `tryAcquire(1, timeout)`.

#### QT‑03: `MediaTreeListener`, `cb` se destruye antes de quitar el listener
- **Ubicación:** `modules/gui/qt/network/mediatreelistener.hpp:52‑54`; uso en `mediatreelistener.cpp:15`
- **Severidad:** Media · **Confianza:** Alta

```cpp
    MediaTreePtr tree;
    ListenerPtr listener = nullptr;
    std::unique_ptr<MediaTreeListenerCb> cb;
```
```cpp
    self->cb->onItemAdded( self->tree, parent, children, count );
```

**Explicación:** el destructor implícito destruye los miembros en orden inverso: primero `cb` y después `listener`, cuyo deleter llama a `vlc_media_tree_RemoveListener`. En ese intervalo, el hilo de *services discovery* (mDNS, UPnP, SAP) puede llamar a `self->cb->…` sobre un objeto ya liberado. El resultado es un fallo intermitente al cerrar la vista de red mientras aparecen o desaparecen dispositivos.

**Arreglo:**
```diff
+    ~MediaTreeListener() { listener.reset(); }   // quitar el listener antes de destruir cb
-    MediaTreeListener( MediaTreeListener&& ) = default;
-    MediaTreeListener& operator=( MediaTreeListener&& ) = default;
+    MediaTreeListener( MediaTreeListener&& ) = delete;   // el userdata C es this
+    MediaTreeListener& operator=( MediaTreeListener&& ) = delete;
```

#### QT‑04: `NetworkDeviceItem::removeSource`, retorno invertido y `erase` de un solo iterador
- **Ubicación:** `modules/gui/qt/network/networkdevicemodel.cpp:107‑122` y `:362‑366`
- **Severidad:** Media · **Confianza:** Alta

```cpp
        mrls.erase(std::remove_if(
            mrls.begin(), mrls.end(),
            [item](const Source& source){
                return source.item == item;
            })
        );

        if (mrls.empty())
        {
            mainMrl = QUrl{};
            return false;
```
```cpp
        bool needDestruction = (*it)->removeSource(media, mediaSource);
        if (needDestruction)
        {
            m_items.erase(it);
        }
```

**Explicación:**
1. El comentario de la función dice «@return false when no sources left», pero quien la llama interpreta `true` como «destruir». El resultado es doble:
   - un dispositivo que desaparece por completo **se queda** como entrada fantasma;
   - un dispositivo anunciado por dos SD (por ejemplo, mDNS y SMB) **desaparece** en cuanto lo retira una sola de ellas.
2. `erase(remove_if(...))` sin segundo argumento borra un único elemento. Si no hay coincidencia, ejecuta `erase(end())`, que es comportamiento indefinido.

**Arreglo:**
```diff
-        mrls.erase(std::remove_if(
-            mrls.begin(), mrls.end(),
-            [item](const Source& source){
-                return source.item == item;
-            })
-        );
+        mrls.erase(std::remove_if(mrls.begin(), mrls.end(),
+                   [&item](const Source& s){ return s.item == item; }),
+                   mrls.end());
 ...
-        bool needDestruction = (*it)->removeSource(media, mediaSource);
+        bool needDestruction = !(*it)->removeSource(media, mediaSource);
```

#### QT‑05: `VLCDialogModel`, estado compartido escrito sin `m_lock`
- **Ubicación:** `modules/gui/qt/dialogs/dialogs/dialogmodel.cpp:256‑260`, `:283‑304` y la espera en `:324‑325`
- **Severidad:** Media · **Confianza:** Alta (la ventana de carrera es estrecha)

```cpp
VLCDialogModel::~VLCDialogModel()
{
    m_shuttingDown = true;
    m_providerWait.wakeAll();
    vlc_dialog_provider_set_callbacks(m_intf, nullptr, nullptr);
```
```cpp
    while (m_provider == nullptr && !m_shuttingDown)
        m_providerWait.wait(&m_lock);
```

**Explicación:**
- El hilo de entrada o de acceso comprueba la condición con `m_lock` tomado.
- En cambio, `setProvider()` y el destructor escriben y despiertan **sin** ese mutex. Si `wakeAll()` ocurre entre la comprobación y el `wait()`, el aviso se pierde y el hilo duerme para siempre.
- Escenarios:
  - cerrar VLC con un diálogo de login HTTP o SMB pendiente: el cierre se bloquea;
  - arrancar con una URL que pide credenciales: el diálogo no aparece nunca.
- Además hay una carrera de datos sobre `m_provider`.

**Arreglo:**
```diff
 VLCDialogModel::~VLCDialogModel()
 {
-    m_shuttingDown = true;
-    m_providerWait.wakeAll();
+    {
+        QMutexLocker lock(&m_lock);
+        m_shuttingDown = true;
+        m_providerWait.wakeAll();
+    }
```
Hacer lo mismo en `setProvider()`: asignar `m_provider` y llamar a `wakeAll()` con `m_lock` tomado.

#### QT‑06: `DialogsProvider::mediaInfoDialog(MLItemId)`, acceso a puntero nulo en release
- **Ubicación:** `modules/gui/qt/dialogs/dialogs_provider.cpp:427‑431`
- **Severidad:** Media · **Confianza:** Alta

```cpp
    input_item_t * const inputItem = vlc_ml_get_input_item( ml, itemId.id );
    assert( inputItem );

    const SharedInputItem sharedInputItem { inputItem, false };
    if ( input_item_IsPreparsed( inputItem ) )
```

**Explicación:**
- `vlc_ml_get_input_item` devuelve NULL en tres casos:
  - el medio ya no existe;
  - se produce `DeviceRemoved` (`modules/misc/medialibrary/entities.cpp:557‑562`);
  - falla una reserva de memoria.
- Con `NDEBUG`, el `assert` desaparece y `input_item_IsPreparsed(NULL)` provoca la caída.
- Escenario: se desconecta un USB indexado y, antes de que la vista se refresque, el usuario elige «Información multimedia».

**Arreglo:**
```diff
-    assert( inputItem );
+    if ( !inputItem )
+    {
+        msg_Warn( p_intf, "media %" PRId64 " unavailable", itemId.id );
+        return;
+    }
```
Además, mover la consulta a `runOnMLThread`, porque ahora se hace en el hilo de la interfaz.

#### QT‑07: `convertMLItemToPlaylistMedias`, se añade un `Media` nulo
- **Ubicación:** `modules/gui/qt/medialibrary/medialib.cpp:66‑70`
- **Severidad:** Media · **Confianza:** Media

```cpp
        auto mediaRange = ml_range_iterate<vlc_ml_media_t>( media_list );
        std::transform(mediaRange.begin(), mediaRange.end(), std::back_inserter(medias), [&](vlc_ml_media_t& m) {
            SharedInputItem item(vlc_ml_get_input_item( ml, m.i_id ), false);
            return vlc::playlist::Media(item.get(), options);
        });
```

**Explicación:**
- La rama de un solo medio (líneas 55‑57) sí comprueba `if (item)`. La de colecciones no lo hace.
- Un `Media(nullptr)` llega a `vlc_playlist_Append`, que llama a `input_item_Hold(NULL)` (`src/playlist/item.c:41`) y provoca la caída.
- Escenario: reproducir un álbum mientras se desmonta el dispositivo que contiene alguna de sus pistas.

**Arreglo:**
```diff
-        std::transform(mediaRange.begin(), mediaRange.end(), std::back_inserter(medias), [&](vlc_ml_media_t& m) {
-            SharedInputItem item(vlc_ml_get_input_item( ml, m.i_id ), false);
-            return vlc::playlist::Media(item.get(), options);
-        });
+        for (vlc_ml_media_t& m : mediaRange) {
+            SharedInputItem item(vlc_ml_get_input_item(ml, m.i_id), false);
+            if (item)
+                medias.push_back(vlc::playlist::Media(item.get(), options));
+        }
```

#### QT‑08: `VideoWindowHandler::m_lastWinScreen`, `QScreen*` colgante
- **Ubicación:** `modules/gui/qt/maininterface/video_window_handler.cpp:201` y `:217‑218`; declaración en `video_window_handler.hpp:68`
- **Severidad:** Media · **Confianza:** Alta

```cpp
            m_lastWinScreen = m_window->screen();
```
```cpp
        if( m_lastWinScreen != NULL && !m_hasWayland )
            m_window->setScreen(m_lastWinScreen);
```

**Explicación:**
- Es un puntero `QScreen*` sin protección. Qt libera el objeto cuando se desconecta un monitor, y el puntero nunca se pone a nulo.
- `setVideoFullScreen(false)` se llama al terminar **cada** vout.
- Con `qt-fullscreen-screennumber` configurado, en cuanto se desconecta el monitor original se produce un uso tras liberar.
- Aunque no se desconecte nada, cada vídeo devuelve la ventana a una pantalla antigua.

**Arreglo:**
```diff
-    QScreen* m_lastWinScreen = nullptr;
+    QPointer<QScreen> m_lastWinScreen;
 ...
         if( m_lastWinScreen && !m_hasWayland )
             m_window->setScreen(m_lastWinScreen);
+        m_lastWinScreen = nullptr;
```

#### QT‑09: `ExtensionsDialogProvider`, se pasa un puntero C sin propiedad a una lambda encolada
- **Ubicación:** `modules/gui/qt/dialogs/extensions/extensions.cpp:136‑143`
- **Severidad:** Media · **Confianza:** Media

```cpp
    //use auto connection here
    // * either we are in extension thread and this is safe to carry the extension_dialog_t
    //   through queued connection as the extension wait that we signal its condition variable
    // * either we are in Qt thread (during destruction for instance) and we want direct connection
    QMetaObject::invokeMethod(p_edp, [p_edp, p_ext_dialog]() {
        p_edp->UpdateExtDialog( p_ext_dialog );
    });
```

**Explicación:** la premisa del comentario no se cumple.
- En `vlclua_dialog_update` y `lua_DialogFlush` (`modules/lua/libs/dialog.c:667`, `:709`) la extensión **no** espera.
- `vlclua_dialog_delete` (`:571`) solo espera mientras `p_sys_intf != NULL`.
- Si la interfaz todavía no ha creado el diálogo, la extensión libera `p_dlg` y la lambda pendiente lo usa después.

**Arreglo:** para llamadas desde un hilo que no sea el de la interfaz, usar `Qt::BlockingQueuedConnection`, o mantener en el proveedor Qt un registro de diálogos vivos. Leer `b_kill` con `p_dialog->lock` tomado.

#### QT‑10: `MLBookmarkModel::initModel` acumula listeners del player (latente)
- **Ubicación:** `modules/gui/qt/medialibrary/mlbookmarkmodel.cpp:518‑527` y `:541‑545`
- **Severidad:** Baja · **Confianza:** Alta

```cpp
        vlc_player_locker lock{ m_player };
        vlc::threads::mutex_locker selflock{ m_mutex };
        m_listener = vlc_player_AddListener( m_player, &cbs, this );
```

**Explicación:**
- Cada cambio de `ml` o de `player` vuelve a llamar a `initModel()`, que sobrescribe `m_listener` sin quitar el anterior.
- Los listeners huérfanos apuntan a `this` cuando el objeto ya se ha destruido.
- Hoy los bindings de `Bookmarks.qml` son estáticos, así que el problema todavía no se manifiesta.

**Arreglo:** al principio de `initModel()`, si `m_listener` existe, llamar a `vlc_player_RemoveListener` y poner `m_listener = nullptr`. Hacer lo mismo en `setPlayer()`.

#### QT‑11: `requestResizeVideo` lee `QWindow` desde el hilo del vout
- **Ubicación:** `modules/gui/qt/maininterface/video_window_handler.cpp:64‑69`; se llama desde `compositor.cpp:140‑145`
- **Severidad:** Baja · **Confianza:** Media

```cpp
void VideoWindowHandler::requestResizeVideo( unsigned i_width, unsigned i_height )
{
    if (!m_window)
        return;
    emit askVideoToResize( i_width, i_height, m_window->windowStates() );
}
```

**Explicación:** ni `QPointer<QWindow>` ni `QWindow::windowStates()` son seguros entre hilos. Si se hace `setWindow()` o `unloadGUI` mientras el vout redimensiona, hay una carrera.

**Arreglo:** emitir solo `(w, h)` y leer `windowStates()` en el slot encolado, que ya se ejecuta en el hilo de la interfaz.

#### QT‑12: identificadores `FRAME_PREV` y `FRAME_NEXT` intercambiados
- **Ubicación:** `modules/gui/qt/player/qml/PlayerControlbarControls.qml:46‑47`; perfil en `modules/gui/qt/dialogs/toolbar/controlbar_profile_model.cpp:262`
- **Severidad:** Baja · **Confianza:** Alta

```qml
        { id: ControlListModel.FRAME_PREV_BUTTON, file: "FrameNextButton.qml", label: VLCIcons.next_frame, text: qsTr("Next Frame") },
        { id: ControlListModel.FRAME_NEXT_BUTTON, file: "FramePrevButton.qml", label: VLCIcons.previous_frame, text: qsTr("Previous Frame") },
```

**Explicación:** el perfil predefinido «One‑liner» declara `ControlListModel::FRAME_NEXT_BUTTON`, pero lo que se pinta es `FramePrevButton.qml`, que llama a `Player.framePrev()`. El usuario ve y usa «Fotograma anterior» donde debería haber «Fotograma siguiente».

**Arreglo:** asociar `FRAME_NEXT_BUTTON` con `FrameNextButton.qml`, `next_frame` y «Next Frame», y `FRAME_PREV_BUTTON` con su pareja. Si algún usuario ya colocó el botón a mano, su perfil guardado cambiará de botón. Conviene avisarlo en `NEWS`.

#### QT‑13: color inválido en la paleta clara del slider
- **Ubicación:** `modules/gui/qt/style/systempalette.cpp:634`
- **Severidad:** Baja · **Confianza:** Alta

```cpp
        setColor(CS, C::Bg, C::Secondary, C::Normal, setColorAlpha("#lightGrey400", 0.2));
```

**Explicación:** `"#lightGrey400"` es un literal de texto, no la constante del mismo nombre. `QColor("#lightGrey400")` es un color inválido, así que el fondo secundario del slider en modo claro se pinta transparente o negro, según quién lo consuma.

**Arreglo:** `setColorAlpha(lightGrey400, 0.2)`.

#### QT‑14: página `mlsettings` sin archivo
- **Ubicación:** `modules/gui/qt/maininterface/qml/MainDisplay.qml:125‑127`
- **Severidad:** Baja · **Confianza:** Alta

```qml
            name: "mlsettings",
            url: "qrc:///qt/qml/VLC/MediaLibrary/MLFoldersSettings.qml"
        }
```

**Explicación:**
- `MLFoldersSettings.qml` no existe en el árbol, ni en `meson.build` ni en `Makefile.am`.
- Nadie hace `History.push(["mlsettings"])`, así que la entrada es código muerto. Si alguien la usa, la carga falla en tiempo de ejecución.

**Arreglo:** eliminar la entrada. Si se quiere esa página, crearla dentro del rediseño (fase 4).

#### QT‑15: el volumen con botón derecho ignora `qt-max-volume`
- **Ubicación:** `modules/gui/qt/player/qml/controlbarcontrols/VolumeWidget.qml:322‑335`
- **Severidad:** Baja · **Confianza:** Alta

```qml
                    if (pos < 0.25)
                        volControl.value = 0
                    else if (pos < 0.75)
                        volControl.value = 0.5
                    else if (pos < 1.125)
                        volControl.value = 1
                    else
                        volControl.value = 1.25
```

**Explicación:** el rango máximo es configurable entre 60 y 300 % (`qt.cpp:457`), pero estos pasos están fijos hasta 125 %. Con `--qt-max-volume=200` nunca se pasa de 125 %. Con `--qt-max-volume=80` el valor se recorta sin avisar.

**Arreglo:** calcular el valor a partir de `pos` y `root._maxvol / 100`, o redondearlo a las marcas definidas en la especificación de volumen (sección 6.4).

### 3.2 Núcleo (`src/player`, `src/playlist`, `src/input`)

#### CORE‑01: acceso a puntero nulo en `INPUT_CONTROL_SET_SEEKPOINT_PREV`
- **Ubicación:** `src/input/input.c:2383‑2388` (la comprobación de rango está en `:2402`, después del acceso)
- **Severidad:** Alta · **Confianza:** Alta

```c
            int i_title = demux_GetTitle( p_demux );
            int i_seekpoint = demux_GetSeekpoint( p_demux );

            if( i_type == INPUT_CONTROL_SET_SEEKPOINT_PREV )
            {
                vlc_tick_t i_seekpoint_time = priv->master->title[i_title]->seekpoint[i_seekpoint]->i_time_offset;
```

**Explicación:**
- Si el título actual tiene `i_seekpoint == 0`, `seekpoint` vale NULL (`vlc_input_title_New`) y se ejecuta `NULL[0]->i_time_offset`.
- `vlc_player_SelectPrevChapter` (`src/player/player.c:995`) encola la orden sin validar nada.
- Escenario: un Blu‑ray o un MKV con varios títulos, alguno sin capítulos. El usuario pulsa la tecla de «capítulo anterior».

**Arreglo:**
```diff
             int i_seekpoint = demux_GetSeekpoint( p_demux );
+            const input_title_t *t = priv->master->title[i_title];
+            if( t->i_seekpoint <= 0 || i_seekpoint < 0 || i_seekpoint >= t->i_seekpoint )
+                break;
```

#### CORE‑02: `INPUT_EVENT_ATTACHMENTS` se envía con `p_item->lock` tomado
- **Ubicación:** `src/input/input.c:849‑851` (también en `:3115` y `:3313`); el envío está en `:3276‑3279`
- **Severidad:** Alta · **Confianza:** Alta

```c
        vlc_mutex_lock( &priv->p_item->lock );
        AppendAttachment( input, i_attachment, attachment );
        vlc_mutex_unlock( &priv->p_item->lock );
```
```c
        input_SendEvent(p_input, &(struct vlc_input_event) {
            .type = INPUT_EVENT_ATTACHMENTS,
            .attachments = { .array = pp_new, .count = i_new },
        });
```

**Explicación:**
- El manejador del player (`src/player/input.c:1011`) toma `player->lock`, así que aquí el orden es **item → player**.
- En el resto del código el orden es **player → item**:
  - `input_item_SetDuration` en `INPUT_EVENT_TIMES`;
  - `vlc_playlist_Sort`;
  - las lecturas de metadatos desde los callbacks de la interfaz.
- Esto produce dos fallos:
  - **interbloqueo ABBA:** se abre un MKV con adjuntos mientras la interfaz ordena la lista;
  - **autointerbloqueo:** una aplicación libvlc llama a `libvlc_media_get_meta()` desde el callback de adjuntos y vuelve a tomar un mutex no recursivo que su propio hilo ya tiene.

**Arreglo:** que `AppendAttachment` solo modifique el item. El que la llama suelta el lock y después envía el evento:
```c
vlc_mutex_lock(&priv->p_item->lock);
bool ok = AppendAttachment(input, n, arr);   /* sin SendEvent */
vlc_mutex_unlock(&priv->p_item->lock);
if (ok)
    input_SendEvent(input, &(struct vlc_input_event){ .type = INPUT_EVENT_ATTACHMENTS, ... });
```

#### CORE‑03: interbloqueo ABBA en el medidor de sonoridad
- **Ubicación:** `src/player/metadata.c:174‑181` (y `:39`) frente a `src/audio_output/meter.c:189‑203`
- **Severidad:** Alta · **Confianza:** Media en la frecuencia; el orden de locks está verificado

```c
    vlc_mutex_lock(&player->metadata_listeners_lock);

    int ret;
    switch (option)
    {
        case VLC_PLAYER_METADATA_LOUDNESS_MOMENTARY:
        case VLC_PLAYER_METADATA_LOUDNESS_FULL:
            ret = vlc_player_AddMetadataLoudnessListener(player, listener_id);
```
```c
            block_t *same_block = filter->ops->filter_audio(filter, block);
```

**Explicación:**
- Hilo de audio, orden `meter->lock` → `metadata_listeners_lock`: el filtro ebur128 emite `filter_SendAudioLoudness` y llega a `vlc_player_OnLoudnessEvent`.
- Hilo de la interfaz, orden contrario: con `metadata_listeners_lock` tomado llama a `aout_Add/RemoveMeterPlugin`, que toman `meter->lock`.
- Si se añade o quita un listener mientras se procesa un bloque de audio, los dos hilos se bloquean. Como la interfaz tiene además el lock del player, se congela todo el player.

**Arreglo:** llamar a `aout_Add/RemoveMeterPlugin` **fuera** de `metadata_listeners_lock`: preparar el cambio, soltar el lock, aplicar el cambio al plugin y volver a tomarlo para publicar el resultado.

#### CORE‑04: `vlc_playlist_Export` tiene las etiquetas de salida intercambiadas
- **Ubicación:** `src/playlist/export.c:73‑99`
- **Severidad:** Alta · **Confianza:** Alta

```c
    export->file = vlc_fopen(filename, "wt");
    if (!export->file)
    {
        msg_Err(export, "Could not create playlist file %s, %s",
                filename, vlc_strerror_c(errno));
        goto close_file;
    }
```
```c
    if (!module)
    {
        msg_Err(export, "Could not export playlist");
        goto out;
    }
```

**Explicación:**
- Si `fopen` falla, se ejecuta `fclose(NULL)`: comportamiento indefinido, y con glibc una caída.
- Si no hay módulo de exportación, el `FILE*` no se cierra nunca.
- Escenario: exportar la lista a un directorio sin permiso de escritura tumba VLC.

**Arreglo:** cambiar `goto close_file` por `goto out` en la línea 78, y `goto out` por `goto close_file` en la 87. Comprobar además el retorno de `fclose` (ver mejoras).

#### CORE‑05: `vlc_playlist_ItemsRemoved` usa el tamaño ya reducido
- **Ubicación:** `src/playlist/content.c:138‑146`; se llama después de `vlc_vector_remove_slice` (`:319`)
- **Severidad:** Media · **Confianza:** Alta

```c
        if (current >= index && current < index + count) {
            /* current item has been removed */
            if (index + count < playlist->items.size) {
                /* select the first item after the removed block */
                playlist->current = index;
            } else {
                /* no more items */
                playlist->current = -1;
```

**Explicación:** `items.size` ya es el tamaño nuevo. Con la lista [A, B, C] y B en reproducción, al borrar B se evalúa `1 + 1 < 2`, que es falso, así que `current` pasa a −1 y se detiene la reproducción en lugar de pasar a C. Ocurre siempre que detrás del bloque borrado quedan `count` elementos o menos. `test_items_removed_callbacks` (`src/playlist/test.c`) no cubre este caso.

**Arreglo:** `if (index < playlist->items.size)`, más un test con [A, B, C] en el que se borra B.

#### CORE‑06: comparador inconsistente en `CompareOptionalIntegers`
- **Ubicación:** `src/playlist/sort.c:316‑326`
- **Severidad:** Media · **Confianza:** Alta

```c
static inline int
CompareOptionalIntegers(bool has_a, int64_t a, bool has_b, int64_t b)
{
    if (has_a && has_b)
        return CompareIntegers(a, b);

    if (!has_a && !has_b)
        return 0;

    return a ? 1 : -1;
}
```

**Explicación:**
- La última línea mira el valor `a` en lugar de `has_a`.
- Si un elemento tiene el meta con valor 0 (disco «0», rating 0, o una fecha que no se pudo parsear) y el otro no tiene el meta, se cumple a la vez `cmp(x,y) = -1` y `cmp(y,x) = -1`.
- Con un comparador así, el resultado de `qsort` es indefinido.

**Arreglo:** `return has_a ? 1 : -1;`

#### CORE‑07: ordenar por tamaño o fecha de modificación falla entero si falta `.stat`
- **Ubicación:** `src/playlist/sort.c:183‑190` (`mtime` en `:196‑203`) y `:456‑459`
- **Severidad:** Media · **Confianza:** Alta

```c
        case VLC_PLAYLIST_SORT_KEY_FILE_SIZE:
        {
            char *str = input_item_GetInfoLocked(media, ".stat", "size");

            if (str == NULL)
                return VLC_EGENERIC;
```

**Explicación:**
- Si un solo elemento no tiene `.stat` (un stream HTTP, o un elemento que todavía no se ha preanalizado), `meta_New` devuelve NULL.
- Entonces la ordenación entera termina con `VLC_ENOMEM`, un código de error además engañoso.
- Escenario: en una lista con ficheros locales y una radio, «Ordenar por tamaño» no hace nada.

**Arreglo:** añadir los campos `has_file_size` y `has_file_modified`, y comparar con `CompareOptionalIntegers` (una vez corregido CORE‑06). Devolver error solo cuando falle de verdad una reserva de memoria.

#### CORE‑08: ruta de error de `vlc_player_New`
- **Ubicación:** `src/player/player.c:2175‑2182` y `:2200`
- **Severidad:** Media · **Confianza:** Alta

```c
    player->resource = input_resource_New(VLC_OBJECT(player));

    if (!player->resource)
        goto error;

    /* Ensure the player has a valid aout */
    aout = vlc_player_aout_Init(player);
    var_AddCallback(player, "corks", vlc_player_CorkCallback, player);
```
```c
    var_DelCallback(player, "corks", vlc_player_CorkCallback, player);
```

**Explicación:**
- Si se produce un fallo antes de la línea 2182, se salta a `error:` y se borra un callback que todavía no se ha registrado.
- En `src/misc/variables.c:838‑846`, una compilación de depuración se para en un `assert`, y una de release accede a un puntero nulo.
- En todas las rutas de error se pierde además la *cookie jar* creada con `vlc_http_cookies_new()`.

**Arreglo:** añadir un indicador `bool corks_cb` que diga si el callback está registrado, y destruir la *cookie jar* en `error:`.

#### CORE‑09: fuga de `input->ml.states`
- **Ubicación:** `src/player/medialib.c:50‑52`, `:175`, `:197`, `:291` y `:298`
- **Severidad:** Baja · **Confianza:** Alta

```c
void
vlc_player_RestorePlaybackPos(vlc_player_t *player)
{
    vlc_player_input_RestoreMlStates(player->input, true);
}
```

**Explicación:**
- Con `restore-playback-pos=ASK`, la segunda restauración sobrescribe los `char*` de la primera sin liberarlos: `aspect_ratio`, `crop`, `deinterlace`, `video_filter` y los ids de las pistas.
- Las salidas tempranas de `vlc_player_UpdateMLStates` tampoco liberan esos datos.

**Arreglo:**
- Llamar a `vlc_ml_playback_states_all_release(&input->ml.states)` antes de cada `get_all_playback_pref`.
- Llamar también a esa función sin condiciones en `vlc_player_input_Delete`.

#### CORE‑10: fugas en `vlc_player_title_list_Create`
- **Ubicación:** `src/player/title.c:138‑158`
- **Severidad:** Baja (solo sin memoria) · **Confianza:** Alta

```c
            titles->count = title_idx;
            vlc_player_title_list_Release(titles);
```

**Explicación:** el título que está en construcción (con su nombre, su array de capítulos y los nombres ya reservados) queda fuera de la liberación. Además, el bucle de capítulos no se detiene en el primer fallo.

**Arreglo:** hacer `break` en el primer `!chapter->name`, poner `titles->count = title_idx + 1` y ajustar `chapter_count` al número de capítulos inicializados.

#### CORE‑11: se ignora el fallo de `randomizer_Add`
- **Ubicación:** `src/playlist/content.c:64‑66` (también en `:349`) y `control.c:40‑42`
- **Severidad:** Baja (solo sin memoria) · **Confianza:** Alta

```c
    if (playlist->order == VLC_PLAYLIST_PLAYBACK_ORDER_RANDOM)
        randomizer_Add(&playlist->randomizer,
                       &playlist->items.data[index], count);
```

**Explicación:** si falla, los elementos están en la lista pero no en el randomizer. Más tarde, `randomizer_RemoveOne` recibe un índice −1 y solo lo comprueba un `assert`, así que en release el vector queda corrupto.

**Arreglo:** propagar el error y deshacer la inserción, o reservar en el randomizer antes de insertar en la lista.

#### CORE‑12: `vlc_player_aout_Deinit` borra callbacks que no se registraron
- **Ubicación:** `src/player/aout.c:208‑217`
- **Severidad:** Baja · **Confianza:** Media

```c
    var_DelCallback(aout, "volume", vlc_player_AoutCallback, player);
```

**Explicación:** si `aout_New` falla al crear el player y el decoder crea el aout más tarde, los `DelCallback` se ejecutan sobre un aout que nunca registró los callbacks. Ocurre lo mismo que en CORE‑08: `assert` en depuración y puntero nulo en release.

**Arreglo:** guardar (con *hold*) el aout en el que se registraron los callbacks y borrarlos solo de ese.

#### CORE‑13: `ts_interval` truncado a 32 bits
- **Ubicación:** `src/player/timer.c:758`
- **Severidad:** Baja · **Confianza:** Alta

```c
    const unsigned ts_interval = interpolated_ts / next_interval;
```

**Explicación:** con un intervalo de 1 µs se desborda a los 71 minutos aproximadamente, y `libvlc_media_player_time_point_get_next_date` (API pública) devuelve fechas pasadas.

**Arreglo:** declarar la variable como `vlc_tick_t`.

#### CORE‑14: `assert` demasiado permisivo frente a `cat2vars[]`
- **Ubicación:** `src/player/player.c:1917` y `:1937`
- **Severidad:** Baja · **Confianza:** Alta

```c
    assert(cat >= UNKNOWN_ES && cat <= DATA_ES);
```

**Explicación:** `cat2vars[]` solo tiene entradas hasta `SPU_ES`, y la API documenta que solo admite `VIDEO_ES..SPU_ES`. Con `DATA_ES` se lee fuera del array.

**Arreglo:** `assert(cat >= VIDEO_ES && cat <= SPU_ES);`

#### CORE‑15: dos defectos menores en `player.c`
- **Ubicación:** `src/player/player.c:513` y `:978`
- **Severidad:** Baja · **Confianza:** Alta

```c
    if (allocated_ids == NULL || osd_ids == NULL)
```
```c
_("Chapter %ld")
```

**Explicación:**
- Si solo falla una de las dos reservas, la otra se pierde.
- En LLP64 (Windows), `%ld` con un `size_t` es comportamiento indefinido.

**Arreglo:**
- Liberar las dos reservas antes de devolver `0`.
- Usar `%zu`.

### 3.3 Entradas no confiables: subtítulos y listas

> Resumen de lo que sí está bien: en `subtitle.c`, todos los `sscanf("%[^\r\n]")` escriben en búferes de tamaño `strlen(s)+1`; `ParseSSA` usa `%15[^,]` sobre un `temp[16]`; `ParseSami` está acotado a 8192; y `ReadLine` garantiza el terminador NUL. En WebVTT, la recursión está limitada. En `substx3g.c` y `cc.c` los índices están acotados.
>
> No he encontrado desbordamientos en `vobsub.c`, `stl.c`, `pls.c`, `m3u.c`, `podcast.c`, `ifo.c` ni `bdmv.c`. Solo hay accesos nulos cuando falta memoria.

#### SEC‑01: `ram.c` `ParseClipInfo`, lectura y escritura fuera de límites
- **Ubicación:** `modules/demux/playlist/ram.c:401‑410` y `:447`; se llama desde `:270`
- **Severidad:** Alta · **Confianza:** Alta

```c
        psz_option_start = psz_option_next;
        psz_option_next = strchr( psz_option_start, '|' );
        if( psz_option_next )
            *psz_option_next = '\0';
        else
            psz_option_next = strchr( psz_option_start, '"' );
        if( psz_option_next )
            *psz_option_next = '\0';
        else
            psz_option_next = strchr( psz_option_start, '\0' );
```

**Explicación:**
- Cuando la última subopción no se cierra con `|` ni con `"`, `psz_option_next` apunta al terminador NUL del `strdup`.
- El `psz_option_next++` del final del bucle avanza entonces **un byte más allá del bloque**.
- La siguiente iteración ejecuta `strchr` sobre memoria del heap que no le pertenece. Si encuentra `|` o `"`, **escribe `'\0'` fuera del bloque**.
- Cómo se alcanza desde fuera: si `vlc_uri_resolve` falla (por ejemplo, con un puerto no numérico), `ProcessMRL` (`playlist.c:193‑196`) devuelve la cadena original sin sanear.
- Entrada que lo dispara: un `.ram`, incluso remoto, con la línea `http://h:x/a.rm?clipinfo="title=foo` (sin comilla de cierre).

**Arreglo:**
```diff
         else
-            psz_option_next = strchr( psz_option_start, '\0' );
+        {
+            psz_option_next = strchr( psz_option_start, '\0' );
+            last = true;
+        }
 ...
         free( psz_suboption );
+        if( last )
+            break;
         psz_option_next++;
```
De paso, comprobar el `strdup` de la línea 388 y liberar `*ppsz_*` antes de reasignarlos, porque ahora se pierden.

#### SEC‑02: `subsusf.c`, un estilo sin `name` provoca `strcasecmp(NULL, …)`
- **Ubicación:** `modules/codec/subsusf.c:578‑583` (inserción); usos en `:313`, `:445` y `:628`
- **Severidad:** Media (DoS) · **Confianza:** Alta

```c
                        if( !strcasecmp( "style", node ) )
                        {
                            TAB_APPEND( p_sys->i_ssa_styles, p_sys->pp_ssa_styles, p_ssa_style );

                            p_ssa_style = NULL;
                            i_style_level--;
```
```c
            if( !strcasecmp( p_sys->pp_ssa_styles[i]->psz_stylename, "Default" ) )
```

**Explicación:** `psz_stylename` solo se rellena si el elemento tiene el atributo `name`, pero el estilo se añade a la tabla igualmente. Entrada que lo dispara: un MKV con una pista `S_TEXT/USF` cuyo CodecPrivate contiene `<USFSubtitles><styles><style><fontstyle face="x"/></style></styles></USFSubtitles>`, seguida de cualquier bloque `<text>`.

**Arreglo:** al cerrar `</style>`, insertar el estilo solo si `p_ssa_style->psz_stylename != NULL`. En caso contrario, liberarlo.

#### SEC‑03: `b4s.c`, `vlc_xml_decode(NULL)`
- **Ubicación:** `modules/demux/playlist/b4s.c:184‑190`
- **Severidad:** Media (DoS) · **Confianza:** Alta

```c
            case XML_READER_ENDELEM:
            {
                // Read the element name
                if( !strcmp( node, "entry" ) )
                {
                    vlc_xml_decode( psz_mrl );
                    p_input = input_item_New( psz_mrl, psz_title );
```

**Explicación:**
- `psz_mrl` solo se asigna si el elemento tiene el atributo `Playstring`.
- `vlc_xml_decode` (`src/text/strings.c:197`) no comprueba si recibe NULL.
- Entrada que lo dispara: `<WinampXML><playlist><entry></entry></playlist></WinampXML>`.

**Arreglo:** `if( !strcmp( node, "entry" ) && psz_mrl != NULL )`, y comprobar que `p_input` no sea NULL.

#### SEC‑04: `xspf.c`, amplificación de memoria con `<vlc:id>`
- **Ubicación:** `modules/demux/playlist/xspf.c:462‑471`; el valor se lee con `atoi` en `:569‑570`
- **Severidad:** Media (DoS) · **Confianza:** Alta

```c
            if (p_sys->i_track_id >= p_sys->i_tracklist_entries)
            {
                input_item_t **pp;
                pp = realloc(p_sys->pp_tracklist,
                             (p_sys->i_track_id + 1) * sizeof(*pp));
```

**Explicación:** el valor solo está acotado por `INT_MAX - 1`. Un `<vlc:id>500000000</vlc:id>` provoca una reserva de unos 4 GB que además se recorre entera. Una lista remota de pocos bytes basta para agotar la memoria.

**Arreglo:** si el id supera un tope (por ejemplo, 65 536), tratar la pista como si no tuviera id. A largo plazo, guardar las pistas en un mapa indexado por id en lugar de un array denso.

#### SEC‑05: `wpl.c`, nombre de nodo ya liberado o sin inicializar
- **Ubicación:** `modules/demux/playlist/wpl.c:170‑176` y `:225‑227`
- **Severidad:** Baja · **Confianza:** Alta

```c
    i_type = xml_ReaderNextNode( p_reader, &psz_name );
    if ( i_type != XML_READER_ENDELEM || strcasecmp( psz_name, "body" ) )
        msg_Err( p_demux, "Expected closing <body> tag. Got: <%s> with type %d", psz_name, i_type );
```

**Explicación:** `ReaderNextNode` (`modules/misc/xml/libxml.c:143‑153`) libera el nodo anterior y, al llegar a EOF, **no** actualiza `*pval`. Un `.wpl` truncado tras `</seq>` hace que se lea memoria liberada. Uno truncado tras `<body>` hace que se use un puntero sin inicializar.

**Arreglo:** inicializar `psz_name = NULL` y pasar `i_type > 0 ? psz_name : "(eof)"` a `msg_Err`.

#### SEC‑06: `subsdec.c`, coste cuadrático en `AppendCharacter`
- **Ubicación:** `modules/codec/subsdec.c:485‑493`
- **Severidad:** Baja (DoS de CPU) · **Confianza:** Alta

```c
static bool AppendCharacter( text_segment_t* p_segment, char c )
{
    char* tmp;
    if ( asprintf( &tmp, "%s%c", p_segment->psz_text ? p_segment->psz_text : "", c ) < 0 )
        return false;
    free( p_segment->psz_text );
    p_segment->psz_text = tmp;
```

**Explicación:** por cada byte se reserva y se copia la cadena entera. Una entrada SRT de 1 MB sin líneas vacías bloquea el hilo del decodificador durante minutos.

**Arreglo:** acumular con `struct vlc_memstream` y volcar el texto en cada cambio de estilo. Opcionalmente, limitar cada bloque a 64 KB.

#### SEC‑07: `ProcessMRL` no aplica ninguna política de origen
- **Ubicación:** `modules/demux/playlist/playlist.c:149‑153` y `:193‑196`
- **Severidad:** Media · **Confianza:** Media (es un problema de diseño; no se ha verificado en Windows)

```c
    if (strncmp(str, "\\\\", 2) == 0
    /* Drive letter prefix? */
     || (isalpha((unsigned char)str[0]) && str[1] == ':'))
        /* Assume this an absolute file path - usually true */
        return vlc_path2uri(str, NULL);
```
```c
        if (scheme_end &&
            strspn (orig, valid_chars) == (size_t)(scheme_end - orig))
        {
            abs = strdup (orig);
```

**Explicación:**
- Una lista servida por HTTP puede apuntar a `file:///…` o a `\\host\share`. En Windows, esto último abre una conexión SMB y puede filtrar el hash NTLM.
- El fallback `strdup(orig)` entrega URIs sin normalizar y es la causa raíz de SEC‑01.
- `qtl.c`, `wms.c`, `sgimb.c`, `itml.c` y el `ENTRYREF` de `asx.c` no pasan por `ProcessMRL`.

**Arreglo:**
- Pasar a `ProcessMRL` el origen de la lista. Si la base no es `file://`, rechazar o pedir confirmación para destinos `file:`, rutas absolutas o UNC.
- Normalizar el fallback con `vlc_uri_fixup`.
- Hacer que todos los módulos usen `ProcessMRL`.

#### SEC‑08: `asx.c`, fugas y `ENTRYREF` con la condición invertida
- **Ubicación:** `modules/demux/playlist/asx.c:282‑285` (también en `:245` y `:729`) y `:756‑764`
- **Severidad:** Baja · **Confianza:** Alta

```c
                while( psz_tmp && !strncasecmp( psz_tmp, "HREF", 4 ) );
                if( ! psz_tmp )
                    break;
```

**Explicación:**
- Cada `<REF>` repetido sobrescribe `psz_href` sin liberarlo.
- En `ENTRYREF`, el bucle se detiene en el primer atributo que **no** es `HREF`, y ese valor se usa como MRL sin pasar por `ProcessMRL`.

**Arreglo:**
- Llamar a `free()` antes de cada reasignación.
- Quitar el `!` de la condición.
- Pasar el valor por `ProcessMRL`.
- Comprobar que `input_item_New` no devuelve NULL.

#### SEC‑09: `subtitle_cmp`, desbordamiento con signo
- **Ubicación:** `modules/demux/subtitle.c:915‑920`
- **Severidad:** Baja · **Confianza:** Alta (sobre el comportamiento indefinido)

```c
    vlc_tick_t result = ((subtitle_t *)(first))->i_start - ((subtitle_t *)(second))->i_start;
```

**Explicación:** las horas negativas o enormes (`%d` en SRT, `llroundf` en JSS y MPSub) hacen que la resta desborde `int64`. El comparador deja de ser transitivo.

**Arreglo:** `return (a > b) - (a < b);`, y acotar h, m y s en los parsers.

#### SEC‑10: `scte27.c`, reensamblado sin límite
- **Ubicación:** `modules/codec/scte27.c:456‑461`
- **Severidad:** Baja · **Confianza:** Media

```c
            sys->segment_buffer = xrealloc(sys->segment_buffer,
                                           sys->segment_size + segment_size);
```

**Explicación:** no se exige que `index` sea secuencial ni hay un tope de tamaño. Repetir `index=1` hace crecer el búfer sin fin, hasta que `xrealloc` aborta el proceso.

**Arreglo:**
- Exigir `index == prev + 1`.
- Poner un tope a `segment_size` y usar `size_t`.
- Usar `realloc` comprobando el resultado, en lugar de `xrealloc`.

#### SEC‑11: `wms.c`, se comparan 11 bytes sobre un peek de 10
- **Ubicación:** `modules/demux/playlist/wms.c:76‑78`
- **Severidad:** Baja · **Confianza:** Alta

```c
    if (vlc_stream_Peek(demux->s, &peek, 10) < 10
     || strncmp((const char *)peek, "[Reference]", 11))
```

**Arreglo:** `vlc_stream_Peek(..., 11) < 11 || memcmp(peek, "[Reference]", 11)`.

### 3.4 Accesibilidad e internacionalización

#### A11Y‑01: botones CSD sin nombre accesible
- **Ubicación:**
  - `modules/gui/qt/widgets/qml/CSDWindowButton.qml:27‑68`;
  - `CSDThemeButton.qml:28‑53`;
  - instancias en `CSDWindowButtonSet.qml:58`;
  - el mismo patrón en `medialibrary/qml/Bookmarks.qml:92‑103`.
- **Severidad:** Alta · **Confianza:** Alta

```qml
T.Button {
    id: control
    ...
    property string iconTxt: ""
    ...
    focusPolicy: Qt.NoFocus
```

**Explicación:** el único contenido del botón es un glifo de la fuente de iconos, que está marcado con `Accessible.ignored: true` en `IconLabel.qml`. NVDA, Orca o VoiceOver anuncian «botón» tres veces y no se sabe cuál cierra la ventana.

**Arreglo:** en `CSDWindowButtonSet.qml`:
```diff
+            Accessible.name: {
+                switch (modelData.type) {
+                case CSDButton.Minimize: return qsTr("Minimize")
+                case CSDButton.MaximizeRestore:
+                    return MainCtx.intfMainWindow.visibility === Window.Maximized ? qsTr("Restore") : qsTr("Maximize")
+                case CSDButton.Close: return qsTr("Close")
+                }
+            }
```
En `Bookmarks.qml`, añadir `Accessible.name: model.name`.

#### A11Y‑02: en las tablas no se puede abrir el menú contextual con el teclado

> **Corrección (fase 2):** la tecla Menú sí funciona cuando la fila tiene el foco de teclado (`TableViewDelegateExt.qml:115`). Lo que se mantiene es lo demás: el botón «…» solo era visible con el ratón y Mayús+F10 no está atendido. Ver la sección 7.2.
- **Ubicación:** `modules/gui/qt/widgets/qml/TableViewDelegateExt.qml:306‑344`
- **Severidad:** Alta · **Confianza:** Alta

```qml
                description: qsTr("Menu")

                visible: delegate.hovered
```
```qml
                activeFocusOnTab: false
```

**Explicación:**
- El botón «…» solo se ve con el ratón encima y no está en el orden de tabulación.
- El delegado no atiende la tecla Menú ni Mayús+F10. `GridItem.qml:99` y `PlaylistDelegate.qml:109` sí lo hacen.
- Resultado: en vista de lista, quien usa solo el teclado no puede llegar a «Añadir a lista», «Información» ni «Eliminar».

**Arreglo:** añadir `Keys.onMenuPressed: contextButton.clicked()` en el delegado y mostrar el botón también con `delegate.visualFocus`. Mejor aún, centralizar esto en `ListViewExt` y `TableViewExt` (ver mejoras).

#### A11Y‑03: filas sin rol ni estado de selección
- **Ubicación:** `modules/gui/qt/playlist/qml/PlaylistDelegate.qml:31‑40` y `modules/gui/qt/widgets/qml/TableViewDelegateExt.qml:28`
- **Severidad:** Media · **Confianza:** Media (el rol por defecto depende de la versión de Qt)

```qml
    Accessible.name: title
```

**Explicación:** son `T.Control` sin `Accessible.role` y sin `Accessible.selected`. En las tablas, ni siquiera tienen nombre. El modelo correcto es `GridItem.qml:94‑96`.

**Arreglo:** usar `Accessible.role: Accessible.ListItem` en la cola y `Accessible.Row` en las tablas, y añadir `Accessible.selected: delegate.selected` y `Accessible.onPressAction`.

#### A11Y‑04: el estado de silencio, grabación y repetición solo se ve por el icono o el color
- **Ubicación:** `.../controlbarcontrols/VolumeWidget.qml:65‑77`, `RecordButton.qml:32‑48` y `LoopButton.qml:28‑33`
- **Severidad:** Media · **Confianza:** Alta

```qml
    color: "#FFFF0000" //red means recording
    text: VLCIcons.record
    description: qsTr("record")
```

**Explicación:**
- «Mute» siempre se anuncia como «Mute», sin propiedad `checked`.
- El botón de grabar es siempre rojo; solo parpadea mientras graba.
- La repetición tiene tres estados (ninguno, todo, una), pero solo expone un booleano.

**Arreglo:**
- En silencio y grabación, usar `checkable` y `checked` ligados a `Player.muted` y `Player.recording`.
- Cambiar `description` según el estado: «Unmute», «Stop recording», «Repeat one» / «Repeat all» / «Repeat off».

#### A11Y‑05: contraste insuficiente en la paleta clara
- **Ubicación:**
  - `modules/gui/qt/style/systempalette.cpp:495`, `:498` y `:513` (conjunto View, paleta clara);
  - `:595‑599` (ButtonAccent);
  - `dialogs/help/help.cpp:95` y `:117‑124` (colores HTML fijos).
- **Severidad:** Alta · **Confianza:** Alta (calculado con la fórmula de contraste WCAG)

```cpp
        setColor(CS, C::Fg, C::Positive, C::Normal, Qt::green);
```
```cpp
        setColor(CS, C::Fg, C::Link, C::Normal, orange800 /* accent */);
```

| Texto | Fondo | Uso | Contraste (mínimo AA: 4,5) |
|---|---|---|---|
| `#00FF00` | `#EDEDED` | «Versión nueva» en `UpdatePane.qml` | **1,17:1** |
| `#FF0000` | `#EDEDED` | «Error» en `UpdatePane.qml` | 3,4:1 |
| `#FF610A` | `#FAFAFA` | enlaces | **2,9:1** |
| blanco | `#FF610A` | botones de acento | **3,0:1** |

**Explicación:** además, en «Acerca de» el título usa `color:#353535` fijo, que se vuelve casi invisible con el tema oscuro.

**Arreglo:**
- `Positive`: `#0F7B0F` (ya se usa en Slider).
- `Negative`: `#C42B1C`.
- `Link` en la paleta clara: `#B54100` o más oscuro.
- Texto de ButtonAccent en la paleta clara: oscuro.
- En `help.cpp`, quitar los colores fijos y usar la `QPalette`.

#### A11Y‑06: en «Acerca de», las etiquetas que hacen de botón solo responden al ratón
- **Ubicación:** `modules/gui/qt/dialogs/help/help.cpp:144‑166` y `about.ui:299`, `:312`, `:325`
- **Severidad:** Media · **Confianza:** Alta

```cpp
        else if( obj == ui.licenseButton )
            showLicense();
```

**Explicación:** son `QLabel` que solo responden a `MouseButtonPress`. Con el teclado o un lector de pantalla no se puede abrir la licencia GPL ni los créditos.

**Arreglo:** cambiarlos por `QPushButton` planos (`flat`) conectados a `clicked`.

#### A11Y‑07: la interfaz QML no se refleja en idiomas RTL
- **Ubicación:** `modules/gui/qt/qt.cpp:956‑958`; ningún `.qml` usa `LayoutMirroring`; `player/qml/SliderBar.qml:47‑51`
- **Severidad:** Alta para los usuarios de idiomas RTL · **Confianza:** Media

```cpp
    /* Set application direction to locale direction,
     * necessary for  RTL locales */
    app.setLayoutDirection(QLocale().textDirection());
```

**Explicación:**
- `setLayoutDirection` refleja los Widgets clásicos, pero **no** los `Row`, `RowLayout` ni los anclajes de Qt Quick. Para eso hace falta `LayoutMirroring.enabled`.
- Los usuarios de árabe, hebreo o persa ven los diálogos reflejados y la ventana principal de izquierda a derecha.
- Además, `QLocale()` es la configuración regional del sistema, no el idioma elegido en VLC.

**Arreglo:**
- En la raíz `MainInterface.qml`:
  ```diff
  +    LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
  +    LayoutMirroring.childrenInherit: true
  ```
- En `SliderBar.qml`, invertir `Keys.onLeft/RightPressed` cuando el reflejo esté activo.
- Calcular la dirección a partir del idioma de la traducción cargada.

#### I18N‑01: Meson no extrae `qsTr`, y faltan archivos en `POTFILES.in`
- **Ubicación:** `po/meson.build:6‑17` comparado con `po/Makevars:13`; `po/POTFILES.in`
- **Severidad:** Alta · **Confianza:** Alta

```meson
	args: [
		'--keyword=_',
		'--keyword=N_',
		'--keyword=_NS',
		'--keyword=qtr',
		'--keyword=Q_',
		'--language=C++',
```

**Explicación:**
- `Makevars` (autotools) declara `--keyword=qsTr:1,1t --keyword=qsTr:1,2,3t --keyword=qtr:1,2,3t`. Meson no declara ninguna de las tres.
- Toda la interfaz QML usa `qsTr` (unas 490 llamadas). Un `.pot` generado con Meson **pierde todas esas cadenas y los plurales**.
- Además, tres archivos que se compilan y contienen `qtr()` no están en `POTFILES.in`:
  - `modules/gui/qt/dialogs/systray/systray.cpp`;
  - `modules/gui/qt/maininterface/navigationmodel.cpp` (la barra lateral);
  - `modules/gui/qt/playlist/playlist_controller_p.hpp` (los criterios de ordenación).

**Arreglo:**
```diff
 		'--keyword=qtr',
+		'--keyword=qtr:1,2,3t',
+		'--keyword=qsTr:1,1t',
+		'--keyword=qsTr:1,2,3t',
```
Añadir los tres archivos a `POTFILES.in`. Añadir también una comprobación en la CI (ver mejoras).

#### I18N‑02: plurales hechos a mano o ausentes
- **Ubicación:** `modules/gui/qt/medialibrary/qml/VideoAllSubDisplay.qml:98‑109`, `:185` y `:244`; `modules/gui/qt/dialogs/plugins/plugins.cpp:970`
- **Severidad:** Media · **Confianza:** Alta

```qml
                    return videoAll.getLabelGroup(model, qsTr("%1 Videos"))
```
```cpp
                           Qt::AlignLeft, qtr("%1 downloads").arg( i_downloads ) );
```

**Explicación:**
- Se decide el plural con `count === 1`, y hay una sola forma para todos los demás valores.
- Ruso, polaco, árabe y otras lenguas tienen entre 3 y 6 formas de plural, que no se pueden expresar así.
- En inglés sale «1 downloads».

**Arreglo:** usar `qsTr("%1 video", "%1 videos", n)` y `qtr("%1 download", "%1 downloads", n)`, como ya hace `MusicAlbumsGridExpandDelegate.qml:70`.

#### I18N‑03: concatenaciones y HTML dentro de cadenas traducibles
- **Ubicación:**
  - `modules/gui/qt/dialogs/plugins/plugins.cpp:1127`, `:1150` y siguientes;
  - `dialogs/gototime/gototime.cpp:55`;
  - `dialogs/vlm/vlm.cpp:506` y `:579`;
  - `medialibrary/qml/VideoInfoExpandPanel.qml:204` y `:221`;
  - `maininterface/qml/UpdatePane.qml:85` y `:94`.
- **Severidad:** Media · **Confianza:** Alta

```cpp
    setWindowTitle( qtr( "About" ) + " " + index.data(Qt::DisplayRole).toString() );
```
```cpp
    QLabel *timeIntro = new QLabel( qtr( "Go to time" ) + ":" );
```

**Explicación:**
- La concatenación fija el orden de las palabras. Así no se puede escribir «À propos de X» ni el orden japonés «Xについて».
- No se puede adaptar la puntuación: el espacio fino antes de «:» en francés o el signo de dos puntos chino «：».
- En `VideoInfoExpandPanel`, el nombre de archivo se inserta en `StyledText` sin escapar.

**Arreglo:**
- Usar `qtr("About %1").arg(name)` y `qtr("Go to time:")`.
- Escribir `qsTr("<b>File Name:</b> %1").arg(escape(fileName))`.
- En `UpdatePane`, sacar el color fuera de la cadena traducible.

#### I18N‑04: números con formato fijo y análisis que depende de la longitud de la traducción
- **Ubicación:**
  - `modules/gui/qt/player/qml/TracksPageAudio.qml:36‑42`;
  - `TracksPageSubtitle.qml:36‑50`;
  - `controlbarcontrols/PlaybackSpeedButton.qml:74`;
  - `TracksListPage.qml:53`;
  - `network/qml/ServicesManage.qml:172‑174`.
- **Severidad:** Media · **Confianza:** Alta

```qml
    function textFromValue(value, locale) {
        return qsTr("%1 ms").arg(Number(value).toLocaleString(locale, 'f', 0))
    }

    function valueFromText(text, locale) {
        return Number.fromLocaleString(locale, text.substring(0, text.length - 3))
    }
```

**Explicación:**
- `valueFromText` da por hecho que la traducción de «%1 ms» acaba en exactamente 3 caracteres. Con «%1 мс» y un espacio fino, o con «ms %1», el resultado es `NaN` y el spinbox de retardo deja de aceptar valores tecleados.
- `toFixed()` siempre escribe «1.25x», incluso donde el separador decimal es la coma.

**Arreglo:**
- Extraer el número quitando el prefijo y el sufijo que se obtienen con `qsTr("%1 ms").split("%1")`.
- Formatear con `toLocaleString(Qt.locale(), 'f', 2)`.

#### I18N‑05: mayúsculas incoherentes y cadenas casi duplicadas
- **Ubicación:**
  - `.../controlbarcontrols/FullscreenButton.qml:32` (`"fullscreen"`), frente a `"Fullscreen"` en `PlayerControlbarControls.qml:40`;
  - `RecordButton.qml:34` (`"record"`);
  - `dialogs/dialogs/qml/Dialogs.qml:372` (`text: qsTr("cancel")`, visible en un botón);
  - `util/vlctick.cpp:100‑143`, donde conviven `"%1 sec"`, `"%1 s"`, `"%1 ms"` y `"%1ms"`.
- **Severidad:** Baja · **Confianza:** Alta

```qml
                        text: qsTr("cancel")
```

**Explicación:** los traductores reciben dos `msgid` que solo se diferencian en las mayúsculas. En inglés, el botón aparece como «cancel».

**Arreglo:** unificar con mayúscula inicial y una sola forma para cada unidad: `"%1 s"` y `"%1 ms"`.

#### A11Y‑08: animaciones infinitas sin opción de reducir el movimiento
- **Ubicación:** `modules/gui/qt/widgets/qml/TextAutoScroller.qml:54‑57`, `RecordButton.qml:46‑60` y `style/VLCStyle.qml:280‑290`
- **Severidad:** Baja · **Confianza:** Alta

```qml
    SequentialAnimation {
        id: scrollAnimation

        running: root.forceScroll && root._needsToScroll
        loops: Animation.Infinite
```

**Explicación:** no hay ningún ajuste global para reducir el movimiento. WCAG 2.2.2 exige que se pueda pausar el contenido que se mueve.

**Arreglo:**
- Crear una opción `qt-reduce-motion` y exponerla como `VLCStyle.reduceMotion`.
- Cuando esté activa, poner `duration_* = 0` y no lanzar las animaciones infinitas.

#### A11Y‑09: tamaños fijos que no siguen la escala de la interfaz
- **Ubicación:**
  - `modules/gui/qt/dialogs/toolbar/qml/ToolbarEditorDialog.qml:31‑35`;
  - `playlist/qml/PlaylistDetachedWindow.qml:34`;
  - `widgets/qml/TextFieldExt.qml:49‑50`.
- **Severidad:** Baja · **Confianza:** Media

```qml
    minimumWidth: 825
```

**Arreglo:** usar `VLCStyle.dp(…, VLCStyle.scale)`.

---

## 4. Mejoras recomendadas (no son bugs)

**Calidad y robustez**
1. **Fuzzing de listas y subtítulos.**
   - `test/src/input/demux-run.c` no incluye `demux_playlist`, `vobsub` ni `stl`. Además usa la URL `vlc://nop`, así que los probes que dependen de la extensión (`.ram`, `.b4s`, `.wpl`, `.xspf`, `.asx`…) nunca se activan.
   - Propuesta:
     - un objetivo `vlc-demux-libfuzzer-playlist` con una URL ficticia por extensión;
     - objetivos que llamen directamente a los decodificadores `subsdec`, `subsusf`, `substx3g`, `webvtt` y `ttml`;
     - compilar con ASan y UBSan;
     - usar como corpus semilla los casos de SEC‑01 a SEC‑05.
2. **Patrón XML seguro:** no usar `node` cuando `xml_ReaderNextNode() <= 0`, y hacer que `vlc_xml_decode` tolere NULL.
3. **Concatenaciones O(n²):** cambiar a `vlc_memstream` en `subsdec.c`, en `webvtt.c` (`asprintf("%s\n%s")`) y en `tt_bsearch_Insert`.
4. **Límites globales:** un tope de bytes en `TextLoad` (`subtitle.c` y `vobsub.c`) y otro por bloque de texto.
5. **Valores de retorno que se pierden:**
   - `fclose` en `export.c:98`;
   - `vlc_player_Set{Category,EsId}Delay`, que siempre devuelve `VLC_SUCCESS`;
   - `vlc_vector_push` en `preparse.c:43` y `item.c:1092`.
6. **Otros defectos menores:**
   - `vlc_playlist_RequestRemove` (`request.c:72‑91`) no elimina índices duplicados;
   - `vlc_playlist_Remove` debería comprobar con un `assert` que `index + count <= size`;
   - `item.c:1074` tiene un `unlikely` donde debería ir `likely`.
7. **Qt: conexiones sin objeto de contexto.**
   - Hay `connect` con lambdas que capturan `this` pero no pasan un objeto de contexto, en `extended_panels.cpp:1560‑1574` y `mainctx.cpp:859`. El de `mainctx.cpp` además se acumula en cada `onWindowClose`.
   - En `renderer_manager.cpp:373‑379`, hay que indicar explícitamente `Qt::QueuedConnection`.
8. **Qt: modelos.**
   - `networkdevicemodel.cpp:250‑273`: desconectar antes de llamar a `m_sourcesProvider.reset()`.
   - `audio_device_model.cpp:42‑53`: la lista de dispositivos no se actualiza al conectar o desconectar uno. Además, si `aout_DevicesList` falla, se puede producir un *double free*.
   - `dialogs_provider.cpp:433‑468`: el `m_parser` es compartido entre peticiones de información.

**Accesibilidad e i18n**

9. **Comprobación de accesibilidad en la CI:** fallar si un `T.AbstractButton` o un `T.Control` interactivo no tiene `Accessible.name`, `description` ni `text`. `IconToolButton.qml:81` ya tiene un `console.assert` parecido.
10. **Componente común para los botones de dos estados:** que exponga `checkable` y `checked`, y un nombre que dependa del estado.
11. **Tecla Menú y Mayús+F10 en un solo sitio:** gestionarlas en `ListViewExt` y `ExpandGridView`, no en cada delegado.
12. **Barra de progreso accesible:** `SliderBar` debería anunciar «1:23 de 4:56», no un porcentaje.
13. **Contraste y alto contraste:**
    - comprobar con un script cada par de colores de texto y fondo de `systempalette.cpp`, también con `qt-accent-color`;
    - respetar el modo de alto contraste del sistema.
14. **`POTFILES.in` y `.pot` generados.** La CI debería comprobar con `grep 'qtr(\|qsTr(\|_("\|N_("'` que todos los archivos estén en `POTFILES.in`. El `po/vlc.pot` versionado tiene fecha `POT-Creation-Date: 2017-12-06`.
15. **Comentarios para traductores:** `//:` en QML y `/* xgettext: */` en C++ para las cadenas ambiguas («MC», «%1x», «Score»). El `Translator` de `qt.cpp:550‑569` ignora la desambiguación.

**Interfaz (preparación del rediseño)**

16. **Valores fijos en el código:**
    - `PlayButton.qml:263‑266` tiene el degradado fijo `#e25b01 → #f89a06`;
    - `color_svg_image_provider.cpp:36` usa `#FF8800` fijo;
    - `VolumeWidget.qml:101` tiene un `dp(100)` marcado como «FIXME».
17. **`qmllint` en la CI:** hoy no se usa en ningún sitio. Hay una única prueba QML: `tests/tst_FSM.qml`.

---

## 5. Mapa de la interfaz para el rediseño

Rutas relativas a `modules/gui/qt/`. Los valores están en dp: `VLCStyle.dp(px) = round(px × MainCtx.intfScaleFactor)`.

### 5.1 Barra de controles

| Pieza | Archivo | Detalles actuales |
|---|---|---|
| Contenedor | `player/qml/ControlBar.qml` | Un `T.Pane` que contiene, en columna, la fila de tiempos, el `SliderBar` y el `PlayerControlLayout`. `sliderHeight: VLCStyle.heightBar_xxsmall` (4 dp) en l.52. `textPosition` (`Hide`, `AboveSlider`, `LeftRightSlider`). Fondo `Window bg.primary`. |
| Instancias | `player/qml/Player.qml:1282`, `player/qml/MiniPlayer.qml:27` | `identifier`: `Videoplayer`, `Audioplayer` o `Miniplayer`. Sobre vídeo se fuerza `VLCStyle.darkPalette`. |
| Disposición | `player/qml/PlayerControlLayout.qml`, `ControlLayout.qml`, `ControlRepeater.qml` | Tres `Loader` (izquierda, centro, derecha). El modelo sale de `MainCtx.controlbarProfileModel.currentModel.getModel(identifier)`. |
| Catálogo de controles | `player/qml/PlayerControlbarControls.qml:32‑73` | Tabla de id → archivo, icono y texto. Hay 45 controles en `player/qml/controlbarcontrols/`. |
| Modelo C++ | `player/control_list_model.hpp:39‑110`, `player/player_controlbar_model.hpp` | Enum `ControlType`. **Los valores nuevos solo se pueden añadir al final**, porque se guardan en la configuración del usuario. |
| Perfiles | `dialogs/toolbar/controlbar_profile_model.cpp` | Default, Minimalist, One‑liner, Simplest y Classic. Se guardan en `QSettings`, grupo `ControlbarProfileModel`. |
| Editor | `dialogs/toolbar/qml/ToolbarEditorDialog.qml` y otros | Herramientas → «Personalizar interfaz» (`menus/menus.cpp:270`). |
| Play/pausa | `controlbarcontrols/PlayButton.qml` | Círculo de 48 dp (`icon_medium`) con un degradado fijo `#e25b01 → #f89a06` (l.263‑266) y un círculo interior blanco. Si se mantiene pulsado, detiene la reproducción. |
| Anterior y siguiente | `PreviousButton.qml`, `NextButton.qml` | `Widgets.IconToolButton`. El glifo mide 24 dp (`icon_toolbar`). |
| Progreso | `player/qml/SliderBar.qml` | `barHeight` es 5 dp por defecto y 4 dp en la barra. En hover crece ×1,8 (capítulos). Fondo `Slider bg.primary`, progreso `fg.primary` (el color de acento), buffer `fg.neutral` con α 0,4. Cabezal circular de 12 dp, visible solo en hover o con foco. Capítulos como segmentos separados 2 dp. Tooltip con el tiempo y el capítulo. |
| Volumen | `controlbarcontrols/VolumeWidget.qml` + `widgets/qml/SliderExt.qml` | Botón de silencio más una pista recta de 4 dp y 100 dp de ancho. El color pasa a `fg.negative` por encima del 100 %. Hay una marca en el 100 %. El máximo viene de `qt-max-volume` (**125** por defecto, rango 60‑300, `qt.cpp:457`). |

### 5.2 Temas, colores y tipografía

| Pieza | Archivo | Detalles |
|---|---|---|
| Tamaños | `style/VLCStyle.qml` | Fuentes de 6 a 24 dp (normal 12, large 14, xlarge 16); márgenes de 2 a 36; iconos de 8 a 128; radios (`button_radius` 4); duraciones de 50 a 400 ms. **No hay familia tipográfica.** |
| Contexto de color | `style/colorcontext.hpp/.cpp` | `ColorContext` con conjuntos de colores (`View`, `Window`, `Item`, `ButtonStandard`, `ButtonAccent`, `ToolButton`, `TabButton`, `MenuBar`, `Tooltip`, `Slider`, `ComboBox`, `SpinBox`, `TextField`, `Switch`, `Badge`), estados (`Normal`, `Disabled`, `Pressed`, `Hovered`, `Focused`) y la API `bg.*`, `fg.*`, `border`, `separator`, `accent`, `visualFocus`. |
| Paletas | `style/systempalette.cpp/.hpp` | `makeLightPalette()` (l.472) y `makeDarkPalette()` (l.686). Constantes: `orange500 #FF8800`, `orange800 #FF610A`, `darkGrey200 #1E1E1E` … `darkGrey800 #303030`. La ventana oscura es **negra**. Un color que no se encuentra se pinta en magenta. |
| Esquema | `util/color_scheme_model.cpp` | `System`, `Day` o `Night`. Se guarda en `QSettings` `MainWindow/color-scheme-index`. Con Qt ≥ 6.8 se sincroniza con `QStyleHints`. |
| Proveedores del sistema | `style/windowsthemeprovider.cpp`, `style/gtkthemeprovider/`, `style/systempalettethemeprovider.cpp` | Solo se usan en el modo `System`. |
| Color de acento | `--qt-accent-color` (`qt.cpp:480`) | `default`, `system` (Qt ≥ 6.6) o `#RRGGBB`. Se aplica en `systempalette.cpp:305‑332`. |
| Fuentes | `style/vlcicons.cpp:9‑14`, `assets.qrc:101‑103` | Solo se carga `VLCIcons.ttf`. No hay `FontLoader` ni `font.family` global. La raíz QML es un `Item` y no un `ApplicationWindow`, así que no hay una fuente que se herede. |

### 5.3 Menús

- **Todos son `QMenu` nativos.** Están en `menus/menus.cpp`, que define la barra de menús (Medio, Reproducción, Vídeo, Audio, Subtítulos, Herramientas, Ver, Ayuda) y los `PopupMenu*`, y en `menus/custom_menus.*`.
- Para usarlos desde QML existen envoltorios en `menus/qml_menu_wrapper.*`: `QmlMenuBar`, `QmlGlobalMenu`, `SortMenu`, `PlaylistContextMenu`, `NetworkMediaContextMenu`…
- La barra de menús visual en QML es `menus/qml/Menubar.qml`, incluida desde `maininterface/qml/MenuTopbar.qml`.
- El menú contextual de la biblioteca es `util/qml/NativeMenu.qml` → `medialibrary/qml/MLContextMenu.qml`.

### 5.4 Barra lateral y biblioteca

| Pieza | Archivo | Detalles |
|---|---|---|
| Páginas | `maininterface/qml/MainDisplay.qml:107‑129` | `home`, `video`, `music`, `network`, `discover` y `mlsettings` (esta última no tiene archivo, ver QT‑14). |
| Barra lateral | `maininterface/qml/SideNavigationPane.qml`, `SideNavigationDelegate.qml`; modelo en `maininterface/navigationmodel.cpp:262‑294` | Inicio · Vídeo (Todo, Listas) · Música (Artistas, Álbumes, Pistas, Géneros, Listas) · Explorar · Descubrir. Ancho expandido: 160 dp. |
| Historial | `util/navigation_history.hpp` | Singleton `History` (`push`, `previous`, `viewPath`). |
| Inicio | `medialibrary/qml/HomeDisplay.qml`, `HomePage.qml` | Ya muestra lo reciente y «continuar viendo». Es la base de «Recientes». |
| Cuadrícula y lista | `maininterface/qml/MainViewLoader.qml`, `widgets/qml/ExpandGridView.qml`, `GridItem.qml`, `TableViewExt.qml` | `MainCtx.gridView` elige entre cuadrícula y lista. |
| Orden y búsqueda | `widgets/qml/PageExt.qml` (`SearchCtx`, `SortCtx`), `widgets/qml/GridSortFilterControls.qml` | Cada vista define su `sortModel` y enlaza `searchPattern`, `sortCriteria` y `sortOrder`. |
| Migas de pan | `network/qml/NetworkAddressbar.qml`, `BrowseTreeHeader.qml:76` | **Solo existen en la navegación de red.** |
| Cola | `playlist/qml/PlaylistPane.qml` | Ancho por defecto 300 dp y máximo 400 dp. |

### 5.5 Diálogos

- **QML:** `dialogs/dialogs/qml/Dialogs.qml` gestiona los diálogos de error, login, progreso, pregunta y personalizados, y carga el editor de la barra. También están en QML `ModalDialog.qml`, `WindowDialog.qml` y `player/qml/ResumeDialog.qml`.
- **Qt Widgets:**
  - preferencias (`dialogs/preferences/`, simples y avanzadas; las avanzadas tienen un filtro de búsqueda);
  - información multimedia (`dialogs/mediainfo/`);
  - ajustes extendidos (`dialogs/extended/`);
  - abrir (`dialogs/open/`);
  - acerca de (`dialogs/help/`);
  - además: mensajes, marcadores, EPG, extensiones, convertir/emitir y VLM.
- **Asistente de primer arranque:** `dialogs/firstrun/firstrunwizard.cpp/.ui`. Es un `QWizard` con estas páginas:
  - bienvenida y privacidad;
  - carpetas;
  - **esquema de color** (Sistema, Claro, Oscuro);
  - disposición (Moderna o Clásica).

  Se lanza si `qt-privacy-ask` está activado.

### 5.6 Iconos

- Fuente de iconos `pixmaps/VLCIcons.ttf`, generada con `pixmaps/makeIconFont.py` (necesita fontforge) a partir de `pixmaps/VLCIcons.json` y de los SVG de `pixmaps/icons/`. El mismo script regenera `style/vlcicons.hpp/.cpp`. **No hay que editar esos archivos a mano.**
- Los SVG que se colorean en tiempo de ejecución usan `image://svgcolor` (`util/color_svg_image_provider.cpp`) y `util/colorizedsvgicon.*`.

### 5.7 Menú de pistas

- `player/qml/TracksMenu.qml`: un `T.Popup` de 296 dp de alto con un `StackView`. Se abre desde `controlbarcontrols/LangButton.qml:63`.
- `TracksListPage.qml` muestra tres columnas: Subtítulos, Audio y Vídeo.
- Hay subpáginas para el retardo de audio (`TracksPageAudio.qml`), el retardo y los FPS de subtítulos (`TracksPageSubtitle.qml`) y la velocidad (`TracksPageSpeed.qml`).

### 5.8 Compilación, ejecución y pruebas de la parte QML

- **Qt mínimo:** 6.2 (`configure.ac:4322`, `meson.build:14‑22`).
- **Registrar un QML nuevo:**
  - Hay que añadirlo **en los dos sistemas de compilación**:
    - en `modules/gui/qt/meson.build:605‑960` (`qml_modules`, `sources` y `singletons`);
    - en `modules/gui/qt/Makefile.am:1003‑1400` (`libqml_module_<x>_a_QML` y `_Singleton_QML`).
  - Los `qrc` y `qmldir` se generan con `scripts/genqrc.py` y `scripts/genqmldir.py`.
  - Los recursos que no son QML (fuentes, imágenes) van en `assets.qrc` y en `libqt_plugin_la_RES` (`Makefile.am:792`).
- **Compilar solo lo necesario (Meson):**
  ```sh
  meson setup build -Dqt=enabled
  ninja -C build modules/gui/qt/libqt_plugin.so
  ```
- **Pruebas:**
  ```sh
  meson test -C build --suite qt        # QTest + tst_FSM.qml (QT_QPA_PLATFORM=offscreen)
  make -C modules/gui/qt check          # equivalente con autotools
  ```
- **Ejecutar:**
  ```sh
  ./build/vlc -I qt --no-qt-privacy-ask
  ```
  - Opciones útiles: `--qt-interface-scale`, `--qt-accent-color=#FF8800`, `--qt-max-volume=125`, `--qt-pin-controls`, `--qt-verbose`.
  - Variables de entorno: `QML_IMPORT_TRACE=1`, `QT_LOGGING_RULES`, `QSG_INFO=1`.
  - `QT_QUICK_CONTROLS_STYLE` **no tiene efecto**, porque la interfaz usa `QtQuick.Templates`.
- **Depurar QML:** configurar con `--enable-qt-qml-debug` (autotools) o `-Dqt_qml_debug=true` (Meson) y lanzar con `--qt-qmljsdebugger=port:…`.
- **`qmllint`:** hoy no se usa. Se propone añadirlo en la fase 1.

---

## 6. Especificación «Redesigned VLC»

> **Estado: especificación, no implementada.** Este PR no cambia nada de lo que se describe aquí. Cada apartado indica en qué archivos y puntos de extensión del mapa anterior se apoyaría.

### 6.1 Tokens de diseño

| Token | Valor | Uso | Implementación |
|---|---|---|---|
| `bg.base` | `#121212` | Fondo del contenido | `makeDarkPalette()`: conjunto `View`, `Bg.Primary` (`darkGrey50`) |
| `bg.surface` | `#181818` | Barra lateral, barra de controles, cabeceras | Conjunto `Window`, `Bg.Primary`/`Bg.Secondary` (`darkGrey100`) |
| `bg.elevated` | `#1E1E1E` | Tarjetas, popups, diálogos, menús | Conjunto `Tooltip`, `Bg.Primary` (`darkGrey200`) |
| `accent` | `#FF8800` | Play/pausa, progreso, selección, foco | `orange500` (ya existe). Sustituir los valores fijos de `PlayButton.qml` |
| `accent.dim` | `#FF8800` con α 0,25 | Parte ya reproducida de la barra de progreso | Nuevo rol `Slider/Fg/Secondary` |
| `fg.primary` | `#FFFFFF` con α 0,92 | Texto principal | Sobre `#121212` el contraste es ≥ 15:1 |
| `fg.secondary` | `#FFFFFF` con α 0,64 | Metadatos | Contraste ≥ 7:1 (AA y AAA) |
| `fg.onAccent` | `#121212` | Texto o glifo sobre fondo naranja | `#121212` sobre `#FF8800` da unos 7,8:1. El blanco no llega a 4,5:1 (ver A11Y‑05) |
| `font.family` | **Inter** (variable, OFL 1.1) | Toda la interfaz | Ver 6.2 |
| `radius.sm` / `md` / `pill` | 4 / 8 / altura÷2 dp | Botones, tarjetas, píldora | `VLCStyle.qml` |

Reglas generales:
- El tema oscuro es el **predeterminado** en «Redesigned VLC». El claro se mantiene, con los contrastes corregidos según A11Y‑05.
- El acento se puede personalizar desde el asistente (6.8). Al cambiarlo, hay que recalcular `fg.onAccent` (negro o blanco, el que dé más contraste).

### 6.2 Tipografía: Inter
1. Añadir `InterVariable.ttf` e `InterVariable-Italic.ttf` (licencia OFL 1.1, compatible con la GPL; incluir `OFL.txt`) en `pixmaps/fonts/`. Registrarlos en `assets.qrc` y en `Makefile.am:792`.
2. Al arrancar la interfaz (`maininterface/mainui.cpp`, junto a la carga de `VLCIcons`), cargar las fuentes con `QFontDatabase::addApplicationFont` y llamar a `QGuiApplication::setFont(QFont("Inter"))`. Así también los diálogos de Widgets usan Inter.
3. En `VLCStyle.qml`, añadir `readonly property string fontFamily: "Inter"` y la escala:
   - 12 / 13 / 14 / 16 / 20 / 24 dp;
   - pesos 400 / 500 / 600;
   - números tabulares (`font.features: { "tnum": 1 }`) en los tiempos y en los porcentajes de volumen.
4. Crear una opción `qt-font-family` para quien prefiera la fuente del sistema, por ejemplo en idiomas CJK (chino, japonés, coreano) o en árabe. Inter no cubre esos alfabetos; Qt recurre automáticamente a otra fuente para los glifos que falten.

### 6.3 Barra de transporte
- **Play/pausa:** una **píldora naranja de 54 × 30 dp**.
  - Radio 15 dp, fondo `accent` y glifo `fg.onAccent` de 16 dp.
  - Hover: `accent` aclarado un 8 %. Pulsado: oscurecido un 8 %.
  - Foco: anillo de 2 dp `visualFocus` con 2 dp de separación.
  - Mantener pulsado sigue deteniendo la reproducción, como ahora.
  - Se implementa como una variante nueva de `controlbarcontrols/PlayButton.qml` (por ejemplo, `PlayPillButton.qml` con un id nuevo **al final** del enum `ControlType`), o modificando el actual.
  - Accesibilidad: conservar `Accessible.checkable` y `checked`; el nombre cambia entre «Reproducir» y «Pausa».
- **Anterior y siguiente:** `IconToolButton` de 32 dp con el glifo en `fg.primary`. La píldora va en el centro del perfil «Default».

### 6.4 Barra de progreso
- Altura: **14 dp**. Pista negra `#000000` con un radio de 2 dp.
- Parte reproducida: `accent` con **α 0,25**.
- Parte en buffer: blanco con α 0,08, por debajo de la parte reproducida.
- **Cabezal:** una barra vertical **naranja de 5 dp** de ancho que ocupa toda la altura. **Siempre visible**: ya no aparece solo en hover.
- Capítulos: marcas verticales de 1 dp (blanco con α 0,24) en lugar de segmentos separados. Hover sobre una marca: tooltip con el nombre del capítulo, como ahora.
- Hover: se quita el escalado ×1,8 de los capítulos, porque con 14 dp ya hay suficiente superficie táctil.
- Implementación:
  - en `SliderBar.qml`: `barHeight`, `_hoveredScalingFactor`, `sliderHandle` (estado `visible` por defecto) y `progressRepeater`;
  - en `ControlBar.qml:52`: `sliderHeight`;
  - un rol nuevo en el conjunto de colores `Slider`.
- Accesibilidad: anunciar «1:23 de 4:56» (mejora 12). Las flechas y la rueda funcionan igual que ahora.

### 6.5 Volumen en cuña
- Forma: un triángulo rectángulo («cuña») de 72 × 18 dp que crece de izquierda a derecha y representa de 0 % a **125 %**.
- Relleno con **degradado** horizontal fijo sobre toda la cuña: verde `#2EB82E` (0 %) → naranja `#FF8800` (≈ 80 %) → rojo `#E53935` (125 %). La parte por encima del valor actual se ve en blanco con α 0,12.
- Marca vertical de 1 dp en el 100 %. Al arrastrar, el valor se engancha al 100 % igual que hoy con `_clamp`.
- El máximo sigue siendo `qt-max-volume`. Si el usuario lo cambia, la cuña se escala para que su extremo sea ese máximo; el degradado pone el rojo en el máximo y el naranja en el 100 %. Arreglar QT‑15 al mismo tiempo.
- Implementación:
  - componente nuevo `widgets/qml/WedgeSlider.qml`, con `Shape` + `ShapePath` + `LinearGradient` de QtQuick.Shapes, o bien un `Canvas`;
  - `VolumeWidget.qml` lo usa en lugar de `SliderExt`.
- Accesibilidad:
  - `Accessible.role: Slider`, con un valor que se anuncia como «85 %»;
  - el estado de silencio va en el botón (A11Y‑04);
  - **el estado no puede depender solo del color**: tooltip con el porcentaje y marca del 100 %.

### 6.6 Barra lateral y biblioteca
- **Entradas de la barra lateral**, en orden: **Inicio · Vídeos · Música · Red · Listas · Recientes**.
  - Hoy, Listas es una subpágina de Vídeo y de Música. Se añade como página propia que une las listas de vídeo y de audio (`MLPlaylistListModel` sin filtro de tipo).
  - Recientes reutiliza el modelo de «continuar viendo» y de lo reproducido recientemente de `HomePage.qml`.
  - Descubrir pasa a ser una subpágina de Red.
  - Implementación:
    - `maininterface/navigationmodel.cpp:262‑294` para los nombres y los iconos;
    - `MainDisplay.qml:107‑129` (`pageModel`);
    - eliminar `mlsettings` (QT‑14).
- **Estilo:** ancho expandido de 200 dp y contraído de 64 dp, fondo `bg.surface`. La entrada activa lleva una barra naranja de 3 dp a la izquierda y el texto en `fg.primary`; el resto va en `fg.secondary`.
- **Biblioteca en cuadrícula:**
  - tarjetas de 160 × 90 dp para vídeo y 160 × 160 dp para audio, con radio `md` sobre `bg.elevated`;
  - al pasar el ratón, una píldora de play pequeña.
- **Migas de pan en todas las vistas** (hoy solo existen en Red):
  - por ejemplo, «Música › Artistas › Daft Punk › Discovery»;
  - se generalizan `NetworkAddressbar.qml` y `AddressbarButton.qml` como `widgets/qml/Breadcrumbs.qml`, alimentados por `History`.
- **Orden y búsqueda:** se reutilizan `GridSortFilterControls.qml`, `SearchCtx` y `SortCtx`. La búsqueda se abre con Ctrl+F, que hoy es `ShortcutExt`.

### 6.7 Menú de pistas con pestañas
- `TracksMenu.qml` pasa a ser un popup con cuatro **pestañas**: **Reproducción · Vídeo · Audio · Subtítulos**.

  | Pestaña | Contenido | Origen |
  |---|---|---|
  | Reproducción | Velocidad, repetición, A‑B, marcadores | `TracksPageSpeed.qml` / `PlaybackSpeed.qml` |
  | Vídeo | Pistas de vídeo, relación de aspecto, recorte, desentrelazado | `TracksListPage.qml` (columna de vídeo) y los menús de `menus.cpp` |
  | Audio | Pistas, retardo, dispositivo | Columna de audio y `TracksPageAudio.qml` |
  | Subtítulos | Pistas, retardo, FPS, «Añadir archivo…» | Columna de subtítulos y `TracksPageSubtitle.qml` |

- Las pestañas se construyen con `widgets/qml/TabButtonExt.qml` o con el conjunto de colores `TabButton`, sobre un `StackLayout`. La pestaña activa lleva un subrayado naranja de 2 dp.
- Tamaño: 480 × 320 dp, fondo `bg.elevated` con α 0,96.
- Teclado: Ctrl+Tab cambia de pestaña y Escape cierra el popup.

### 6.8 Ajustes globales con búsqueda y asistente de tema
- **Ajustes:**
  - Página QML a pantalla completa (por ejemplo, `dialogs/settings/qml/SettingsPage.qml`) con categorías a la izquierda y un **buscador global** arriba.
  - El buscador filtra por etiqueta, descripción y nombre de opción a partir de un modelo C++ nuevo (`SettingsModel`) construido sobre `module_config_get`. `complete_preferences.cpp` ya hace este recorrido para el filtro de las preferencias avanzadas.
  - La primera iteración solo cubre las opciones de las preferencias simples. Las avanzadas siguen en Qt Widgets, con un enlace a ellas.
- **Asistente de tema:**
  - Se amplía la página `colorSchemePage` de `dialogs/firstrun/firstrunwizard.cpp`, o se rehace en QML.
  - Contenido:
    - esquema: Sistema, Claro u Oscuro, con el oscuro como predeterminado;
    - color de acento: naranja `#FF8800` por defecto, otros cinco colores predefinidos y un selector libre;
    - una vista previa en vivo de la barra de controles.
  - Guarda en `qt-accent-color` y en `MainWindow/color-scheme-index`.
  - Se puede volver a abrir desde Ajustes → Apariencia.

### 6.9 Criterios de aceptación transversales
- Contraste AA en todos los pares de colores de texto y fondo, comprobado con un script en la CI.
- Todo control interactivo tiene `Accessible.name` y se puede manejar con el teclado.
- El reflejo RTL funciona (A11Y‑07).
- Ninguna cadena nueva concatenada, y plurales con `%n`.
- Cero valores de color fijos en QML: todo pasa por `ColorContext`.
- Los perfiles de barra guardados por los usuarios siguen funcionando: los ids nuevos solo se añaden al final del enum.
- Cada componente nuevo se registra en `meson.build` **y** en `Makefile.am`.

---

## 7. Plan por fases

| Fase | Objetivo | Contenido | Criterio de salida |
|---|---|---|---|
| **0. Estabilidad (P0)** | Que nada se congele ni falle | CORE‑01 a CORE‑04, QT‑01, QT‑02, SEC‑01, más un test para cada uno: `src/playlist/test.c` y fuzzer/ASan para SEC‑01 | Tests en verde; ASan limpio con el corpus semilla |
| **1. i18n e infraestructura** | Que todo lo que se añada sea traducible y comprobable | I18N‑01; `qmllint` en la CI; comprobación de `POTFILES`; comprobación de contraste; objetivo de fuzzing de listas (mejora 1) | `.pot` de Meson igual al de autotools; CI en verde |
| **2. Correcciones P1** | Comportamiento correcto | CORE‑05 a CORE‑08, QT‑03 a QT‑08, QT‑12, SEC‑02 a SEC‑04, A11Y‑01, A11Y‑02, A11Y‑05, A11Y‑07 | Tests de regresión; revisión con NVDA u Orca |
| **3. Tokens y tipografía** | Base visual | 6.1 y 6.2: tokens oscuros, `fg.onAccent`, Inter, `VLCStyle.fontFamily`, sin valores fijos en `PlayButton.qml` | Capturas antes/después con `--qt-interface-scale` 1 y 2; contraste AA |
| **4. Reproductor** | Transporte nuevo | 6.3 a 6.5: píldora de play, barra de progreso de 14 dp, cuña de volumen (más QT‑15) y 6.7 (pestañas de pistas) | Perfil «Default» actualizado; perfiles antiguos intactos; teclado y lector de pantalla OK |
| **5. Biblioteca** | Navegación nueva | 6.6: barra lateral, página de Listas, Recientes, migas de pan genéricas, cuadrícula | Navegación completa con teclado; historial correcto |
| **6. Ajustes y asistente** | Configuración moderna | 6.8: `SettingsModel` y página QML con búsqueda; asistente de tema y acento | La búsqueda encuentra cualquier opción simple; el asistente persiste lo elegido |
| **7. Pulido** | Cierre | P2 restantes, A11Y‑08 (reducir movimiento), I18N‑02 a I18N‑05, documentación y `NEWS` | Sin P0/P1 abiertos |

Las fases 0 a 2 se pueden repartir en varios PR pequeños e independientes. A partir de la 3, cada fase es un PR que se revisa con capturas de pantalla.

### 7.1 Decisión de tecnología

**Se mantiene Qt 6/QML.** No se cambia de tecnología.
- El rediseño cabe en los puntos de extensión que ya existen (sección 5).
- La integración del vídeo (compositores DComp, Wayland y X11), los modelos de la biblioteca y la accesibilidad nativa ya están resueltos en QML. Con otra tecnología habría que rehacerlos.
- El fork puede seguir incorporando los cambios de VideoLAN, cuya interfaz oficial de la versión 4.0 es esta misma.

Dentro de Qt se añaden tres cambios de arquitectura:
1. **Menús en QML**, para que puedan seguir el tema.
2. **Ajustes en QML** (fase 6).
3. **Una comprobación en la CI** de que `meson.build` y `Makefile.am` registran los mismos archivos QML.

### 7.2 Estado de la ejecución

Rama `claude/wonderful-pascal-entcah`, sobre `master` (`4953f0b`). Validado con una compilación Meson con ASan y UBSan.

**Fase 0: hecha.** Un commit por hallazgo:

| Hallazgo | Commit | Validación |
|---|---|---|
| CORE‑04 | `9b80512` playlist: export: fix swapped error labels | Revisión. El harness de tests de la playlist no puede ejercitar `export` |
| CORE‑01 | `28d5463` input: fix out-of-bounds access on previous chapter without chapters | Test nuevo en `test/src/player/titles.c`. **Sin el arreglo, ASan da *heap-buffer-overflow* en `input.c:2388`** |
| CORE‑02 | `b2a500b` input: send the attachments event without the item lock | Test nuevo en `test/src/player/attachments.c` (el listener lee el item). **Sin el arreglo, salta el assert de mutex ya tomado** |
| CORE‑03 | `59ed028` player: metadata: fix lock inversion with the audio meter | Test de estrés en `test/src/player/loudness.c`. El interbloqueo antiguo depende de la temporización y **no se reproduce de forma fiable** (0/10 ejecuciones), así que el test solo comprueba que la secuencia es segura |
| QT‑01 | `3ee3e8b` qt: thumbnailcollector: fix deadlock and use-after-free on destruction | Compila. Sin test automático |
| QT‑02 | `970ca5c` media_tree: always notify the end of the preparsing | Arreglo en el núcleo (siempre se notifica el fin del preparse) y en Qt (el semáforo solo se libera para la petición propia, y también si `Preparse` falla). Compila. Sin test automático |
| SEC‑01 | `5dcda8c` demux: ram: fix out-of-bounds read/write in clipinfo parsing | Test nuevo `test_modules_playlist_ram`. **Sin el arreglo, ASan da *heap-buffer-overflow* en `strchr`** |

**Fase 1: hecha.**

| Tarea | Commit | Resultado |
|---|---|---|
| I18N‑01, extracción con Meson | `a6d1a05` po: meson: extract qsTr() and plural qtr() strings | El objetivo `vlc-pot` de Meson pasa de 0 a 495 referencias a QML |
| I18N‑01, `POTFILES` | `6b0f64e` po: add missing files to POTFILES.in and check it in a test | **Faltaban 135 archivos, no 3.** Se añaden y se crea el test `potfiles` (`po/check_potfiles.py`) |
| `qmllint` | `062fd2d` qt: meson: add a qmllint test | Test `qmllint` (suite `qt`), limitado a las comprobaciones que no dependen de los tipos C++ |
| Bug encontrado por `qmllint` | `b0cd876` qml: fix signal handlers declaring more parameters than the signal | `ServicesHomeDisplay.qml` perdía el motivo del foco (`reason` llegaba como `undefined`) al volver al inicio de los servicios |
| Contraste | `3c6e66d` qt: meson: add a contrast test for the palettes | Test `contrast`. Los 13 pares que ya no cumplen están en `scripts/contrast_known_issues.txt` (A11Y‑05, fase 2); cualquier par nuevo que no cumpla hace fallar el test |
| Fuzzing de listas | `388ee42` test: demux-run: allow fuzzing the playlist demuxers | Variable `VLC_TARGET_URL` y llamada a `readdir`. **Con un `.b4s` mínimo ya reproduce SEC‑03** (SEGV en `b4s.c:189`) |

**Tests que fallan en el entorno de validación sin relación con estos cambios:** `http_tunnel_test`, `test_qt_renderer_manager`, `test_qt_dialog_model` y `test_libvlc_media_player_record` dan fugas con LeakSanitizer; `test_src_preparser_thumbnail_to_files` falla por falta de formato PNG; `test_src_media_source` y `test_libvlc_media_discoverer` fallan porque no hay `plugins.dat`; `test_modules_codec_hxxx_helper` da un aviso de UBSan. `test_src_media_source` se comprobó también sin los cambios, y falla igual.

**Fase 2: hecha**, con las reservas que se indican después de la tabla.

| Hallazgo | Commit | Validación |
|---|---|---|
| (infraestructura) | `02f8e7f` src: meson: build and run the playlist unit test | `test_playlist` solo existía en autotools; ahora también se ejecuta con Meson |
| CORE‑05 | `7f78971` playlist: keep playing the next item when removing the current one | Test `test_remove_current`. **Sin el arreglo, falla** (`current == -1` en lugar de 1) |
| CORE‑06 | `41d2426` playlist: sort: fix comparison of optional integers | Test `test_sort_optional_integers`. **Sin el arreglo, falla** |
| CORE‑07 | `d40847a` playlist: sort: handle items without file size or modification date | Test `test_sort_file_size` |
| CORE‑08 | `0617055` player: fix the vlc_player_New() error path | Compila. Sin test automático, porque haría falta inyectar fallos |
| SEC‑02 | `6221d58` codec: subsusf: ignore styles without name | Test nuevo `test_modules_codec_subsusf`. **Sin el arreglo, falla** (UBSan: puntero nulo en `strcasecmp`) |
| SEC‑03 | `4b77b5e` demux: playlist: b4s: ignore entries without Playstring | Test `test_modules_playlist_parsers` (antes `..._ram`). **Sin el arreglo, falla** |
| SEC‑04 | `3e7159c` demux: playlist: xspf: limit the track id | Medido con `vlc-demux-run`: una lista de 343 bytes pasaba de **1,8 GB y 7,5 s** a 0,27 s |
| QT‑03 | `28bff7f` qt: mediatreelistener: remove the listener before destroying the callback | Compila. Sin test automático |
| QT‑04 | `697beae` qt: networkdevicemodel: fix the removal of device sources | Compila. Sin test automático |
| QT‑05 | `930c6f8` qt: dialogmodel: set the provider and the shutdown flag with the lock | `test_qt_dialog_model` pasa; solo queda su fuga, que ya existía |
| QT‑06 | `8baeb26` qt: dialogs: don't open the media information of a missing media | Compila |
| QT‑07 | `e372272` qt: medialib: skip unavailable medias when playing a collection | Compila |
| QT‑08 | `d3552f3` qt: video_window_handler: don't keep a dangling screen pointer | Compila |
| QT‑12 | `5d05e2d` qml: fix the swapped previous/next frame controls | `qmllint` |
| A11Y‑01 | `5d22cb9` qml: give an accessible name to the window and bookmark buttons | `qmllint` y `potfiles` (que detectó los dos QML nuevos con cadenas) |
| A11Y‑02 | `c3b3005` qml: show the context menu button of table rows with the keyboard focus | `qmllint`. Ver la corrección de A11Y‑02 más abajo |
| A11Y‑05 y QT‑13 | `7b2248a` qt: fix the contrast of the palettes | Test `contrast` **sin problemas conocidos**. Las funciones `withContrast()` y `textColorOn()` dan el mismo resultado en C++ (Qt) y en el comprobador (±1 por canal), también con acentos personalizados |
| A11Y‑07 | `a08c907` qml: mirror the interface with right-to-left languages | Probado con la interfaz real en Xvfb y la dirección RTL forzada: la interfaz se refleja, pero la barra de reproducción no (se mantiene de izquierda a derecha, que es lo habitual en reproductores). Se arregló `SplitButton`, que se rompía al reflejarse |
| **Nuevo** | `aab2c23` qt: fix use after scope in the cached graphics api setup | **Encontrado por ASan al arrancar la interfaz real**: a partir del segundo arranque, una lambda encolada usaba variables locales ya destruidas (`qt.cpp:1175`). Ya no aparece |

**Reservas de la fase 2:**
- **No se ha hecho la revisión con NVDA u Orca** que pedía el criterio de salida, porque el entorno no tiene lector de pantalla. Lo comprobado es el código, `qmllint` y las capturas en Xvfb.
- **Corrección de A11Y‑02:** el delegado de las tablas **sí** atiende la tecla Menú cuando la fila tiene el foco (`Keys.menuPressed.connect(contextButton.clicked)`). Lo que sigue siendo cierto es que el botón «…» solo se veía con el ratón; ya está corregido. Falta, para una fase posterior, atender Mayús+F10, la alternativa a la tecla Menú en portátiles.
- **Pendiente de A11Y‑07:** en RTL, los iconos direccionales (como la flecha «atrás») no se invierten.
- **Proveedores de tema:** los de GTK y Windows toman los colores del tema del sistema, así que su contraste depende de ese tema. El proveedor «Qt básico» sí está corregido.

**Batería completa tras la fase 2:** pasan 103 tests y fallan los mismos 8 ajenos de antes.

**Fase 3: hecha.**

| Tarea | Commit | Validación |
|---|---|---|
| Superficies oscuras y tokens de radio (6.1) | `c1af079` qt: palette: dark theme surfaces and radius tokens | Test `contrast`: todos los pares del tema oscuro cumplen (texto ≥ 7:1) |
| Tema oscuro por defecto | `2359ac2` qt: use the dark color scheme by default | El asistente de primer arranque preselecciona el oscuro, y cancelarlo también lo aplica |
| Tipografía Inter (6.2) | `63bcce2` qt: bundle the Inter font and use it as the application font | Comprobado en Xvfb con un fontconfig cuya única fuente es DejaVu: con `--no-qt-bundled-font` se usa DejaVu y, por defecto, Inter |
| `PlayButton` sin colores fijos | `cdb2539` qml: PlayButton: derive the gradient from the accent color | `qmllint`. Con el acento por defecto, el degradado es casi idéntico al anterior |

**Notas de la fase 3:**
- **Superficies:** en la implementación, la base `#121212` es el contenido (`View`), la superficie `#181818` es la estructura de la ventana (banner, barra lateral y barra de controles, conjunto `Window`) y el nivel elevado `#1E1E1E` son tooltips y desplegables. Así se respeta el orden de profundidad.
- **Inter:** se usan las instancias estáticas Regular, Medium, SemiBold y Bold, unos 800 KB comprimidos. La variable no sirve: hasta Qt 6.7, Qt no maneja su eje de peso y dibujaba 500 y 600 como regular. Las cifras tabulares (`font.features`) necesitan Qt 6.6 y no se han aplicado, porque el mínimo es 6.2.
- **Revisión propia:** sospeché un fallo de identificadores en los botones del asistente. Al comprobarlo resultó que `initializePage()` los asigna, así que no era un fallo y no se ha tocado.
- **Capturas** antes y después con escala 1 y 2, tema oscuro y claro y reproductor, sin errores de ASan.

**Batería completa tras la fase 3:** pasan 103 tests y fallan los mismos 8 ajenos.

**Fase 4: hecha, con el alcance reducido que se detalla en las reservas.**

| Tarea | Commit | Validación |
|---|---|---|
| Píldora de play/pausa (6.3) | `3b2fbfc` qml: PlayButton: draw the button as an accent pill | Captura: 54 × 30 dp, glifo de 16 dp; hover +8 %, pulsado −8 %; anillo de foco de 2 dp separado 2 dp. Nombre accesible «Play» o «Pause» |
| Barra de progreso de 14 dp (6.4) | `fe480dd` qml: SliderBar: 14 dp seek bar with a thin playhead | Captura con 5 capítulos: pista negra, parte reproducida con el acento a α 0,25, cabezal de 5 dp siempre visible, marcas de capítulo de 1 dp. La barra ya no cambia de altura en hover |
| Cuña de volumen (6.5) | `9c28864` qml: VolumeWidget: draw the volume as a wedge | Captura con el volumen forzado al 110 %: degradado verde → naranja (100 %) → rojo (máximo) y marca del 100 % |
| QT‑15 | `6f1886e` qml: VolumeWidget: follow the maximum volume when snapping | El clic derecho se engancha al más cercano de 0, 50 %, 100 % y el máximo real de `qt-max-volume` |
| Menú de pistas con pestañas (6.7) | `fc8c70a` qml: TracksMenu: organize the menu in tabs | Captura en oscuro y claro: 480 × 320 dp, subrayado naranja de 2 dp. Ctrl+Tab y Ctrl+Mayús+Tab cambian de pestaña |
| Teclado en el menú de pistas | `58adeae` qml: TracksMenu: fix the keyboard navigation | Probado en Xvfb con `xdotool`: abrir con el ratón, Ctrl+Tab, flechas y Escape |

**Notas de la fase 4:**
- **Fallo encontrado al implementar 6.7.** El archivo tenía un `FIXME` («Keyboard navigation needs to be fixed for this Popup»), y la causa era esta: si el menú se abría con el ratón, su foco no contaba como foco de teclado. `InterfaceWindowHandler::applyKeyEvent()` trataba entonces Escape, las flechas o Espacio como atajos globales, y el menú nunca los recibía. Ahora el menú toma foco de teclado al abrirse. Escape (o Retroceso) cierra el menú desde las pestañas y vuelve atrás desde las páginas de sincronización.
- **Por qué no basta la política de cierre del `Popup`:** la navegación de VLC consume Escape como acción de cancelar. Además, con el compositor X11, las teclas llegan a la ventana con `sendEvent` y no pasan por el mapa de atajos de Qt.
- **Paleta:** el conjunto `Slider` oscuro usa ahora una pista negra, un verde `#2EB82E` y un rojo `#E53935`. Esto también afecta a `ProgressBarExt` (progreso del escaneo y de las actualizaciones) y a `VideoProgressBar` (progreso sobre las miniaturas). Al rojo y al verde no se les aplica el umbral de texto del test de contraste, porque no se usan como texto.
- **Capturas** en oscuro y claro, con escala 1 y 2, del reproductor (600 × 420 y 1100 × 620) y del menú de pistas con foco de teclado. ASan no da errores.

**Reservas de la fase 4 (desviaciones de la especificación):**
- **Contenido de las pestañas:**
  - **Reproducción** solo tiene la velocidad; faltan repetición, A‑B y marcadores.
  - **Vídeo** solo tiene las pistas; faltan relación de aspecto, recorte y desentrelazado.
  - **Audio** tiene las pistas, y el menú lleva al retardo; falta el dispositivo.
  - **Subtítulos** tiene las pistas, y el menú lleva al retardo y a los FPS.

  El resto de 6.7 queda para la fase 7: requiere exponer en QML menús que hoy viven en `menus.cpp`.
- **Perfiles:** la píldora sustituye al `PlayButton` en lugar de ser una variante nueva del enum `ControlType`. Por eso la ven todos los perfiles, también los antiguos, y el criterio «perfiles antiguos intactos» no se cumple al pie de la letra. Se puede revertir con un `PlayPillButton.qml` si se prefiere.
- **Detalles distintos de 6.4 y 6.5:**
  - las marcas de capítulo usan el acento a α 0,6 en lugar de blanco a α 0,24, porque se distinguen mejor sobre la parte reproducida;
  - el buffer usa `fg.secondary` a α 0,12;
  - la parte vacía de la cuña usa `fg.secondary` a α 0,2;
  - la cuña es un `Canvas` dentro de `VolumeWidget.qml` y no un `WedgeSlider.qml` aparte;
  - el fondo del menú es la superficie de `Window` a α 0,96, porque `bg.elevated` no existe como rol.
- **No hecho:**
  - el anuncio «1:23 de 4:56» de la barra (mejora 12);
  - la revisión con NVDA u Orca, porque el entorno sigue sin lector de pantalla.
- **Verificación parcial de la cuña:** con las salidas de audio de prueba (`adummy`, `afile`), el reproductor informa de un volumen desconocido (−1) y la cuña sale vacía. El relleno se comprobó forzando temporalmente el volumen en QML, sin incluir ese cambio en ningún commit.

**Batería completa tras la fase 4:** pasan 103 tests y fallan los mismos 8 ajenos. En la ejecución en paralelo fallaron además `test_src_clock_clock` (alarma de 10 s, tarda 8,6 s sin carga) y `test_src_preparser_thumbnail`; ambos pasan al ejecutarlos solos y no dependen de Qt.

**Fase 5: hecha, siguiendo `design/ANALISIS-DISENO.md` (rama `design/rediseno`), que precisa la sección 6.6.**

La especificación del rediseño pide una barra lateral sin subentradas: las secciones de cada página se alcanzan desde la propia página. Por eso la fase 5 va más allá de 6.6 en ese punto.

| Tarea | Commit | Validación |
|---|---|---|
| Fallo encontrado al probar Red | `6e13485` xcb_apps: do not read x11-display when it is not declared | Antes, la interfaz abortaba al abrir Red en un build sin `xcb_window` (sin RandR). Comprobado con gdb |
| Historial con «adelante» | `b631028` qt: navigation history: allow to go forward | Botones ← → en la cabecera |
| Cabecera de página (4.4 del análisis) | `ec8ac83` y `1802db4` (migas de pan) | ← →, migas de pan («Music › Albums») y «N items». Plural con la convención de VLC: `qsTr(singular, plural, n)` |
| Barra lateral (4.2) | `e052870` y `725cd10` | Home, Videos, Music, Network, Playlists, Recent y «Add item». Activo en naranja y negrita, sin indicador lateral. Música y Red abren un índice de secciones. Test `test_navigation_model` reescrito para el modelo plano |
| Cuadrícula de vídeo (4.4) | `6078b37` | Los vistos se atenúan y tienen la barra completa. Los que están a medias llevan barra parcial. Desaparece la marca de «nuevo» |
| Orden de vídeo (4.4) | `691db9b` | Unwatched First, Watched First, Newest First, Oldest First, Title A-Z y Title Z-A, con un orden fijo por entrada |
| Inicio (4.3) | `3828b37` | «Watch Next ›»: el título lleva a la lista completa |
| Listas (4.7) | `b24ebdb` y `d68f0a1` | «Create playlist». Crear una lista vacía fallaba con una aserción en `MLPlaylistListModel::create()`; corregido |
| Cola (4.7) | `e08282e` | «3 items - 47m», más ordenar, repetir, aleatorio, quitar, añadir y buscar. Filas con asa o con ▶ naranja |
| Menú «…» de página (4.4) | `802cac3` | En Vídeos: «Add Folder» y «Resync» |

**Entorno de la fase 5:**
- Se ha instalado medialibrary 0.13.2 (archivo de Ubuntu) para poder probar la biblioteca. El de la distribución, 0.12, no llega al mínimo de VLC 4.
- Se han activado `png` y `jpeg`. Sin un codificador JPEG, las miniaturas de la biblioteca fallaban sin avisar.
- La biblioteca de prueba tiene vídeos y canciones etiquetadas, generados con ffmpeg.

**Reservas de la fase 5:**
- **Iconos:** se usan los glifos que ya existían. Los del diseño (carpeta con ▶, carpeta con nota, antena) piden regenerar `VLCIcons.ttf` con fontforge, y quedan para el pulido visual.
- **«…» de carpeta:** de las entradas del diseño (Add File, Add Folder, Edit Subtitle Tracks, Edit Audio Tracks, Resync, Info), solo «Add Folder» y «Resync» tienen equivalente en VLC.
- **Pendiente para la fase de la ventana:**
  - página de artista con la lista de pistas;
  - listas M3U navegables como carpeta;
  - diálogo «Open Network Stream» con varias URL;
  - menús nativos (QMenu), que aún salen claros en el tema oscuro.
- **«Add item»** lleva a las carpetas de Red para añadirlas a la biblioteca. El diseño no aclara qué hace esa entrada.

**Batería completa tras la fase 5:** pasan 110 tests y fallan 4 de los 8 ajenos de siempre (`http_tunnel_test`, `test_modules_codec_hxxx_helper`, `test_qt_dialog_model` y `test_qt_renderer_manager`). Los otros 4 pasan ahora porque el build tiene medialibrary, png y jpeg.

**Fase 6: hecha (secciones 4.11 y 4.13 del análisis del diseño).**

| Tarea | Commit | Validación |
|---|---|---|
| Acento configurable en caliente | `c8a408d` qt: allow to change the accent color at runtime | Al elegir otro acento (p. ej. rojo), toda la interfaz cambia sin reiniciar. Test `contrast` OK. Si el color no es válido, se vuelve al acento por defecto |
| Ajustes globales con búsqueda | `2670935` qt: global settings with search | Diálogo «Preferences» de la barra lateral, con las categorías App / Media / System del diseño. Cada opción usa su control: interruptor ON/OFF, lista, número, deslizador, texto o color. La búsqueda recorre todas las categorías. «Advanced Options ›» abre las preferencias de siempre |
| Acento en el asistente de primer arranque | `b87c4a9` qt: first run wizard: choose the accent color | Los 9 colores del diseño aparecen bajo los temas; se comparten con los ajustes a través de `MainCtx.accentColorPresets` |

**Notas de la fase 6:**
- **`SettingsModel`:**
  - es una selección curada de opciones reales de VLC (unas 90);
  - omite las que no existen en el build (módulo no compilado) y las obsoletas: `add_obsolete_*` deja la opción sin texto, y así se detecta;
  - aplica cada cambio al momento (`reloadPrefs` para las de la interfaz) y escribe el archivo de configuración al cerrar.
- **Fallos encontrados al implementarla:**
  - `config_GetType()` devuelve el tipo `VLC_VAR_*`, no el `CONFIG_ITEM_*`; el modelo guarda el de la opción;
  - los controles dentro del popup salían magenta porque no encontraban paleta, como ya pasaba en el menú de pistas.
- **Plurales:** en VLC, `qsTr(singular, plural, n)` se traduce con `ngettext`; el patrón de Qt `qsTr("%n item(s)", "", n)` devuelve una cadena vacía. Se ha usado la forma de VLC.

**Reservas de la fase 6:**
- **Categorías vacías:** Library y Extensions no tienen opciones simples; la página remite a las opciones avanzadas. Las carpetas de la biblioteca y los complementos tienen sus propios diálogos.
- **Atajos:** «Edit Keyboard Shortcuts» de Controls no está; los atajos siguen en las preferencias avanzadas.
- **Asistente de primer arranque:** sigue siendo el de Qt Widgets (tema claro) con sus páginas; solo se ha añadido el acento. La vista previa en vivo del reproductor del diseño no está.

**Batería completa tras la fase 6:** 110 OK y los mismos 4 fallos ajenos.

**Fase 7: hecha (pulido).** Rama `claude/wonderful-pascal-entcah`, fusionada en `design/rediseno` (`df9a0c6` y `f7aead7`).

**Correcciones P2, un commit cada una:**

| Hallazgo | Commit | Validación |
|---|---|---|
| CORE‑13 | `7be6bc9` player: timer: do not truncate the number of intervals | Tests `test_src_player_timers` OK |
| CORE‑14 | `a1c2c1c` player: only allow the categories of cat2vars in assertions | Tests del player OK |
| CORE‑15 | `32cde11` player: fix a leak and a format in track and chapter selection | `_("Chapter %zu")`; se liberan las dos reservas |
| SEC‑11 | `ccbf80e` demux: wms: peek all the bytes that are compared | Peek de 11 bytes y `memcmp` |
| SEC‑09 | `42e9364` demux: subtitle: compare the start times without subtracting them | `(a > b) - (a < b)`, sin desbordamiento |
| SEC‑05 | `c859131` demux: wpl: do not log an unset tag name at the end of the file | `psz_name = NULL` y «(eof)» en los mensajes |
| CORE‑10 | `6094fa6` player: title: release the title that fails to be created | `break` en el primer capítulo sin nombre y `count = title_idx + 1` |
| CORE‑09 | `d962550` player: medialib: release the playback states of the media library | Nueva `vlc_player_input_ReleaseMlStates()`: antes de cada restauración, al final de `UpdateMLStates` y en `vlc_player_input_Delete` |
| QT‑10 | `8612a83` qt: bookmark model: do not add a player listener twice | `initModel()` quita el listener anterior; `setPlayer()` deja `m_listener` a nulo |
| QT‑11 | `b62527d` qt: video window: do not read the window states from the vout threads | Los estados se guardan en un atómico que actualiza el hilo de la interfaz (`windowStateChanged`) |
| SEC‑08 | `2094df9` demux: asx: fix leaks and the ENTRYREF address | ASX de prueba con REF y MOREINFO repetidos: ASan sin fugas; `ENTRYREF` ahora usa el `HREF` resuelto respecto a la lista (antes cogía el primer atributo que **no** era `HREF`) |
| SEC‑10 | `a320fe4` codec: scte27: only reassemble the segments in order | Se exige `index == anterior + 1`, lo que acota el mensaje (4096 × 4086 bytes como máximo); `realloc` comprobado |
| SEC‑06 | `c9dae0a` codec: subsdec: append the text without copying it again | Arnés que llama a `ParseSubtitles`: salida idéntica en un texto con etiquetas; **81 s para 256 KiB antes, 0,05 s para 4 MiB después** (con ASan) |
| CORE‑12 | `00e22d3` player: aout: remove the callbacks from the aout that has them | El player retiene el aout donde registró los callbacks y solo los quita de ese |
| CORE‑11 | `57f953b` playlist: keep the randomizer in sync on allocation failure | Nueva `randomizer_Reserve()` antes de insertar; si al pasar a aleatorio no caben los elementos, el orden sigue normal. `test_playlist` OK |
| QT‑09 | `b49c94f` qt: extensions: ignore the queued updates of a deleted dialog | Ver la nota |
| SEC‑07 (parcial) | `dcef16e` demux: playlist: fix up the addresses that are kept as they are | El fallback devuelve la URI normalizada por `vlc_uri_fixup` y no la cadena original |

**Accesibilidad e i18n:**

| Hallazgo | Commit | Validación |
|---|---|---|
| A11Y‑03 | `d606cd9` qml: expose the role and the selection of the list and table rows | Cola: `ListItem`; tablas: `Row` con nombre (`title` o `name`); `selected` y `onPressAction` en las dos |
| A11Y‑04 | `a59c2fa` qml: tell the state of the mute, record and repeat buttons | «Mute»/«Unmute», «Record»/«Stop recording», «Repeat off/all/one», más `Accessible.checked` |
| A11Y‑06 | `a3d773c` qt: about: use buttons for the license, authors and credits | Probado en Xvfb: Tab enfoca «Credits» y Espacio abre los créditos |
| A11Y‑08 | `a352495` qt: add an option to reduce the motion of the interface | Nueva opción `qt-reduce-motion` (ajustes › Interface › Accessibility): duraciones a 0 y sin animaciones infinitas (títulos largos, botón de grabar, nieve). Arranca sin errores QML |
| A11Y‑09 | `26f4eca` qml: scale the fixed sizes… | `VLCStyle.dp()` en el editor de barras, la cola separada y los campos de texto |
| I18N‑02 | `fbe29d1` qt: use plural forms for the number of videos and downloads | El `.pot` de Meson lleva `msgid`/`msgid_plural` para «%1 Video» y «%1 download» |
| I18N‑03 | `d7774ac` qt: do not build translatable strings by concatenation | «About %1», «Go to time:», «Broadcast: %1»; HTML y colores fuera de las cadenas; nombre de archivo escapado con el nuevo `Helpers.escapeStyledText()` |
| I18N‑04 | `d719503` qml: format the numbers in the language of the interface | Nuevos `Helpers.formatNumber()` y `Helpers.numberFromFormattedText()`, probados en un motor QML: «1,25» en es/de y «1.25» en en; se aceptan «ms %1» y «%1 мс» |
| I18N‑05 | `eca7773` qt: capitalize the visible strings… | «Cancel», «Filter», «Fullscreen»/«Exit fullscreen», «%1 s» y «%1 ms» |
| `NEWS` | `1d1cf34` NEWS: add the changes of the Qt interface | Novedades de las fases 3 a 7 |

**Notas de la fase 7:**
- **QT‑09:** no se ha usado `Qt::BlockingQueuedConnection`, que proponía el informe, porque puede bloquearse al cerrar: el hilo de Qt hace `vlc_join` del hilo Lua al desactivar las extensiones. En su lugar, el proveedor Qt guarda los diálogos que siguen vivos, con un mutex recursivo:
  - un diálogo sale del registro cuando la extensión lo borra sin que la interfaz lo haya creado (es el caso en que la extensión no espera);
  - las actualizaciones encoladas de un diálogo que ya no está se ignoran;
  - `b_kill` se lee con el diálogo bloqueado.

  Compila y pasa los tests, pero no se ha probado con una extensión real.
- **SEC‑07** sigue abierto en su parte de diseño: ninguna política de origen impide que una lista remota apunte a `file://` o a rutas UNC. Hace falta decidir el comportamiento (rechazar o preguntar) antes de implementarlo.
- **Hallazgo nuevo (intermitente):** `test_libvlc_media_player_record` falló una vez con una fuga de 296 bytes en `AddStream` de `modules/mux/asf.c`, creada por `stream_out/record.c` al cerrar la grabación (`OutputStart` desde `Del`). No se reproduce al repetirlo (5 de 5 OK) y no pasa por el código tocado.
- `test_qt_navigation_model` y `test_qt_thread_runner` fallaron una vez con la batería completa en paralelo y pasan al repetirla; los dos son ajenos a esta fase.

**Batería completa tras la fase 7:** 110 OK y los mismos 4 fallos ajenos.

**Fase 8: hecha (ventana y reproductor, secciones 4.1, 4.8, 4.9, 4.10 y 4.14 del análisis del diseño).** Fusionada en `design/rediseno` (`b7785c9`).

| Zona | Commit | Validación |
|---|---|---|
| Barra de una fila (4.8) | `65a6e76`, `91d6e42` | Nuevo modo `Inline` de `ControlBar`: con los controles fijos, el tiempo, la barra de progreso y la duración van entre los controles izquierdos y derechos. Nuevo perfil «Default»: anterior, play, siguiente · volumen, pistas de audio, subtítulos, ajustes, cola. Tres controles nuevos (`AUDIO_TRACKS_BUTTON`, `SUBTITLE_TRACKS_BUTTON` y `PLAYER_SETTINGS_BUTTON`, en los huecos reservados 0x2B–0x2D) abren el menú de pistas en su pestaña, sobre el propio botón |
| Cuña de volumen | `677b37d` | Trapecio, degradado de verde al acento y fondo negro en los temas oscuros |
| Marco del vídeo | `34000ca` | `qt-pin-controls` pasa a estar activo por defecto. El vídeo va en un marco con margen y esquinas de 8 dp. Como el vídeo se pinta debajo de la interfaz, el marco es un anillo dibujado encima |
| Barra de título (4.1) | `66c26e2`, `58fdb6f`, `838e9ea` | Reproductor: cono, «…» y botón de contexto («⌂ Home», «Videos»…) que vuelve a la página de la biblioteca; el título va centrado (el nombre del archivo cuando el título es una ruta). Biblioteca: cono, «…» y barra lateral (atrás y adelante están en la cabecera de página desde la fase 5) y el título del medio en reproducción. A la derecha, minimizar, maximizar, **pantalla completa** y cerrar (nuevo tipo `CSDButton::Fullscreen`; en Windows, `HTCLIENT`) |
| Aviso de reanudación (4.8) | `b10a6d2` | Tarjeta centrada sobre los controles: «You already watched till **00:12** [Continue Watching] ×». La posición sale del progreso guardado en la biblioteca (`PlayerController.restoreTime`) |
| Pestaña Video (4.9) | `e38f6d5`, `fbe51c7`, `14166d3`, `4449ce3` | Volteo (None, Horizontal, Vertical) y rotación (0–270°) con el filtro `transform` aplicado en caliente (probado: el vídeo sale espejado). También zoom, relación de aspecto, recorte, ajuste y desentrelazado (con `VLCVarChoiceModel.currentRow` nuevo) y las pistas de vídeo. La pestaña Subtitles tiene «Show Preferences» |
| Menú «…» (4.10) | `fabc983` | Lista plana: las entradas de abrir (con atajos), Open Recent ›, Save Playlist, Convert, Stream · Customize Player, Plugins and Extensions, Settings (Ctrl+P), About (Shift+F1) · los menús clásicos como submenús · Quit |
| Menús oscuros | `0aa6353` | Con el esquema oscuro, los widgets (menús y diálogos) usan una paleta oscura con los tokens 4.14 y el acento. Antes solo pasaba con Qt 6.8 y un tema de plataforma que lo siguiera |
| `NEWS` | `0442ad7` | |

**Entorno de la fase 8:**
- Se han instalado las cabeceras de GL/EGL de Mesa y las extensiones xcb (composite, damage, xfixes, keysyms y xkb). Con ellas se compilan las salidas de vídeo OpenGL y el compositor X11 de Qt, y el vídeo se ve en Xvfb. Hasta ahora las capturas mostraban el reproductor de audio.
- Sin un gestor de ventanas, el compositor X11 no redimensiona su superficie cuando el tamaño se cambia desde fuera. Por eso algunas capturas son de 600×420, y las de la biblioteca usan `--qt-compositor=dummy`.

**Reservas de la fase 8:**
- **No implementado del diseño:**
  - Playback: «Show Subtitle Timeline/Waveform on Seekbar», «Reverse» y «Sleep Timer», que VLC no tiene.
  - Video: «HDR», «Resolution» y «Render».
  - Subtitles: la separación de pistas incrustadas y externas, la sincronización y la apariencia en la misma pestaña (siguen en el submenú «Synchronize» y en las preferencias).
  - Menú «…»: «Profile ›» (los perfiles Movies/Shows/Music/Work no existen en VLC) y «Keyboard Shortcuts».
  - Customize Player: la entrada abre el editor de barras actual, sin las categorías del diseño (4.12).
  - Barra lateral compacta, solo con iconos.
- **Marcadores:** en el modo de una fila no se muestran bajo la barra de progreso.
- **Iconos:** se usan los glifos existentes (`visualization` para el audio). Los del diseño piden regenerar `VLCIcons.ttf`.
- **Volumen en Xvfb:** sin una salida de audio real el volumen no se informa y la cuña sale vacía. En la vista previa del editor de barras se pinta al 50 %.
- **Hallazgo nuevo (preexistente):** al cerrar con el compositor X11, UBSan informa de un acceso a miembro sobre un `QWindow` ya destruido en el lambda de `visibilityChanged` de `CompositorX11RenderWindow` (`compositor_x11_renderwindow.cpp:364` y `:374`). Antes no se veía porque el compositor no se compilaba.

**Batería completa tras la fase 8:** 110 OK y los mismos 4 fallos ajenos.

**Hallazgos nuevos de las fases 7 y 8: corregidos.** Fusionados en `design/rediseno` (`b7ec39d`).

| Hallazgo | Commit | Validación |
|---|---|---|
| Fuga intermitente al grabar (1) | `7633917` mux: asf: release the track when it cannot be added | `AddStream()` no liberaba la pista con un códec de audio no admitido ni al fallar una reserva, y en modo HTTP `DelStream()` la quitaba de la lista sin liberarla. La grabación prueba el multiplexor ASF con cualquier pista (296 bytes, el tamaño de `asf_track_t`) |
| Fuga intermitente al grabar (2) | `1199104` sout: release the options of an access output that fails to open | Al fallar la apertura, `sout_AccessOutNew()` no liberaba las opciones del acceso (`no-overwrite`, que la grabación usa al probar nombres de archivo). `test_libvlc_media_player_record` pasa 60 veces seguidas con LeakSanitizer; antes fallaba más o menos una vez de cada seis |
| Acceso tras destruir en el compositor X11 | `604ba92` qt: x11 compositor: disconnect the visibility handler before the window is destroyed | `~QWindow()` oculta la ventana y llamaba al manejador cuando la parte derivada ya estaba destruida. UBSan ya no informa de nada al cerrar |

Batería completa: 110 OK y los mismos 4 fallos ajenos.

**Instalador de Windows.** Se ha compilado `vlc-4.0.0-dev-win64.exe` (NSIS, 65 MB) desde `b7785c9`, con la imagen `vlc-debian-win64-posix` de la CI y sus dependencias precompiladas. El código se monta en `/builds/videolan/vlc`, porque las rutas de `target_qt.conf` dependen de esa profundidad. ninja y meson se instalan desde PyPI, porque las descargas de GitHub no están permitidas en el entorno. El `.msi` no se genera, porque WiX falla bajo wine.

### 7.3 Icono de la aplicación

Commit `2f45fdd` (icons: new application icon). A petición del propietario, el icono de VLC (el cono) se sustituye por un «play» de tres trazos entrelazados, redibujado en vectorial a partir de la propuesta inicial:
- triángulo equilátero con trazos de grosor constante que comparten centro en cada vértice, así que el contorno ya no tiene escalones;
- trazos más finos, para que el hueco se mantenga abierto a 16 px;
- tres tonos derivados del acento `#FF8800` y una sombra suave en los cruces;
- centrado óptico en un lienzo cuadrado.

Fuentes y generación:
- `extras/misc/app-icon/generate.py` escribe tres SVG: `share/icons/vlc.svg`, la baldosa de macOS y la variante plana de la interfaz (`cone.svg`, que sigue el color de acento).
- `extras/misc/app-icon/render.sh` genera los PNG, XPM, ICO e ICNS.

Las variantes estacionales (Navidad, 1 de abril) usan el mismo icono hasta que haya diseños propios. Los paquetes `VLC.icon` y `VLC-Dev.icon` de Icon Composer (macOS 26) no se han actualizado: necesitan Icon Composer en un Mac.

---

## 8. Anexo: metodología y límites

- **Revisión:** lectura del código por áreas (Qt C++, núcleo, parsers no confiables, a11y/i18n y mapa de la interfaz). Para cada hallazgo se revisaron quién llama a la función, qué locks tiene tomados, los `assert` y quién es dueño de cada objeto, incluido el código del núcleo al que se llama desde fuera del alcance.
  - Por ejemplo: `src/misc/medialibrary.c`, `src/media_source/media_tree.c`, `src/audio_output/meter.c` y `modules/lua/libs/dialog.c`.
- **Verificación de las citas:** cada fragmento citado se buscó con `grep -F` en el commit `4953f0b`, y se confirmó la línea indicada.
- **Hallazgos descartados:** los que no se pudieron confirmar leyendo el código no aparecen. Los que dependen de que se dé un orden temporal concreto, o de un comportamiento externo, llevan confianza **Media**.
- **Sin ejecución:** no se compiló VLC ni se ejecutó ningún caso. Las entradas de ejemplo de la sección 3.3 describen cómo se dispararía cada fallo, pero **no** se han probado. Antes de corregir, se recomienda reproducir cada P0 con ASan o con un test.
- **Fuera del alcance:** otros módulos de interfaz (macOS, Lua, HTTP), la salida de streams, los decodificadores de audio y vídeo, y `contrib/`.
- **Rama 3.0.x:** no se ha revisado. Su interfaz Qt Widgets es otra base de código, y nada de este documento se le aplica directamente.
