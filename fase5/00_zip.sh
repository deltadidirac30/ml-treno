#!/bin/zsh
# fase5/00_zip.sh: passo 0, integrità dello zip delle 16384 tratte DoE ed estrazione.
#   zsh fase5/00_zip.sh
# Lo zip è stato creato sul PC Windows con .NET (ZipFile.CreateFromDirectory, cartella base inclusa): le voci
# hanno "\" come separatore (host "fat"). unzip di Info-ZIP lo segnala ("appears to use backslashes as path
# separators") e li converte in "/": dopo l'estrazione si controlla che nessun nome contenga "\".
# Attesi (dal PC): 81 921 voci, 65 943 374 byte non compressi.
set -e
Z=~/Documents/lavoro/train-powertrain/campagne/tratte_doe_16384.zip
B=~/Documents/lavoro/ml_treno_dati
D=$B/tratte_doe_16384
L=$B/fase5_log
mkdir -p $L
stat -f "%z byte" $Z
unzip -t $Z > $L/unzip_t.txt                       # CRC di tutte le voci; exit ≠ 0 se lo zip non è integro
echo "voci OK: $(grep -c ' OK$' $L/unzip_t.txt)"     # attese 81921
tail -1 $L/unzip_t.txt
zipinfo $Z > $L/zipinfo.txt
tail -1 $L/zipinfo.txt                              # attesi "81921 files, 65943374 bytes uncompressed"
awk 'NR>2 && $1 ~ /^-/ {s+=$4; n++} END {printf "file %d, byte %d\n", n, s}' $L/zipinfo.txt
echo "voci con '..': $(zipinfo -1 $Z | grep -c '\.\.' || true)"   # attese 0
shasum -a 256 $Z | tee $L/sha256.txt
[[ -e $D ]] && { echo "$D esiste già: non sovrascrivo"; exit 1 }
unzip -q $Z -d $B 2> $L/unzip_estrazione.txt || true    # exit 1 solo per l'avviso sui "\"
cat $L/unzip_estrazione.txt
echo "file estratti: $(find $D -type f | wc -l)"        # attesi 81921
echo "byte estratti: $(find $D -type f -exec stat -f %z {} + | awk '{s+=$1} END {print s}')"   # attesi 65943374
echo "nomi con '\\': $(find $B/tratte_doe_16384 | grep -c '\\' || true)"   # attesi 0
echo "cartelle route: $(find $D -mindepth 1 -maxdepth 1 -type d -name 'route_*' | wc -l)"   # attese 16384
