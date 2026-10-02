# MILTV Universal Native

MILTV is being rebuilt as a **real Flutter application**. The UI and playback layer are native; this project does **not** wrap the GitHub Pages website in a WebView or TWA.

## Targets
- Android phones/tablets
- Android TV / Google TV / compatible Android TV boxes and Smart TVs
- Linux
- macOS
- Windows

A single APK is for Android-family devices. Linux/macOS/Windows are separate native desktop builds from the same codebase.

## Current native features
- Native Material 3 UI
- MediaKit native playback layer
- M3U parsing with channel metadata
- HLS/DASH-capable playback backend
- Search by channel/category/country
- Category filtering
- Favorites persisted locally
- Saved M3U sources
- Local account registration/login/logout for offline testing
- TV mode with larger cards
- Android TV manifest capabilities prepared in CI
- Argentina and worldwide IPTV-Org list shortcuts
- Responsive desktop/tablet player pane
- Automated M3U parser tests
- CI quality gate: `flutter analyze` + `flutter test`
- Android emulator smoke test in CI

## Authentication
The local login is a **development/offline account system**, not production-grade cloud identity. It must not be presented as a shared production account system. A real cloud authentication provider can be integrated once the project's real credentials/backend configuration are available.

## Streaming
Only load streams, catalogs and credentials that you own or are authorized to use. MILTV is a player/catalog application and does not bypass DRM, conditional access, encryption or paywalls.

## Build in GitHub Actions
1. Create a new GitHub repository for this native app.
2. Upload the contents of this folder to the repository root.
3. Push to `main` or run **Actions → MILTV Universal Build → Run workflow**.
4. The Android job runs static analysis, unit tests, an Android emulator smoke test, then publishes a universal APK plus split APKs.
5. The Linux, macOS and Windows jobs publish their respective native artifacts.

The workflow creates platform folders in CI so the repository stays small and portable.


## V4 — endurecimiento de la base

Esta revisión añade el punto de entrada real de Flutter (`main()`), inicialización de `media_kit`, pruebas M3U corregidas, soporte de librerías nativas de reproducción para Windows y manejo visible de errores del reproductor. En pantallas pequeñas el reproductor aparece integrado encima del catálogo al seleccionar un canal.

### Estado de validación

La fuente fue revisada y preparada para CI, pero el entorno de preparación no contiene el SDK de Flutter/Android; por eso la compilación final debe ser validada por GitHub Actions antes de publicar un APK.

### Contenido

- `flutter analyze` y `flutter test` antes de compilar.
- Smoke test de arranque en emulador Android.
- APK universal y APKs por ABI.
- Builds de Linux, macOS y Windows.
- Android TV con Leanback opcional, pantalla táctil no obligatoria y banner de TV.


## Autenticación cloud (producción)

MILTV puede usar Supabase Auth sin guardar contraseñas en el dispositivo. La app lee dos variables de compilación:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`

Si ambas están presentes, el flujo de registro/inicio de sesión usa Supabase; si no, queda disponible el modo local únicamente para pruebas.

En GitHub Actions se configuran como Secrets del repositorio con esos mismos nombres. No se debe colocar una `service_role`/secret key dentro de la aplicación.


## Fase 7 — Android TV / control remoto

- Focus traversal explícito para el catálogo.
- Resaltado visual del elemento enfocado.
- Activación de canales mediante Enter/Select del control remoto.
- Tarjetas ampliadas cuando está activo el modo TV.
- La compatibilidad final depende del dispositivo/firmware y se valida en CI y hardware real.


## Fase 10 — CI y reproducibilidad

- Versión nativa: `1.0.0+8`.
- CI normaliza el formato Dart antes de analizar y probar.
- Cada job tiene un límite de tiempo para evitar builds colgados indefinidamente.
- Se conserva la auditoría de APK/AAB y hashes SHA-256.
- Android TV mantiene `LEANBACK_LAUNCHER`, banner y navegación por D-pad.
- Esta fase no declara el APK como validado hasta que GitHub Actions complete la compilación real.

## Fase 9 — QA del reproductor

- Timeout de 15 s para detectar streams que no llegan a iniciar.
- Estado de buffering conectado a la interfaz del reproductor.
- Cancelación segura de timers y suscripciones al salir de la pantalla.
- La compilación final sigue dependiendo de Flutter/Gradle en CI y de una prueba en hardware real.
