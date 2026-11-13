# fase7/02_figura_importanza.jl: ridisegna fig_importanza.png da 01_importanza.csv (la prima versione di 01_durata.jl
# scambiava gli assi delle etichette con le barre orizzontali). Nessun calcolo.
#   julia --project=fase7 fase7/02_figura_importanza.jl
using Plots
gr()
const LOG = expanduser("~/Documents/lavoro/ml_treno_dati/fase7_log")
r = [split(l, ',') for l in readlines(joinpath(LOG, "01_importanza.csv"))[2:end]]
k15 = [(String(a), parse(Float64, b)) for (a, b) in r[1:15]]
v = reverse(last.(k15))
plt = scatter(v, 1:15; yticks = (1:15, reverse(first.(k15))), legend = false, size = (800, 500), dpi = 130, ms = 6,
              color = :steelblue, xscale = :log10, xlims = (3e-4, 1.5), xlabel = "importanza (guadagno, normalizzata, scala log)",
              title = "D: le 15 caratteristiche più usate")
for (i, x) in enumerate(v); plot!(plt, [3e-4, x], [i, i]; color = :steelblue, lw = 1.5); end
savefig(plt, joinpath(LOG, "fig_importanza.png"))
println("fig_importanza.png ridisegnata")
