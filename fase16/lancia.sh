#!/bin/bash
# fase16/lancia.sh: verifica indipendente della strategia G su 256 tratte DoE del test, mai usate per metterla a punto.
#
#   cd "$ML" && nohup caffeinate -i bash fase16/lancia.sh >> ~/Documents/lavoro/ml_treno_dati/fase16_log/log.txt 2>&1 &
#
# 1. 01_tratte.jl: le 256 tratte di fase12 passo 8a.
# 2. Il surrogato com'è (surrogato/usa_surrogato.jl, invariato; rete_6b, margine=si), strategia G e poi semplice, sulle 256 tratte
#    in un solo lancio ciascuna (-t 8). Lo strumento scrive le sue cartelle per tratta in ml_treno_dati/surrogato/route_<id> e un
#    riepilogo_<data>.csv: qui vengono spostati in ml_treno_dati/fase16 (surrogato_G/, surrogato_semplice/, riepilogo_*.csv).
#    Le 16 cartelle route_<id> che esistevano già in surrogato/ da lanci precedenti sono copiate prima in fase16/surrogato_prima
#    e rimesse al loro posto alla fine: surrogato/ resta com'era.
# 3. 02_griglia.jl: la griglia fitta simulata, l'ottimo vero (si riprende tratta per tratta).
# 4. 03_confronto.jl: le metriche di fase13/08 sulle 256 tratte, accanto alle 146 linee reali.
# 5. copia di log, tabelle e figura in fase16/risultati e fase16/figure.
# Si può rilanciare: i passi già fatti si saltano.
set -euo pipefail
ML="$(cd "$(dirname "$0")/.." && pwd)"
B="$HOME/Documents/lavoro/ml_treno_dati"; D="$B/fase16"; LOG="$B/fase16_log"; SUR="$B/surrogato"
mkdir -p "$D" "$LOG"
cd "$ML"
echo "== $(date '+%F %T') fase16/lancia.sh"

# 1
julia --project=fase16 fase16/01_tratte.jl
IDS=$(cat "$D/tratte.txt")
DIRS=$(echo "$IDS" | tr ',' '\n' | awk '{printf "route_%06d\n", $1}')

# 2
if [ ! -f "$D/surrogato_prima/.fatto" ]; then
  mkdir -p "$D/surrogato_prima"
  for d in $DIRS; do if [ -d "$SUR/$d" ]; then cp -Rp "$SUR/$d" "$D/surrogato_prima/"; fi; done
  touch "$D/surrogato_prima/.fatto"
  echo "surrogato/: $(ls "$D/surrogato_prima" | wc -l | tr -d ' ') cartelle già presenti copiate in fase16/surrogato_prima"
fi
for S in G semplice; do
  if [ -f "$D/riepilogo_$S.csv" ]; then echo "surrogato $S: già fatto"; continue; fi
  echo "== $(date '+%F %T') surrogato, strategia $S"
  julia -t 8 --project=surrogato surrogato/usa_surrogato.jl doe="$IDS" strategia=$S margine=si > "$LOG/01_surrogato_$S.txt" 2>&1
  tail -3 "$LOG/01_surrogato_$S.txt"
  R=$(grep '^Riepilogo in ' "$LOG/01_surrogato_$S.txt" | sed 's/^Riepilogo in //')
  mkdir -p "$D/surrogato_$S"
  for d in $DIRS; do
    if [ -d "$SUR/$d" ]; then /bin/rm -rf "$D/surrogato_$S/$d"; mv "$SUR/$d" "$D/surrogato_$S/"; fi
  done
  mv "$R" "$D/riepilogo_$S.csv"
done
if [ ! -f "$D/surrogato_prima/.rimesse" ]; then
  for d in $DIRS; do
    if [ -d "$D/surrogato_prima/$d" ]; then /bin/rm -rf "$SUR/$d"; cp -Rp "$D/surrogato_prima/$d" "$SUR/"; fi
  done
  touch "$D/surrogato_prima/.rimesse"
  echo "surrogato/: cartelle di prima rimesse al loro posto"
fi

# 3
echo "== $(date '+%F %T') griglia fitta"
julia -t 8 --project=fase16 fase16/02_griglia.jl >> "$LOG/log_02.txt" 2>&1
tail -1 "$LOG/02_griglia.txt"

# 4
echo "== $(date '+%F %T') confronto"
julia --project=fase16 fase16/03_confronto.jl > "$LOG/log_03.txt" 2>&1

# 5
cp "$LOG"/01_surrogato_*.txt "$LOG"/02_griglia.txt "$LOG"/02_tempi.csv "$LOG"/03_confronto.txt "$LOG"/03_ottimo_tratte.csv \
   "$LOG"/log.txt "$LOG"/log_02.txt "$LOG"/log_03.txt "$D"/riepilogo_G.csv "$D"/riepilogo_semplice.csv "$ML/fase16/risultati/"
cp "$LOG"/fig_ottimo_test.png "$ML/fase16/figure/"
echo "== $(date '+%F %T') fine"
