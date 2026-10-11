#!/bin/zsh
# Ottimizzazione delle 5 tratte reali in andata e ritorno con il runner di train-powertrain (2026-10-10,
# commit c47dc17), con i due ottimizzatori. Uscita fuori dal repo e da Google Drive.
D=/Users/kairos/Documents/lavoro/ml_treno_dati
cd /Users/kairos/Documents/lavoro/train-powertrain
julia -t 5 --project=julia julia/scripts/esegui_campagna.jl modalita=ottimizza tratte=reali \
    cartella=$D/2026-10-10_ottimizza_corretta_ar_reali 'direzioni=andata&ritorno' modello=corretta > $D/log_attuale.txt 2>&1
julia -t 1 --project=julia julia/scripts/esegui_campagna.jl modalita=ottimizza ottimizzatore=nomad_pb processi=5 tratte=reali \
    cartella=$D/2026-10-10_ottimizza_nomad_corretta_ar_reali 'direzioni=andata&ritorno' modello=corretta > $D/log_nomad.txt 2>&1
