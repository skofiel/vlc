# Compilar el instalador de Windows con WSL2 y Docker

Este es el procedimiento para generar el instalador `.exe` de este fork (rama `design/rediseno`) en Windows.
La compilación se hace con la misma imagen Docker que usa la CI de VideoLAN.

- **Imagen**: `registry.videolan.org/vlc-debian-llvm-ucrt:20260611225331` (la misma fecha que fija `extras/ci/gitlab-ci.yml`).
- **Orden**: `extras/package/win32/build.sh -a x86_64 -u -r -p -m -i u`.
- **Resultado**: `vlc-<versión>-win64-<commit>.exe` (más el `.msi`, si sale) y una versión portable,
  en `D:\Proyectos\VLC-instaladores`.

> **Sin instalar nada:** cada push a `design/rediseno` lanza el workflow
> [`.github/workflows/windows-installer.yml`](../../../../.github/workflows/windows-installer.yml).
> Ese workflow compila lo mismo en los servidores de GitHub. El instalador y la versión portable se descargan desde
> *Actions › la ejecución › Artifacts*. La primera ejecución tarda horas, porque compila los contribs.
> Las siguientes los toman de la caché.
> Lo de abajo solo hace falta para compilar en tu propio equipo, y requiere tener la virtualización (SVM o VT-x) activada en la BIOS.

## 1. Lo que hay que saber antes

| | |
|---|---|
| **Primera compilación** | Varias horas. VideoLAN no publica contribs precompilados para `x86_64` (la URL de `-p` da 404), así que se compilan todos, Qt 6 incluido. |
| **Siguientes** | Minutos: los contribs y la compilación de Meson se reaprovechan. |
| **Disco** | Unos 40–60 GB dentro del disco virtual de WSL (en `C:`). |
| **Memoria** | Qt con 16 compilaciones en paralelo puede pasar de 16 GB. Mira el apartado 2. |

## 2. Instalar WSL2 (una vez)

En **PowerShell como administrador**:

```powershell
wsl --install -d Ubuntu-24.04
```

Reinicia Windows cuando lo pida. Al volver, se abre Ubuntu y pide un usuario y una contraseña para Linux.
Comprueba que la versión es la 2:

```powershell
wsl -l -v
```

**Memoria (recomendado):** por defecto WSL usa la mitad de la RAM (16 GB en este equipo).
Crea `C:\Users\<tu usuario>\.wslconfig` con:

```ini
[wsl2]
memory=24GB
swap=16GB
```

Y aplica el cambio con `wsl --shutdown`. Si aun así se queda sin memoria (el compilador muere con `Killed`), baja el paralelismo con `JOBS=8`.

## 3. Instalar Docker dentro de Ubuntu (una vez)

Se recomienda Docker Engine dentro de Ubuntu: es gratuito y no necesita Docker Desktop.
Dentro de Ubuntu:

```bash
sudo apt update
sudo apt install -y docker.io git
sudo usermod -aG docker "$USER"
```

Cierra la sesión con `wsl --shutdown` desde PowerShell y vuelve a abrir Ubuntu. Después comprueba que funciona:

```bash
docker run --rm hello-world
```

Si Docker no arranca, revisa que `/etc/wsl.conf` tenga `[boot]` y `systemd=true` (Ubuntu 24.04 lo trae así) y ejecuta `sudo systemctl enable --now docker`.

> **Alternativa:** Docker Desktop con el motor WSL2 y la integración con Ubuntu activada (*Settings › Resources › WSL integration*).
> Es gratuito para uso personal y empresas pequeñas.

## 4. Compilar

Dentro de Ubuntu:

```bash
bash /mnt/d/Proyectos/VLC/extras/package/win32/docker/build-installer.sh
```

El script hace lo siguiente:
1. **Clona la rama** `design/rediseno` del repositorio de `D:\Proyectos\VLC` en `~/vlc-win`, dentro del disco de Linux.
   - En las siguientes ejecuciones, solo trae los commits nuevos.
   - No usa GitHub.
   - **Solo entra lo que está en commits:** los cambios sin confirmar de `D:` no se compilan.
   - Compilar directamente sobre `/mnt/d` sería varias veces más lento.
2. **Descarga la imagen** (unos GB, solo la primera vez).
3. **Ejecuta `build.sh`** dentro del contenedor y guarda el registro en `~/vlc-win/build-win.log`.
4. **Copia los resultados** a `D:\Proyectos\VLC-instaladores`, con el commit en el nombre:
   - el instalador `.exe` (y el `.msi`, si se ha generado);
   - la carpeta portable `vlc-win64-ucrt-<commit>`.

