# fase13/01_linee.jl: le linee della rete ricostruite dai dati sorgente aggiornati il 17/11/2026 (Drive condiviso SurrogateTrains,
# script del collega v45a: nuova livellazione di rete; Lombardia: le 6 linee del bacino di Iseo con le fermate complete fino a
# Brescia Borgo San Giovanni).
#
#   julia --project=fase13 fase13/01_linee.jl > ~/Documents/lavoro/ml_treno_dati/fase13_log/log_01.txt 2>&1
#
# Sorgente: copia locale del Drive in ~/Documents/lavoro/ml_treno_dati/linee_rinf_sorgente/<regione>/<linea>/. Per ogni linea:
# quota dai punti di altimetria.csv (inizi delle livellette, a piena precisione), fermate da fermate.csv (solo quelle, non le
# stazioni), limiti da velocita_tratti.csv. Scrive train-powertrain/dati_rete/tratte_rete_rinf/tutto_rinf/<linea>/ nel formato a
# 4 file (come fase12/11, versione "tutto RINF") e l'elenco delle linee non elettrificate oltre il 70% (km_non_elettrificati /
# lunghezza_km del riepilogo.csv del Drive) in tratte_rete_rinf/linee_non_el_70.txt.

using TrainPowertrain, Printf, Dates
const BASE = expanduser("~/Documents/lavoro/ml_treno_dati")
const LOG = joinpath(BASE, "fase13_log"); mkpath(LOG)
const OUT = open(joinpath(LOG, "01_linee.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase13/01_linee.jl  ", now(), "  TrainPowertrain ", TrainPowertrain.commit_codice())
const SRC = joinpath(BASE, "linee_rinf_sorgente")
const DIR_RINF = expanduser("~/Documents/lavoro/train-powertrain/dati_rete/tratte_rete_rinf")
const DIR_TR = joinpath(DIR_RINF, "tutto_rinf")
isdir(DIR_TR) && error("$DIR_TR esiste già: cancellarla prima di ricostruire")

function leggi_csv(f)
    l = readlines(f); h = split(l[1], ',')
    return [Dict(String(h[j]) => String(x) for (j, x) in enumerate(split(r, ','))) for r in l[2:end] if !isempty(strip(r))]
end
# il riepilogo ha campi fra virgolette con virgole
dividi(r) = (out = String[]; buf = IOBuffer(); dentro = false;
             for ch in r; ch == '"' ? (dentro = !dentro) : (ch == ',' && !dentro) ? push!(out, String(take!(buf))) : print(buf, ch); end;
             push!(out, String(take!(buf))); out)

sorgente = Dict{String,String}()
for reg in readdir(SRC), l in (isdir(joinpath(SRC, reg)) ? readdir(joinpath(SRC, reg)) : String[])
    isfile(joinpath(SRC, reg, l, "altimetria.csv")) && (sorgente[l] = joinpath(SRC, reg, l))
end
nomi = sort(collect(keys(sorgente)))
say("linee nella sorgente: ", length(nomi))

# nel riepilogo 4 linee pugliesi si chiamano "…L3+5", "…L4+3"; le cartelle "…L3_5", "…L4_3"
rie = let l = readlines(joinpath(SRC, "riepilogo.csv")), h = dividi(l[1])
    Dict(replace(d["tronco"], '+' => '_') => d for d in (Dict(h[j] => x for (j, x) in enumerate(dividi(r))) for r in l[2:end] if !isempty(strip(r))))
end
Set(keys(rie)) == Set(nomi) || error("riepilogo e cartelle non coincidono: ", symdiff(Set(keys(rie)), Set(nomi)))
quota_ne(l) = parse(Float64, rie[l]["km_non_elettrificati"]) / parse(Float64, rie[l]["lunghezza_km"])

oggi = Dates.format(now(), "yyyy-mm-dd")
function scrivi(linea, s, q, stazioni, limiti)
    d = joinpath(DIR_TR, linea); mkpath(d)
    int = "% $(linea): dal Drive condiviso SurrogateTrains (17/11/2026: quota, fermate e limiti dai dati sorgente), ml_treno/fase13/01_linee.jl, $(oggi)"
    open(io -> (println(io, int); foreach(x -> println(io, repr(x)), s)), joinpath(d, "$(linea)_progressiva.txt"), "w")
    open(io -> (println(io, int); foreach(x -> println(io, repr(x)), q)), joinpath(d, "$(linea)_altimetria.txt"), "w")
    open(io -> (println(io, int); foreach(x -> println(io, x), stazioni)), joinpath(d, "$(linea)_stazioni.txt"), "w")
    open(io -> (println(io, int); foreach(x -> println(io, x), limiti)), joinpath(d, "$(linea)_limiti.txt"), "w")
end
"""Il profilo (punti strettamente crescenti; i punti ripetuti si scartano), esteso con la pendenza dell'ultimo tratto fino ad almeno `Lmin` [m]."""
function profilo(src, Lmin)
    s = Float64[]; q = Float64[]
    for r in leggi_csv(joinpath(src, "altimetria.csv"))
        x = round(1000parse(Float64, r["s_km"]); digits = 3); h = parse(Float64, r["quota_m"])   # al millimetro
        (isempty(s) || x > s[end] + 1e-6) && (push!(s, x); push!(q, h))
    end
    if s[end] < Lmin - 1e-6
        g = (q[end] - q[end-1]) / (s[end] - s[end-1]); push!(q, q[end] + g * (Lmin - s[end])); push!(s, Lmin)
    end
    return s, q
end
"""Limiti contigui da 0 a L (interi, m)."""
function limiti_contigui(righe, L)
    out = String[]; a = 0
    for (k, r) in enumerate(righe)
        b = k == length(righe) ? max(round(Int, 1000parse(Float64, r["s_fine_km"])), L) : round(Int, 1000parse(Float64, r["s_fine_km"]))
        b > a && push!(out, @sprintf("%d %d %s", a, b, r["vmax_kmh"])); a = b
    end
    return out
end

problemi = Tuple{String,String}[]; avvisi = String[]; costruite = String[]
for linea in nomi
    try
        src = sorgente[linea]
        L_km = parse(Float64, rie[linea]["lunghezza_km"])
        fer = leggi_csv(joinpath(src, "fermate.csv"))
        st = unique([round(Int, 1000parse(Float64, r["s_km"])) for r in fer]); sort!(st)
        st[1] == 0 || (push!(avvisi, @sprintf("%s: prima fermata a %.3f km, aggiunta una fermata a 0", linea, st[1] / 1000)); pushfirst!(st, 0))
        L_fin = round(Int, max(1000parse(Float64, leggi_csv(joinpath(src, "velocita_tratti.csv"))[end]["s_fine_km"]),
                               round(1000parse(Float64, leggi_csv(joinpath(src, "altimetria.csv"))[end]["s_km"]); digits = 3)))
        if st[end] < L_fin - 50
            push!(avvisi, @sprintf("%s: fermate fino a %.3f km, capolinea aggiunto a %.3f km", linea, st[end] / 1000, L_fin / 1000))
            push!(st, L_fin)
        end
        abs(st[end] / 1000 - L_km) > 0.05 && push!(avvisi, @sprintf("%s: capolinea a %.3f km, riepilogo %.3f km", linea, st[end] / 1000, L_km))
        s, q = profilo(src, st[end])
        lim = limiti_contigui(leggi_csv(joinpath(src, "velocita_tratti.csv")), st[end])
        scrivi(linea, s, q, string.(st), lim)
        leggi_tratte_reali([linea]; cartella = DIR_TR)          # controllo: la tratta si legge come le altre
        push!(costruite, linea)
    catch e
        push!(problemi, (linea, first(sprint(showerror, e), 200)))
    end
end
non_el = filter(l -> quota_ne(l) > 0.7, costruite)
open(io -> foreach(l -> println(io, l), non_el), joinpath(DIR_RINF, "linee_non_el_70.txt"), "w")
open(joinpath(DIR_RINF, "README.md"), "w") do io
    println(io, "# Linee della rete costruite dai dati sorgente RINF\n")
    println(io, "Generate il $(oggi) da `ml_treno/fase13/01_linee.jl` dalla copia locale del Drive condiviso SurrogateTrains",
            " (`Linee Ferroviarie/01 - Italia/Linee/<regione>/<linea>`, versione del 17/11/2026: script v45a e le 6 linee del bacino di Iseo",
            " corrette fino a Brescia Borgo San Giovanni). **Non modificare a mano.**\n")
    println(io, "- `tutto_rinf`: quota dai punti di `altimetria.csv` (inizi delle livellette, a piena precisione), fermate da `fermate.csv`",
            " (solo le fermate dell'orario, non le stazioni), limiti da `velocita_tratti.csv`. Le soste per fermata non sono rappresentabili",
            " nel formato a 4 file: il simulatore usa 120 s per fermata e 300 s al capolinea.")
    println(io, "- `linee_non_el_70.txt`: le $(length(non_el)) linee con km non elettrificati oltre il 70% della lunghezza (dal `riepilogo.csv` del Drive).")
    println(io, "\nLinee costruite: $(length(costruite)) su $(length(nomi)).")
    isempty(avvisi) || (println(io, "\nAvvisi:"); foreach(x -> println(io, "- ", x), avvisi))
    isempty(problemi) || (println(io, "\nNon costruite:"); foreach(p -> println(io, "- ", p[1], ": ", p[2]), problemi))
end
say(@sprintf("linee costruite: %d su %d; non elettrificate oltre il 70%%: %d", length(costruite), length(nomi), length(non_el)))
for p in problemi; say("   non costruita: ", p[1], ": ", p[2]); end
for x in avvisi; say("   ", x); end
close(OUT)
