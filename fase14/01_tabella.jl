# fase14/01_tabella.jl: la tabella su cui si sceglie la flotta di treni standard (punto 5, classificazione degli ottimi).
# Dalla griglia fitta simulata (fase13/02: 146 linee non elettrificate oltre il 70%, dati del 17/11, 9702 progetti per linea):
#   - costo C[i, j] del treno j sulla linea i [€/km], Inf se il progetto non è fattibile su quella linea;
#   - extra-costo R[i, j] = C[i, j] / C*[i] − 1, dove C*[i] è l'ottimo della linea i;
#   - taglie del treno j: potenza nominale della fuel cell [kW] e capacità della batteria [kWh] (controllo: uguali su tutte le linee);
#   - massa del serbatoio [kg] di ogni treno su ogni linea (il simulatore lo dimensiona linea per linea: da discutere per i treni standard).
# Poi la riduzione: si tolgono i treni che non funzionano su nessuna linea e quelli "dominati" (un altro treno funziona almeno sulle
# stesse linee e costa al più quanto lui su ognuna): nella scelta della flotta non servono mai, con o senza tetto e vincoli geografici.
# Non vale per i treni modulari (lì si scelgono taglie, e un treno dominato può servire a completare una combinazione).
#
#   julia --project=fase14 fase14/01_tabella.jl > ~/Documents/lavoro/ml_treno_dati/fase14_log/log_01.txt 2>&1
#
# Scrive ml_treno_dati/fase14/tabella.jld2 e il riassunto in fase14_log/01_tabella.txt.

