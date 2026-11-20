# fase16/01_tratte.jl: le 256 tratte del test DoE di fase12 passo 8a (gruppi 15 e 16, senza la 14664, seme 20261117),
# ricostruite come in fase12/01_test.jl e confrontate con la lista salvata allora (fase12_log/01_griglia_tratte.csv).
# Scrive ~/Documents/lavoro/ml_treno_dati/fase16/tratte.txt (route_id separati da virgole). Lanciato da fase16/lancia.sh.

using Arrow, Random
const BASE = expanduser("~/Documents/lavoro/ml_treno_dati")
const DAT = joinpath(BASE, "fase16"); mkpath(DAT)
tt = Arrow.Table(joinpath(BASE, "P9_D28_16384", "tabella", "test.arrow"))
sort(unique(Int.(tt.gruppo))) == [15, 16] || error("non è il test")
const TRATTE = [r for r in sort(unique(Int.(tt.tratta))) if r != 14664]
const CAMPIONE = sort(TRATTE[randperm(Xoshiro(20261117), length(TRATTE))[1:256]])
f12 = sort([parse(Int, split(l, ',')[1]) for l in readlines(joinpath(BASE, "fase12_log", "01_griglia_tratte.csv"))[2:end]])
CAMPIONE == f12 || error("il campione non è quello di fase12 passo 8a")
write(joinpath(DAT, "tratte.txt"), join(CAMPIONE, ','))
println("01_tratte: ", length(CAMPIONE), " tratte del test (su ", length(TRATTE), "), uguali a quelle di fase12 passo 8a, da ", CAMPIONE[1], " a ", CAMPIONE[end])
