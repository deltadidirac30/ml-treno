#!/bin/zsh
# fase4/00_zip.sh: passo 0, integrità dello zip della campagna P9_D28_16384 ed estrazione in raw/.
#   zsh fase4/00_zip.sh
# Lo zip (tar di Windows, con data descriptor) contiene P9_D28_16384/blocco_XX/{registro.csv,config.txt} con il
# prefisso "./" e "../errori_P9_D28_16384.csv" (percorso che risale): si estraggono solo le voci P9_D28_16384/*
# dentro raw/, e il file degli errori si scrive esplicitamente in raw/ con unzip -p (niente fuori da raw/).
set -e
Z=~/Documents/lavoro/train-powertrain/campagne/registri_P9_D28_16384.zip
D=~/Documents/lavoro/ml_treno_dati/P9_D28_16384
mkdir -p $D/raw $D/arrow $D/log
stat -f "%z byte" $Z
unzip -l $Z > $D/log/unzip_l.txt
unzip -t $Z > $D/log/unzip_t.txt              # CRC di tutte le voci; si ferma con exit ≠ 0 se lo zip non è integro
grep -c "OK$" $D/log/unzip_t.txt                # attese 129
shasum -a 256 $Z | tee $D/log/sha256.txt
unzip -q -o $Z "./P9_D28_16384/*" -d $D/raw
unzip -p $Z "../errori_P9_D28_16384.csv" > $D/raw/errori_P9_D28_16384.csv
find $D/raw -type f | wc -l                     # attesi 129