using TrainPowertrain, JLD2, Statistics, Printf, Dates
const TP = TrainPowertrain
const BASE = expanduser("~/Documents/lavoro/ml_treno_dati")
const LOG = joinpath(BASE, "fase14_log"); mkpath(LOG)
const OUT = open(joinpath(LOG, "01_tabella.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase14/01_tabella.jl  ", now(), "  TrainPowertrain ", TP.commit_codice())
const T0 = time()
const SIM = joinpath(BASE, "fase13", "griglia_rinf")
const DIR_RINF = expanduser("~/Documents/lavoro/train-powertrain/dati_rete/tratte_rete_rinf")
const GRIGLIA = [(m, n) for m in vcat(0.0, [round(x; digits = 2) for x in 0.03:0.01:0.99]) for n in [round(x; digits = 2) for x in 0.01:0.01:0.99]]
const NG = length(GRIGLIA); const IDX = Dict(GRIGLIA[j] => j for j in 1:NG)
const linee = filter(!isempty, strip.(readlines(joinpath(DIR_RINF, "linee_non_el_70.txt"))))
const NL = length(linee)
regime(m) = m == 0 ? "sola batteria" : m < 0.1 ? "ibrido FC piccola" : "ibrido"

# ── 1. lettura della griglia ─────────────────────────────────────────────────────
const INTEST = String.(split(TP.INTESTAZIONE_REGISTRO, ','))
col(x) = findfirst(==(x), INTEST)
const J_M, J_N, J_ES, J_C = col("m"), col("n"), col("tipo_esito"), col("total_cost_EUR_km")
const J_P, J_B, J_S = col("P_nom_fc_kW"), col("C_batt_kWh"), col("massa_serbatoio_kg")
pf(s) = (x = tryparse(Float64, s); x === nothing ? NaN : x)
C = fill(Inf, NL, NG); S = fill(NaN, NL, NG); P = fill(NaN, NL, NG); B = fill(NaN, NL, NG)
for (i, l) in enumerate(linee)
    righe = 0
    for r in Iterators.drop(eachline(joinpath(SIM, l, "registro.csv")), 1)
        c = split(r, ','); j = IDX[(round(pf(c[J_M]); digits = 2), round(pf(c[J_N]); digits = 2))]; righe += 1
        P[i, j] = pf(c[J_P]); B[i, j] = pf(c[J_B]); S[i, j] = pf(c[J_S])
        c[J_ES] == "fattibile" && (C[i, j] = pf(c[J_C]))
    end
    righe == NG || error("$l: $righe righe nel registro invece di $NG")
end
all(isfinite, filter(!isinf, C)) || error("costo non finito in un progetto fattibile")
const copt = vec(minimum(C; dims = 2)); const jopt = [argmin(C[i, :]) for i in 1:NL]
R = C ./ copt .- 1                                      # extra-costo relativo (Inf = non fattibile)
F = isfinite.(R)
say(@sprintf("1. griglia letta: %d linee × %d progetti in %.1f s; progetti fattibili per linea: mediana %d (da %d a %d)", NL, NG, time() - T0,
             median(vec(sum(F; dims = 2))), minimum(sum(F; dims = 2)), maximum(sum(F; dims = 2))))

# taglie: uguali su tutte le linee?
dP = maximum(j -> (v = filter(isfinite, P[:, j]); isempty(v) ? 0.0 : maximum(v) - minimum(v)), 1:NG)
dB = maximum(j -> (v = filter(isfinite, B[:, j]); isempty(v) ? 0.0 : maximum(v) - minimum(v)), 1:NG)
say(@sprintf("   taglie uguali su tutte le linee: differenza massima %.2g kW (fuel cell), %.2g kWh (batteria)", dP, dB))
med(v) = (w = filter(isfinite, v); isempty(w) ? NaN : median(w))     # NaN: progetto senza taglie nel registro (mai completato)
const P_FC = [med(P[:, j]) for j in 1:NG]; const C_BATT = [med(B[:, j]) for j in 1:NG]
const m = [g[1] for g in GRIGLIA]; const n = [g[2] for g in GRIGLIA]

# ── 2. quanto è "universale" un treno ────────────────────────────────────────────
nf = vec(sum(F; dims = 1))
say(@sprintf("\n2. su quante linee funziona ogni treno: nessuna %d, tutte le %d linee %d, mediana %d", count(==(0), nf), NL, count(==(NL), nf), median(nf)))
univ = findall(==(NL), nf)
if !isempty(univ)
    mr = [mean(R[:, j]) for j in univ]; k = univ[argmin(mr)]
    say(@sprintf("   il miglior treno unico (K = 1): m %.2f, n %.2f (%s, FC %.0f kW, batteria %.0f kWh): extra-costo medio %+.1f%%, peggiore %+.1f%% (%s)",
                 m[k], n[k], regime(m[k]), P_FC[k], C_BATT[k], 100mean(R[:, k]), 100maximum(R[:, k]), linee[argmax(R[:, k])]))
end
say("   ottimi per regime: ", join((@sprintf("%s %d", r, count(i -> regime(m[jopt[i]]) == r, 1:NL)) for r in ("sola batteria", "ibrido FC piccola", "ibrido")), ", "),
    "; ottimi distinti: ", length(unique(jopt)))

# ── 3. riduzione: treni inutili e dominati ───────────────────────────────────────
t0 = time()
cand = findall(>(0), nf)
# j è dominato se esiste k ≠ j con R[:, k] ≤ R[:, j] su tutte le linee (Inf ≤ Inf vale), stretto in almeno una; a parità perfetta si tiene il primo.
ord = sort(cand; by = j -> (-nf[j], sum(x -> isfinite(x) ? x : 0.0, R[:, j])))   # prima i treni che funzionano su più linee
tenuti = Int[]
function domina(k, j)
    stretto = false
    @inbounds for i in 1:NL
        a = R[i, k]; b = R[i, j]
        a > b && return false
        a < b && (stretto = true)
    end
    return stretto ? true : k < j        # colonne identiche: vince l'indice più basso
end
for j in ord
    any(k -> nf[k] >= nf[j] && domina(k, j), tenuti) || push!(tenuti, j)
end
# seconda passata: un treno tenuto presto può essere dominato da uno arrivato dopo
tenuti = [j for j in tenuti if !any(k -> k != j && domina(k, j), tenuti)]
sort!(tenuti)
say(@sprintf("\n3. riduzione (%.1f s): %d progetti → %d fattibili su almeno una linea → %d non dominati", time() - t0, NG, length(cand), length(tenuti)))
say("   per regime: ", join((@sprintf("%s %d", r, count(j -> regime(m[j]) == r, tenuti)) for r in ("sola batteria", "ibrido FC piccola", "ibrido")), ", "))
all(i -> jopt[i] in tenuti || any(j -> R[i, j] == 0 && j in tenuti, 1:NG), 1:NL) || error("un ottimo di linea è stato tolto")
say("   controllo: l'ottimo di ogni linea è fra i treni tenuti (o un treno con lo stesso costo)")

# ── 4. il serbatoio: dimensionato linea per linea ────────────────────────────────
# Per i treni standard bisognerà decidere se il serbatoio si adatta alla linea o è fisso (il più grande delle linee servite).
rs = Float64[]
for j in tenuti
    v = [S[i, j] for i in 1:NL if F[i, j] && m[j] > 0]
    length(v) >= 2 && push!(rs, maximum(v) / minimum(v))
end
isempty(rs) || say(@sprintf("\n4. serbatoio (treni ibridi tenuti, sulle linee dove funzionano): rapporto fra il più grande e il più piccolo, mediana %.1f, 90° percentile %.1f",
                           median(rs), quantile(rs, 0.9)))

mkpath(joinpath(BASE, "fase14"))
jldsave(joinpath(BASE, "fase14", "tabella.jld2"); linee = String.(linee), m, n, P_FC, C_BATT, C, R, S, copt, jopt, tenuti)
say(@sprintf("\nScritto %s (C, R, S: %d × %d; tenuti: %d). Tempo totale %.1f s", joinpath(BASE, "fase14", "tabella.jld2"), NL, NG, length(tenuti), time() - T0))
close(OUT)
