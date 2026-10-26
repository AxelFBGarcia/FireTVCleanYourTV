# Mi fondo

Una foto fija: `wallpaper.jpg` aquí mismo. Varias que roten: en `wallpapers/`, con
`wallpaper_rotation_minutes` mayor que 0 en `config.json`. Para enviarlas a la tele:

    TV_HOST=192.168.1.70 tools/theme.sh fireos/tema

- Una sola foto también sirve: con una, simplemente no rota.
- Mejor oscuras, 1920×1080 y de menos de ~300 KB: el texto y el dock están pensados sobre negro, y la
  tele decodifica la imagen en memoria cada vez que vuelve al inicio. Para achicar una foto en la Mac:
  `sips -Z 1920 -s formatOptions 75 foto.jpg --out wallpapers/foto.jpg`
- `config.json`: foto fija (`wallpaper_rotation_minutes: 0`), oscurecida 15 % (`wallpaper_dim`, 0–90; la
  foto ya viene más oscura arriba y abajo), dock de vidrio translúcido para que se vea el fondo. Todas las opciones
  están en `themes/README.md`.
- Para quitar el tema: `TV_HOST=192.168.1.70 tools/theme.sh --reset` (la configuración de Fire TV no se
  pierde: vive en el APK).
