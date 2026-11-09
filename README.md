# Textura

Editor de archivos de texto para iPhone con interfaz Liquid Glass.

- Abre **cualquier archivo**: `.txt`, `.ini`, `.cfg`, `.json`, `.xml`, `.lua`, `.pnach`, `.cht`, `.patch`, `.log`…
- **Archivos binarios** (parches `.ips`, `.bps`, `.ups`, ROMs…) en un editor **hexadecimal** con paginación, ir a offset y búsqueda de bytes.
- Detecta la codificación (UTF-8, UTF-16, Windows-1252, Shift-JIS…) y **conserva el final de línea** (LF / CRLF / CR).
- Buscar y reemplazar nativo, deshacer/rehacer, ir a línea, barra de símbolos sobre el teclado.
- Abre carpetas completas, y crea, renombra, duplica y elimina archivos.
- Guarda **en el propio archivo** (Archivos, iCloud, etc.).

## Compilar el IPA

1. Crea un repositorio en GitHub y sube **todo el contenido** de esta carpeta (incluida `.github/`).
2. Ve a la pestaña **Actions** y ejecuta **Compilar IPA (sin firmar)** (se lanza solo con cada push).
3. Al terminar, descarga el artefacto **Textura-IPA-sin-firmar** (es un ZIP que contiene `Textura.ipa`).
4. Si creas una etiqueta (`git tag v1.0.0 && git push --tags`), el IPA también se publica en **Releases**.

El workflow usa el runner `xcode-27` (Xcode 27, SDK de iOS 27). Si tu cuenta no lo tiene, define la
variable de repositorio `RUNNER` con el valor `macos-26`, o lanza el workflow a mano y elige `macos-26`.

Si la compilación falla, se sube el artefacto **build-log** con el registro completo.

## Instalar

- **SideStore**: abre el IPA con SideStore (compartir → SideStore), o *My Apps → +* y elige el archivo.
- **LiveContainer**: pulsa **+** y selecciona el IPA; luego ábrela desde LiveContainer.

El IPA no está firmado: SideStore y LiveContainer lo firman al instalarlo.
El Bundle ID (`com.textura.editor`) puede cambiarse en `project.yml`.

> Nota sobre LiveContainer: la app se ejecuta dentro del contenedor, así que «Abrir con Textura» desde
> Archivos no funcionará. Usa el botón **Abrir archivo** dentro de la app.

## Estructura

```
project.yml                  Definición del proyecto (XcodeGen)
.github/workflows/build.yml  Compilación y empaquetado del IPA
Textura/                     Código fuente SwiftUI y recursos
