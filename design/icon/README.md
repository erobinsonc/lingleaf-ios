# App icon sources

Masters for the Lingleaf icon (same files in lingleaf-ios and lingleaf-android).

- `icon-full-1024.png`: full-bleed square, no transparency. iOS `AppIcon` and the App Store.
- `icon-foreground-1024.png`: the leaf on transparency, scaled to fit Android's adaptive-icon
  safe zone (a centred circle of about 61% of the canvas).
- `icon-background-1024.png`: the green gradient, full bleed.
- `icon-monochrome-1024.png`: white leaf silhouette for Android 13+ themed icons.

The platforms add their own rounded corners or masks: never bake corners, borders or an outer
shadow into these files.
