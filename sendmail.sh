#!/usr/bin/env bash
# Sendet für jede Zeile einer CSV-Datei eine Mail über ein Thunderbird-Compose-Fenster.
# Platzhalter im Template werden durch die CSV-Werte ersetzt.
#
# Einschränkung: CSV-Felder dürfen keine Kommas enthalten (auch nicht in Anführungszeichen).
#
# Verwendung:
#   ./sendmail.sh --csv DATEI --template DATEI --email-column SPALTENNAME
#
# Voraussetzungen:
#   - thunderbird muss im PATH sein
#   - envsubst muss im PATH sein (macOS: brew install gettext && brew link gettext)
#   - xxd muss im PATH sein (auf macOS standardmäßig vorhanden)

set -euo pipefail

usage() {
    cat <<EOF
Verwendung: $0 --csv DATEI --template DATEI --email-column SPALTENNAME

  --csv           Pfad zur CSV-Datei (Komma-getrennt, erste Zeile = Header)
  --template      Pfad zur Template-Datei (erste Zeile = Betreff, Rest = Body)
  --email-column  Name der Spalte, die die Empfänger-E-Mail-Adresse enthält
EOF
    exit 1
}

CSV=""
TEMPLATE=""
EMAIL_COLUMN=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --csv)           CSV="$2";          shift 2 ;;
        --template)      TEMPLATE="$2";     shift 2 ;;
        --email-column)  EMAIL_COLUMN="$2"; shift 2 ;;
        *) echo "Unbekannter Parameter: $1" >&2; usage ;;
    esac
done

[[ -z "$CSV" || -z "$TEMPLATE" || -z "$EMAIL_COLUMN" ]] && usage

[[ -f "$CSV" ]]      || { echo "Fehler: CSV-Datei nicht gefunden: $CSV" >&2; exit 1; }
[[ -f "$TEMPLATE" ]] || { echo "Fehler: Template-Datei nicht gefunden: $TEMPLATE" >&2; exit 1; }

command -v thunderbird >/dev/null 2>&1 \
    || { echo "Fehler: 'thunderbird' nicht im PATH gefunden." >&2; exit 1; }
command -v envsubst >/dev/null 2>&1 \
    || { echo "Fehler: 'envsubst' nicht im PATH gefunden. macOS: brew install gettext && brew link gettext" >&2; exit 1; }

SUBJECT_TEMPLATE=$(head -n1 "$TEMPLATE" | tr -d '\r')
BODY_TEMPLATE=$(tail -n+3 "$TEMPLATE" | tr -d '\r')

IFS=',' read -ra HEADERS < <(head -n1 "$CSV" | tr -d '\r')

EMAIL_IDX=-1
for i in "${!HEADERS[@]}"; do
    if [[ "${HEADERS[$i]}" == "$EMAIL_COLUMN" ]]; then
        EMAIL_IDX=$i
        break
    fi
done

[[ $EMAIL_IDX -eq -1 ]] && {
    echo "Fehler: Spalte '$EMAIL_COLUMN' nicht in CSV-Header gefunden." >&2
    echo "Vorhandene Spalten: ${HEADERS[*]}" >&2
    exit 1
}

ROW=0
while IFS=',' read -ra FIELDS; do
    [[ "${#FIELDS[@]}" -eq 0 ]] && continue

    # Alle Spaltenwerte als Umgebungsvariablen exportieren
    for i in "${!HEADERS[@]}"; do
        export "${HEADERS[$i]}"="${FIELDS[$i]:-}"
    done

    RECIPIENT="${FIELDS[$EMAIL_IDX]}"
    SUBJECT=$(envsubst <<< "$SUBJECT_TEMPLATE")
    BODY=$(envsubst <<< "$BODY_TEMPLATE")

    echo "[$((++ROW))] Öffne Compose-Fenster für: $RECIPIENT"
    thunderbird -compose "to='${RECIPIENT}',subject='${SUBJECT}',body='${BODY}'" &

    sleep 2
done < <(tail -n+2 "$CSV")

echo "Fertig. $ROW Compose-Fenster geöffnet."
