# Sevilla FC — proyecto nativo para iPhone

Proyecto SwiftUI para iOS 16 o posterior. Está creado como código fuente; **no es un IPA compilado ni firmado**.

## Incluye
- Nombre e identidad visual Sevilla FC, escudo e imagen de Jesús Navas.
- Secciones TV, Películas, Series y Favoritos, además de búsqueda.
- Añadir varias listas M3U/M3U8 mediante URL y guardar las URL localmente.
- Importar un archivo M3U desde Archivos.
- Reproducción integrada con AVPlayer.

## Limitaciones actuales
- Las categorías Películas/Series se infieren de `group-title` y del nombre de cada elemento en la lista. Algunas listas pueden clasificar contenido de forma distinta.
- AVPlayer no admite todos los protocolos/códecs que puede admitir VLC. En particular, algunas listas IPTV con formatos o streams no compatibles con iOS pueden no reproducirse. Esta app usa el reproductor nativo de iOS, no libVLC.
- El archivo importado desde Archivos se añade a la sesión actual; las listas por URL sí se guardan para recargarlas.
- No incluye listas de canales ni contenido audiovisual.

## Compilar desde un PC Windows
Apple no permite compilar una app iOS nativa localmente con Windows: hace falta macOS/Xcode en algún punto. Desde Windows puedes usar un servicio de compilación en la nube como Codemagic:

1. Descomprime el ZIP.
2. Sube la carpeta `SevillaFC_iPhone` a un repositorio privado de GitHub.
3. Crea una cuenta en Codemagic y conecta ese repositorio.
4. Selecciona el proyecto Xcode `SevillaFC.xcodeproj` y el esquema `SevillaFC`.
5. Para instalarla en un iPhone real, configura firma de código de Apple. La distribución por TestFlight/App Store requiere una cuenta del Apple Developer Program.
6. Inicia la compilación en la nube. Descarga el artefacto generado y sigue el método de instalación que permita la firma seleccionada.

## Ajustes del proyecto
- Bundle ID: `com.sevillafc.player` (cámbialo si está ocupado).
- Deployment target: iOS 16.0.
- Frameworks: SwiftUI, AVKit, UniformTypeIdentifiers.

El código fuente se entrega sin afirmar que haya sido compilado o probado en Xcode en este entorno.