Variables para cambiar el comportamiento (se ponen delante de la orden):

| Variable | Valor por defecto | Para qué |
|---|---|---|
| `JOBS` | número de núcleos | Bajarlo si falta memoria (`JOBS=8 bash …`) |
| `EXTRA_FLAGS` | vacío | `-l` incluye las traducciones (interfaz en español). Tarda más |
| `BRANCH` | `design/rediseno` | Compilar otra rama |
| `OUT_DIR` | `/mnt/d/Proyectos/VLC-instaladores` | Otra carpeta de salida |
| `WORKDIR` | `~/vlc-win` | Otra copia de trabajo |
| `PORTABLE` | `1` | `0` para no copiar la versión portable |
| `BUILD_FLAGS` | `-a x86_64 -u -r -p -m -i u` | Sustituir todas las opciones de `build.sh` |

Por ejemplo, con traducciones y 8 compilaciones en paralelo:

```bash
JOBS=8 EXTRA_FLAGS=-l bash /mnt/d/Proyectos/VLC/extras/package/win32/docker/build-installer.sh
```

## 5. Por qué estas opciones de `build.sh`

| Opción | Significado | Nota |
|---|---|---|
| `-a x86_64` | Windows de 64 bits | |
| `-u` | Runtime UCRT | **Añadida a la orden original.** La imagen `llvm-ucrt` trae un compilador UCRT, y la CI de VLC siempre la combina con `-u`. Sin ella, `build.sh` compilaría con las cabeceras de `msvcrt` (`__MSVCRT_VERSION__=0x700`) contra una cadena UCRT |
| `-r` | Release | Avisa de que no hay LTO; es normal (LTO sería `-t` y tarda bastante más) |
| `-p` | Contribs precompilados | No tiene efecto: la descarga da 404 y se compilan (ver el apartado 1). Se deja por si VideoLAN vuelve a publicarlos |
| `-m` | Meson en lugar de autotools | Es la compilación con la que se validaron las fases 0 a 8 |
| `-i u` | Instalador sin firmar | `.exe` con NSIS y `.msi` con WiX. Va después de `-r`, que pondría `-i r` (que además hace `meson dist`) |

## 6. Probar el resultado

En este equipo está instalado **VLC 3.0.23** en `C:\Program Files\VideoLAN\VLC`.
El instalador de VLC 4 usa la misma carpeta y la misma entrada de «Programas instalados». Por eso, al ejecutarlo, ofrece desinstalar VLC 3 y lo sustituye.
Además, los dos comparten la configuración de `%APPDATA%\vlc`.

- **Para probar sin tocar VLC 3:** usa la carpeta portable (`D:\Proyectos\VLC-instaladores\vlc-win64-ucrt-<commit>\vlc.exe`).
  Lleva una subcarpeta `portable`, así que su configuración se guarda ahí y no en `%APPDATA%\vlc`.
- **Para instalarlo de verdad:** ejecuta el `.exe`. Como no está firmado, SmartScreen avisa: *Más información › Ejecutar de todas formas*.

## 7. Problemas conocidos y qué mirar

- **Es la primera vez que se compila el fork para Windows.** Las fases 0 a 8 se validaron en Linux (Xvfb).
  - El código exclusivo de Windows que tocan no se ha compilado nunca: el botón de pantalla completa de la barra de título en `mainctx_win32.cpp`.
  - Tampoco se ha visto la interfaz con el compositor de Windows (DirectComposition), ni el icono nuevo en el instalador.
  - Si falla la compilación, el error estará al final de `~/vlc-win/build-win.log` (busca `error:`).
- **Falla el paso del MSI pero hay `.exe`:** el script copia igualmente el `.exe` y termina con un aviso. El `.exe` es válido.
- **`detected dubious ownership`** al clonar: el script ya pasa `safe.directory`. Si aun así aparece, ejecuta
  `git config --global --add safe.directory /mnt/d/Proyectos/VLC`.
- **`Killed` o `signal 9` al compilar:** falta memoria. Usa `JOBS` y `.wslconfig` (apartado 2).
- **Empezar de cero:** borra `~/vlc-win` (o solo `~/vlc-win/win64-ucrt-meson` para rehacer la parte de VLC sin los contribs).
