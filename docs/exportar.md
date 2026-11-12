# Exportar el juego (Windows, Linux y Android)

Los presets están en `apps/game/export_presets.cfg` (versionado). Los builds salen en `apps/game/export/` (ignorado por git).

| Comando | Resultado |
| ------- | --------- |
| `pnpm game:export:linux` | `export/linux/UrbanCraft.x86_64` (un solo archivo, con el `.pck` embebido) |
| `pnpm game:export:windows` | `export/windows/UrbanCraft.exe` (un solo archivo) |
| `pnpm game:export:android` | `export/android/UrbanCraft.apk` firmado con tu llave de release |
| `pnpm game:export:android:debug` | `export/android/UrbanCraft-debug.apk` (llave de debug, para probar) |
| `pnpm game:export` | los tres de release |

Los builds de release se conectan a `https://urbancraft.droni.vip` y no muestran las herramientas de depuración (usuarios de prueba, sección Depuración).

## 1. Una sola vez: plantillas de exportación

Tienen que ser **exactamente** de la versión de Godot que usas (`godot --version`, ahora 4.7.2.stable):

- Editor → **Editor → Gestionar plantillas de exportación → Descargar e instalar**, o
- descarga `Godot_v4.7.2-stable_export_templates.tpz` de godotengine.org, y descomprímelo (es un zip) en
  `~/.local/share/godot/export_templates/4.7.2.stable/` (los archivos sueltos, sin la carpeta `templates/`).

Si actualizas Godot, hay que bajar las plantillas nuevas.

## 2. Linux y Windows

Con las plantillas basta: `pnpm game:export:linux` y `pnpm game:export:windows`.

- **Linux:** distribúyelo en un `.tar.gz` (conserva el permiso de ejecución). Requiere OpenGL 3.3 / GLES3 (renderer Compatibility).
- **Windows:** sin firma de código, Windows SmartScreen mostrará "Editor desconocido" (Más información → Ejecutar de todas formas). Un certificado de firma lo quita, pero cuesta dinero.
- **Ícono del .exe:** está desactivado (`application/modify_resources=false`) porque desde Linux necesita `rcedit` + `wine`. Para activarlo: crea un `icon.ico` (256×256, varios tamaños), configura `rcedit` en Configuración del editor → Exportar → Windows, y pon `application/icon="res://icon.ico"` y `application/modify_resources=true`.
- **Versión:** al publicar una nueva, sube `config/version` en `project.godot` y `application/file_version` / `product_version` en el preset de Windows.

## 3. Android

### Herramientas (una sola vez)

1. **JDK 17** (Arch/CachyOS: `sudo pacman -S jdk17-openjdk`).
2. **Android SDK** en `~/Android/Sdk`. Con Android Studio, o solo con las *command-line tools* (`commandlinetools-linux-*_latest.zip` de developer.android.com, descomprimidas en `~/Android/Sdk/cmdline-tools/latest/`):
   ```bash
   export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
   SM=~/Android/Sdk/cmdline-tools/latest/bin/sdkmanager
   yes | $SM --sdk_root=$HOME/Android/Sdk --licenses
   $SM --sdk_root=$HOME/Android/Sdk "platform-tools" "build-tools;36.1.0" "platforms;android-36"
   ```
   Son las versiones que pide Godot 4.7.2. Para otra versión de Godot, míralas en su plantilla:
   `unzip -p ~/.local/share/godot/export_templates/<versión>/android_source.zip config.gradle | grep -E "compileSdk|buildTools"`.
3. En el editor: **Configuración del editor → Exportar → Android**: `Java SDK Path` (p. ej. `/usr/lib/jvm/java-17-openjdk`) y `Android SDK Path`.
4. **Llave de debug** (para `game:export:android:debug`):
   ```bash
   mkdir -p ~/.local/share/godot/keystores
   keytool -genkeypair -v -keystore ~/.local/share/godot/keystores/debug.keystore -storepass android \
     -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 \
     -dname "CN=Android Debug,O=Android,C=US"
   ```

### Llave de release (¡guárdala para siempre!)

Todas las versiones futuras de la app deben firmarse con **la misma llave**: si la pierdes, no podrás actualizar la app instalada (ni en Google Play). Guárdala fuera del repo y con respaldo.

```bash
keytool -genkeypair -v -keystore ~/claves/urbancraft-release.keystore -alias urbancraft \
  -keyalg RSA -keysize 2048 -validity 10000
```

Godot la toma de variables de entorno (así no queda en ningún archivo del proyecto):

```bash
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=~/claves/urbancraft-release.keystore
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=urbancraft
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD='tu-contraseña'
pnpm game:export:android
```

(También se puede poner en Proyecto → Exportar → Android → Keystore; Godot lo guarda en `.godot/export_credentials.cfg`, que no se versiona.)

### Probar en un teléfono

Activa *Opciones de desarrollador → Depuración USB*, conéctalo y:

```bash
adb install -r apps/game/export/android/UrbanCraft.apk
```

### A tener en cuenta

- **Paquete:** `co.droni.urbancraft`. Es el id permanente de la app (Google Play no deja cambiarlo después).
- **version/code:** súbelo en 1 en cada versión que publiques (Android no instala encima un código igual o menor). `version/name` es el texto visible (`0.1.0`).
- **Solo arm64-v8a:** cubre los teléfonos actuales. Para teléfonos de 32 bits muy viejos, activa `armeabi-v7a` (el APK pesa más).
- **Ubicación:** el GPS nativo aún no está implementado (ver `LocationService`): en Android la posición sale de la IP, como en PC. Cuando se agregue el plugin habrá que pedir el permiso `ACCESS_FINE_LOCATION`.
- **Login con Google:** abre el navegador del teléfono y el juego espera la respuesta; no necesita configuración extra.
- **Google Play** exige **AAB**, no APK. Para eso: instala la plantilla de Gradle (`godot --headless --path apps/game --install-android-build-template --export-release Android ...` o Proyecto → Instalar plantilla de compilación de Android), y en el preset `gradle_build/use_gradle_build=true` y `gradle_build/export_format=1`. Para repartir el APK directamente (o en pruebas internas) no hace falta.

## Lista antes de publicar

- [ ] El backend en la nube está desplegado con las migraciones al día.
- [ ] `config/version` (y la versión del preset de Windows / `version/code` y `version/name` de Android) actualizados.
- [ ] Probado el build de release (no el editor) en cada plataforma: login con Google, mapa, multijugador, amigos.
- [ ] La llave de release de Android respaldada.
