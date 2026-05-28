#!/usr/bin/env bash
# Rasterize docs/design/assets/logo-mark.svg into all platform app-icon
# sizes (iOS, Android mipmaps, Web/PWA, favicon, Apple touch icon).
#
# Tooling preference (auto-detected, first match wins):
#   1. rsvg-convert  (Debian/Ubuntu: apt install librsvg2-bin; macOS: brew install librsvg)
#   2. inkscape      (apt install inkscape; macOS: brew install --cask inkscape)
#   3. magick / convert (ImageMagick — fallback, may rasterize less crisply)
#
# Run from repo root: bash tools/export_icons.sh
# Idempotent: re-runs overwrite existing files with identical output.
#
# Output paths:
#   ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-*.png
#   android/app/src/main/res/mipmap-{m,h,xh,xxh,xxxh}dpi/ic_launcher.png
#   web/icons/Icon-{192,512}.png
#   web/icons/Icon-maskable-{192,512}.png
#   web/icons/apple-touch-icon-180.png
#   web/favicon.png

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_SVG="${REPO_ROOT}/docs/design/assets/logo-mark.svg"

if [ ! -f "${SRC_SVG}" ]; then
  echo "ERROR: master SVG not found at ${SRC_SVG}" >&2
  exit 1
fi

# ---- Renderer detection -----------------------------------------------------
RENDERER=""
if command -v rsvg-convert >/dev/null 2>&1; then
  RENDERER="rsvg"
elif command -v inkscape >/dev/null 2>&1; then
  RENDERER="inkscape"
elif command -v magick >/dev/null 2>&1; then
  RENDERER="magick"
elif command -v convert >/dev/null 2>&1; then
  RENDERER="convert"
else
  cat >&2 <<EOF
ERROR: no SVG renderer found. Install one of:
  - rsvg-convert   (apt install librsvg2-bin  /  brew install librsvg)
  - inkscape       (apt install inkscape     /  brew install --cask inkscape)
  - imagemagick    (apt install imagemagick  /  brew install imagemagick)
EOF
  exit 2
fi
echo "Using renderer: ${RENDERER}"

# render <size_px> <output_path>
render() {
  local size="$1"
  local out="$2"
  mkdir -p "$(dirname "${out}")"
  case "${RENDERER}" in
    rsvg)
      rsvg-convert -w "${size}" -h "${size}" -o "${out}" "${SRC_SVG}"
      ;;
    inkscape)
      inkscape --export-type=png --export-width="${size}" \
               --export-height="${size}" --export-filename="${out}" \
               "${SRC_SVG}" >/dev/null
      ;;
    magick)
      magick -background none -density 384 "${SRC_SVG}" \
             -resize "${size}x${size}" "${out}"
      ;;
    convert)
      convert -background none -density 384 "${SRC_SVG}" \
              -resize "${size}x${size}" "${out}"
      ;;
  esac
}

# ---- iOS --------------------------------------------------------------------
IOS_DIR="${REPO_ROOT}/ios/Runner/Assets.xcassets/AppIcon.appiconset"
mkdir -p "${IOS_DIR}"

# All unique pixel sizes Apple ships in the AppIcon set
IOS_SIZES=(20 29 40 58 60 76 80 87 120 152 167 180 1024)
for sz in "${IOS_SIZES[@]}"; do
  render "${sz}" "${IOS_DIR}/Icon-App-${sz}x${sz}.png"
done

# ---- Android mipmaps --------------------------------------------------------
declare -A ANDROID_MIPMAPS=(
  [mdpi]=48
  [hdpi]=72
  [xhdpi]=96
  [xxhdpi]=144
  [xxxhdpi]=192
)
for dpi in "${!ANDROID_MIPMAPS[@]}"; do
  render "${ANDROID_MIPMAPS[$dpi]}" \
         "${REPO_ROOT}/android/app/src/main/res/mipmap-${dpi}/ic_launcher.png"
done

# ---- Web --------------------------------------------------------------------
render 192 "${REPO_ROOT}/web/icons/Icon-192.png"
render 512 "${REPO_ROOT}/web/icons/Icon-512.png"
render 192 "${REPO_ROOT}/web/icons/Icon-maskable-192.png"
render 512 "${REPO_ROOT}/web/icons/Icon-maskable-512.png"
render 180 "${REPO_ROOT}/web/icons/apple-touch-icon-180.png"
render 32  "${REPO_ROOT}/web/favicon.png"

echo "Done. All app-icon assets regenerated."
