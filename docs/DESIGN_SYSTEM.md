# Design System OneFacility

## Identidad visual

La paleta oficial se compone de:

| Token de marca | Valor | Uso principal |
| --- | --- | --- |
| Navy 900 | `#002E42` | Sidebar, fondos institucionales y texto de alta jerarquía |
| Blue 700 | `#005A8C` | Acciones principales, navegación activa y foco |
| Brown 900 | `#4F2304` | Acentos sobrios y contenido institucional puntual |
| Brown 700 | `#994608` | Acento interactivo y estados destacados |
| Background | `#F6F9FB` | Fondo general de la aplicación |
| Surface muted | `#EEF5F8` | Superficies secundarias y controles agrupados |
| Border | `#D8E4EA` | Bordes de cards, inputs y separadores |

Los tokens semánticos compatibles con shadcn/ui viven en `src/index.css`. Las
clases opcionales `onefacility.*` están declaradas en `tailwind.config.ts`.

## Tipografía

El manual de marca recomienda Proxima Nova ExtraBold. Como sus archivos y
licencia no están incluidos en el repositorio, la aplicación usa el fallback
seguro `Inter, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI",
sans-serif`. No se debe agregar Proxima Nova sin licencia y archivos oficiales.

## Assets

- `logo-primary.png`: versión completa sobre superficies claras.
- `isotipo-primary.png`: navegación colapsada, favicon visual y marca de agua.
- `wordmark-primary.png`: encabezados compactos sobre superficies claras.
- Los logos deben conservar proporción, espacio libre y colores originales.
- Sobre fondo navy, usar una superficie blanca o una versión monocromática
  mediante tratamiento CSS sólo cuando funcione como marca de agua decorativa.

## Componentes

- **Sidebar:** fondo Navy 900, texto blanco, estado activo Blue 700 y hover
  blanco al 8 %. El logo completo se usa expandido y el isotipo al colapsar.
- **Login:** panel institucional Navy 900 en desktop y card blanca elevada. En
  mobile se compacta a una columna sin perder el logo ni el formulario.
- **Botón primario:** Blue 700 con texto blanco. Reservar Brown 700 para acentos,
  no para la acción dominante de cada pantalla.
- **Cards:** fondo blanco, radio `0.75rem`, borde sutil y sombra suave.
- **Inputs:** borde neutral, foco Blue 700 y altura cómoda de al menos 40 px.
- **Tablas:** encabezados sobrios, separadores `--of-border` y acciones alineadas.
- **Badges:** usar color semántico y evitar más de un badge dominante por fila.

Esta base no redefine todavía el diseño interno de Dashboard, Administración,
Perfil, Solicitudes u Órdenes de trabajo; esos módulos deben migrarse de manera
incremental usando estos tokens.
