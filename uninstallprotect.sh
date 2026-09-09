#!/usr/bin/env bash
set -euo pipefail
STATE_FILE="/var/lib/zxv-official-protect/state"
NC='\033[0m'; GREEN='\033[1;32m'; RED='\033[1;31m'; CYAN='\033[1;36m'
[[ $EUID -eq 0 ]] || { printf "${RED}[-]${NC} Root diperlukan.\n"; exit 1; }
[[ -f "$STATE_FILE" ]] || { printf "${RED}[-]${NC} Tidak ada backup ZXV OFFICIAL.\n"; exit 1; }
BACKUP_DIR="$(cat "$STATE_FILE")"; MANIFEST="$BACKUP_DIR/manifest"
[[ -f "$MANIFEST" ]] || { printf "${RED}[-]${NC} Manifest tidak ditemukan.\n"; exit 1; }
printf "${CYAN}[@]${NC} Restore: %s\n" "$BACKUP_DIR"
while IFS='|' read -r kind target backup; do
  [[ -n "$target" ]] || continue
  if [[ "$kind" == "EXIST" ]]; then mkdir -p "$(dirname "$target")"; cp -a "$backup" "$target"; printf "${GREEN}[+]${NC} Restored: %s\n" "$target"; elif [[ "$kind" == "NEW" ]]; then rm -f "$target"; printf "${GREEN}[+]${NC} Removed: %s\n" "$target"; fi
done < "$MANIFEST"
rm -f "$STATE_FILE"
if [[ -f /var/www/pterodactyl/artisan ]] && command -v php >/dev/null 2>&1; then (cd /var/www/pterodactyl && php artisan optimize:clear >/dev/null 2>&1) || true; fi
printf "${GREEN}[+]${NC} ZXV OFFICIAL Protect berhasil di-uninstall.\n"
