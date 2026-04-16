# EXECUTION PLAN — Pipeline Surrogato H2-Treno (Julia + Flux)
**Issued by:** Lead Software Architect (Claude Sonnet 4.6)
**Consuming agents:** OpenCode con modello `gml-5:cloud`, orchestrazione multi-agente
**Tutte le istruzioni sono in questo documento + `AGENT_PROMPTS.md`**

---

## 0. Contesto del progetto

**Obiettivo:** costruire un modello surrogato in Julia/Flux che sostituisca un simulatore fisico MATLAB
per treni ibridi H2/batteria. Il simulatore prende in input una configurazione di tratta + powertrain
e restituisce 4 output. Un ottimizzatore globale chiama il simulatore ~200 volte per tratta e questo
richiede ~2 giorni. Il surrogato ML deve essere abbastanza veloce (<1 ms per chiamata) e accurato
(R² > 0.7 per almeno 2 output su test set).

**Questo esperimento è un first-cut su dati in gran parte sintetici.** I dati reali di slope/velocità/fermate
non sono ancora disponibili: vanno **inventati** in modo realistico e deterministico, partendo dai dati
reali disponibili in `ml_treno_H2/Data/` che contengono `(P_nom_fc, C_batt)` → 4 output.

**Input del modello** (69 feature ingegnerizzate):
- 3 scalari: lunghezza tratta `L`, potenza fuel cell `P_nom_fc`, capacità batteria `C_batt`
- 66 feature derivate da profili spaziali: pendenza `p(x)` metro-per-metro, limiti velocità
  `v_lim(x)` a segmenti, posizioni fermate `x_stops`

**Output del modello** (4):
1. `H2_cons` — consumo idrogeno (continuo)
2. `SOC_end` — stato di carica finale batteria (continuo)
3. `num_repl_FC` — n° sostituzioni fuel cell (intero ≥ 0)
4. `num_repl_batt` — n° sostituzioni batteria (intero ≥ 0)

**Architettura:** MLP Flux a 4 Dense layer (128→64→32→4), AD via **Zygote.jl**, Adam optimiser.

---

## 1. Struttura progetto (ciò che OpenCode deve produrre)

Working directory: `ml_treno/` (la directory corrente di questo piano).
Dati sorgente readonly: `../ml_treno_H2/Data/` (percorso assoluto risolvibile tramite `joinpath`).

```
ml_treno/
├── Project.toml                    # deps Julia (vedi §2)
├── src/
│   ├── ingestion.jl                # §3 — legge Excel → raw_rows.csv
│   ├── templates.jl                # §4 — catalogo 6 tratte italiane
│   ├── profile_synth.jl            # §5 — genera slope/v_lim/stops
│   ├── features.jl                 # §6 — estrae 69 feature
│   ├── dataset.jl                  # §7 — assembla + split train/test
│   ├── model.jl                    # §8 — MLP 128→64→32→4
│   ├── train.jl                    # §9 — training loop Zygote
│   └── evaluate.jl                 # §10 — metriche + plot
├── scripts/
│   ├── 01_ingest.jl
│   ├── 02_synthesize.jl
│   ├── 03_features.jl
│   ├── 04_assemble.jl
│   ├── 05_train.jl
│   └── 06_evaluate.jl
├── test/
│   ├── runtests.jl
│   ├── test_ingestion.jl
│   ├── test_profile_synth.jl
│   ├── test_features.jl
│   ├── test_dataset.jl
│   └── test_model.jl
├── data_generated/                 # output intermedi (git-ignored)
├── results/                        # output finali (git-ignored)
└── AGENT_PROMPTS.md
```

---

## 2. Environment (Project.toml)

```toml
name = "MLTrenoSurrogate"
uuid = "11111111-2222-3333-4444-555555555555"   # genera UUID v4
version = "0.1.0"

[deps]
BSON         = "fbb218c0-5317-5bc6-957e-2ee96dd4b1f0"
CSV          = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
DataFrames   = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
Distributions= "31c24e10-a181-5473-b8eb-7969acd0382f"
Flux         = "587475ba-b771-5e3f-ad9e-33799f191a9c"
JLD2         = "033835bb-8acc-5ee8-8aae-3f567f8a3819"
Optimisers   = "3bd65402-5787-11e9-1adc-39752487f4e2"
Plots        = "91a5bcdd-55d7-5caf-9e0b-520d859cae80"
Random       = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"
Statistics   = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"
StatsBase    = "2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91"
XLSX         = "fdbf4ff8-1666-58a4-91e7-1b58723a45e0"
Zygote       = "e88e6eb3-aa80-5325-afca-941959d7151f"

[compat]
julia      = "1.10"
Flux       = "0.14"
Zygote     = "0.6"
Optimisers = "0.3"
XLSX       = "0.10"
DataFrames = "1"
CSV        = "0.10"
JLD2       = "0.4"
BSON       = "0.3"
Plots      = "1"
```

Header standard per ogni script/src:
```julia
using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
```

---

## 3. Step A — Ingestion (`src/ingestion.jl` + `scripts/01_ingest.jl`)

**Sorgente:** 5 file `.xlsx` in `../ml_treno_H2/Data/` + sottocartelle:

| File | Parametro esplicito | Valori attesi (nomi sheet) |
|---|---|---|
| `tratte_ideali/fermate/opt_results_sensitivity_stops.xlsx` | `n_stops` | `0, 10, 30, 50` |
| `tratte_ideali/lunghezza/opt_results_sensitivity_length.xlsx` | `L_km` | valori in km (es. 50–250) |
| `tratte_ideali/pendenza/opt_results_sensitivity_slope.xlsx` | `slope_permille` | `0, 3, 6, 9, 12` |
| `tratte_ideali/vel/opt_results_sensitivity_vel.xlsx` | `v_max_kmh` | valori in km/h |
| `tratte_reali/opt_results_real_routes.xlsx` | `template_id` | nomi/id tratte |

**Schema colonne atteso in ogni sheet** (20 colonne, formato europeo `;` + `,`):
```
m; n; TCO (€/km); P_nom_fc; C_batt; H2_cons; SOC_end; CAPEX_FC_km; CAPEX_batt_km;
CAPEX_tank_km; OPEX_batt_rech_km_att; OPEX_H2_rech_km_att; OPEX_mant_FC_km_att;
OPEX_mant_batt_km_att; OPEX_mant_serb_km_att; cost_repl_FC_att_km; cost_repl_batt_att_km;
total_cost_km; num_repl_FC; num_repl_batt
```

**Funzione principale da esporre:**
```julia
function ingest_all(data_root::AbstractString) -> DataFrame
```

**Comportamento richiesto:**
1. Lista tutti i file `opt_results_*.xlsx` sotto `data_root`. Ignora file temporanei che iniziano con `~$`.
2. Per ogni file: `XLSX.readxlsx(path)` → per ogni sheet: legge i dati tabulari.
3. **Parsing robusto**: se le celle contengono stringhe con `,` come decimale, convertile a `Float64`
   con `replace(',' => '.')` prima del `parse`. Se una riga ha celle mancanti/NaN → skip.
4. **Filtro penalità**: scarta righe con `TCO (€/km) > 500`.
5. Per ogni riga valida, costruisci un record:
```julia
(
  P_nom_fc::Float64,
  C_batt::Float64,
  H2_cons::Float64,
  SOC_end::Float64,
  num_repl_FC::Int,
  num_repl_batt::Int,
  source_file::String,       # basename del file
  sheet_name::String,
  explicit_param::String,    # "n_stops" | "L_km" | "slope_permille" | "v_max_kmh" | "template_id"
  explicit_value::Float64,   # parsed dal nome sheet (o numero-template per i reali)
  row_idx::Int,              # indice globale 1..N
  seed::UInt32,              # hash((source_file, sheet_name, row_idx)) % UInt32
)
```
6. Concatena tutto in un `DataFrame`; salva `data_generated/raw_rows.csv`.
7. Stampa un riepilogo: totale righe, righe scartate per filtro TCO, breakdown per file.

**Acceptance:** `raw_rows.csv` esiste, ha ≥ 500 righe, colonne complete, nessun NaN.

---

## 4. Step B.1 — Templates tratte reali (`src/templates.jl`)

Modulo che esporta una costante `REAL_ROUTE_TEMPLATES::Vector{NamedTuple}` con **6 tratte**:

```julia
const REAL_ROUTE_TEMPLATES = [
    (id=1, name="Torino-Milano",           L_km=125.0, slope_style=:pianura,     v_max=160.0, n_stops=4,  slope_mean=1.0,  slope_range=(-5.0, 5.0)),
    (id=2, name="Napoli-Reggio Calabria",  L_km=495.0, slope_style=:costiero,    v_max=140.0, n_stops=8,  slope_mean=3.0,  slope_range=(-15.0, 15.0)),
    (id=3, name="Brennero-Verona",         L_km=233.0, slope_style=:discendente, v_max=120.0, n_stops=6,  slope_mean=-8.0, slope_range=(-25.0, 10.0)),
    (id=4, name="Roma-Ancona",             L_km=295.0, slope_style=:appenninica, v_max=130.0, n_stops=10, slope_mean=2.0,  slope_range=(-20.0, 20.0)),
    (id=5, name="Palermo-Messina",         L_km=230.0, slope_style=:costiero,    v_max=100.0, n_stops=12, slope_mean=1.5,  slope_range=(-10.0, 10.0)),
    (id=6, name="Brescia-Iseo-Edolo",      L_km=103.0, slope_style=:montano,     v_max=80.0,  n_stops=15, slope_mean=5.0,  slope_range=(-30.0, 30.0)),
]
```

Funzione: `template_for_row(row_idx::Int) = REAL_ROUTE_TEMPLATES[mod1(row_idx, 6)]`.

---

## 5. Step B.2 — Profile synthesis (`src/profile_synth.jl` + `scripts/02_synthesize.jl`)

Per ogni riga di `raw_rows.csv`, genera profili spaziali sintetici **deterministici** (stesso seed
su run successivi → stesso output bit-a-bit).

**Range globali:**
- `L ∈ [30, 300]` km
- `n_stops ∈ [0, 50]`
- `slope(x) ∈ [-35, +35]` ‰
- `v_lim ∈ {60, 80, 100, 120, 140, 160}` km/h
- `discretizzazione slope`: 1 campione per metro

**Regola di fissaggio parametro:**
- Se `explicit_param == "n_stops"`: `n_stops = explicit_value`, altri random.
- Se `explicit_param == "L_km"`: `L = explicit_value`, altri random.
- Se `explicit_param == "slope_permille"`: `slope_baseline = explicit_value`, altri random.
- Se `explicit_param == "v_max_kmh"`: `v_max_baseline = explicit_value`, altri random.
- Se `explicit_param == "template_id"`: usa `REAL_ROUTE_TEMPLATES[id]` per tutti i parametri,
  poi applica perturbazione random leggera (`L *= rand(0.9, 1.1)`, etc.).

**Default random (quando non fissati):**
```julia
rng = MersenneTwister(seed)
L               = rand(rng, 30:5:300) |> Float64          # km
n_stops         = rand(rng, 0:2:50)
slope_baseline  = sample(rng, [0.0, 3.0, 6.0, 9.0, 12.0], Weights([0.3, 0.25, 0.2, 0.15, 0.1]))
v_max_baseline  = sample(rng, [100.0, 120.0, 140.0], Weights([0.4, 0.4, 0.2]))
```

### 5.1 Funzione `synthesize_slope(rng, L, slope_baseline) -> Vector{Float64}`

1. `N = Int(L * 1000) + 1` punti (uno per metro).
2. Numero macro-segmenti: `K = max(3, Int(floor(L/10)))`.
3. Genera K lunghezze random con `rand(rng, Dirichlet(ones(K)))` normalizzate a `L*1000` metri.
4. Per ogni macro-segmento, campiona `μ_seg ~ Normal(slope_baseline * rand([-1,1]), slope_baseline/2 + 1)`.
5. Costruisci `p[i]` costante per ogni segmento = `μ_seg`.
6. Aggiungi rumore: `p .+= randn(rng, N) * 1.5` (‰).
7. Smoothing con media mobile 100m: `p = moving_average(p, 100)`.
8. Clip: `p .= clamp.(p, -35.0, 35.0)`.
9. Return `p`.

### 5.2 Funzione `synthesize_vlim(rng, L, v_max_baseline, p=nothing) -> Vector{Tuple{Float64,Float64,Float64}}`

Ritorna `Vector{(x_start_km, x_end_km, v_lim_kmh)}`.

1. `M ~ Poisson(L/15) + 1`.
2. Lunghezze segmenti `lens ~ Dirichlet(ones(M)) * L`.
3. Costruisci bordi `edges = cumsum([0.0; lens])`.
4. Per ogni segmento, valore in `{60, 80, 100, 120, 140, 160}` con probabilità biased verso
   `v_max_baseline` (es. gaussiana centrata su v_max_baseline, σ=20).
5. (Opzionale) Se `p` fornito e `mean(|p|)` in un segmento > 20‰, riduci v_lim di una classe.
6. Return vettore di tuple.

### 5.3 Funzione `synthesize_stops(rng, L, n_stops) -> Vector{Float64}`

1. Se `n_stops == 0`: return `Float64[]`.
2. Proponi `n_stops` posizioni uniformi in `(0, L)`.
3. Ordina, rimuovi coppie con Δ < 1 km mantenendo la prima. Se si scende sotto `n_stops` ricampiona
   fino a convergenza (max 10 tentativi).
4. Return vettore ordinato.

### 5.4 Pipeline `scripts/02_synthesize.jl`

Carica `raw_rows.csv` → per ogni riga chiama le 3 funzioni con seed dalla riga → salva in
`data_generated/profiles.jld2` con chiave `row_idx::Int`:
```julia
profiles[row_idx] = (
    L = L::Float64,
    p = p::Vector{Float64},                                  # len = Int(L*1000)+1
    vlim_segments = vlim::Vector{Tuple{Float64,Float64,Float64}},
    stops = stops::Vector{Float64},
)
```

**Acceptance:** `profiles.jld2` contiene tanti record quanti `raw_rows.csv`, nessun NaN/Inf,
rirunnare 2 volte produce file bit-identici.

---

## 6. Step C — Feature extraction (`src/features.jl` + `scripts/03_features.jl`)

Funzioni pure, niente side effect.

### 6.1 Costante ordine colonne

```julia
const FEATURE_NAMES = [
    # Gruppo 0 — Scalari (3)
    "L_km", "P_nom_fc", "C_batt",
    # Gruppo 1 — Slope lavoro gravitazionale (4)
    "slope_int_pos", "slope_int_neg", "slope_int_abs", "slope_rms",
    # Gruppo 2 — Slope statistiche (8)
    "slope_mean_pos", "slope_std_pos", "slope_mean_neg", "slope_std_neg",
    "slope_max", "slope_min", "slope_std_all", "slope_std_sq_pos",
    # Gruppo 3 — Slope struttura spaziale (3)
    "slope_L_up_frac", "slope_sign_changes_per_km", "slope_max_run_up_km",
    # Gruppo 4 — Velocità statistiche (4)
    "vlim_mean", "vlim_std", "vlim_max", "vlim_min",
    # Gruppo 5 — Velocità energia cinetica (4)
    "vlim_sum_abs_dv2", "vlim_changes_per_km", "vlim_sum_dv_pos_sq", "vlim_sum_dv_neg_sq",
    # Gruppo 6 — Velocità classi (3)
    "vlim_frac_low", "vlim_frac_mid", "vlim_frac_high",
    # Gruppo 7 — Fermate densità (3)
    "stops_density", "stops_spacing_mean", "stops_spacing_std",
    # Gruppo 8 — Fermate energia (4)
    "stops_sum_v2", "stops_mean_v", "stops_std_v", "stops_sum_v2_segweighted",
    # Gruppo 9 — Fermate pendenza locale (3)
    "stops_mean_p", "stops_sum_abs_p", "stops_frac_on_slope",
    # Gruppo 10 — Cross-feature (10)
    "cross_Lup_v", "cross_Ldn_v", "cross_brake_energy_signed", "cross_thermal_fatigue",
    "cross_stops_v_seg", "cross_abs_p_highv", "cross_up_lowv", "cross_mean_p_v",
    "cross_int_p_v", "cross_var_p_v",
    # Gruppo 11 — Binning spaziale K=10 (20)
    "bin_p_1", "bin_p_2", "bin_p_3", "bin_p_4", "bin_p_5",
    "bin_p_6", "bin_p_7", "bin_p_8", "bin_p_9", "bin_p_10",
    "bin_v_1", "bin_v_2", "bin_v_3", "bin_v_4", "bin_v_5",
    "bin_v_6", "bin_v_7", "bin_v_8", "bin_v_9", "bin_v_10",
]
@assert length(FEATURE_NAMES) == 69
```

### 6.2 Funzione principale

```julia
function extract_features(; p::Vector{Float64},
                            vlim_segments::Vector{Tuple{Float64,Float64,Float64}},
                            stops::Vector{Float64},
                            L::Float64,
                            P_nom_fc::Float64,
                            C_batt::Float64) -> Vector{Float64}
```

Restituisce un vettore `Float64` di lunghezza 69, in ordine `FEATURE_NAMES`.
`dx = 1e-3` (km) dato che `p` è metro-per-metro.

**Helper da implementare** (tutti in `features.jl`):
- `vlim_at(x_km, segments)` → velocità al km `x`
- `slope_at(x_km, p)` → `p[Int(round(x_km*1000))+1]`
- `max_run_positive(v)` → lunghezza massima run consecutivo `v .> 0` (in metri → km)
- `n_sign_changes(v)` → conteggio di `sign(v[i]) != sign(v[i-1])` con v≠0
- `bin_means(v, K)` → media in K bin equispaziati

**Formule esatte** (ogni feature è un'espressione scalare):

| # | Nome | Formula |
|---|---|---|
| 1 | L_km | `L` |
| 2 | P_nom_fc | `P_nom_fc` |
| 3 | C_batt | `C_batt` |
| 4 | slope_int_pos | `sum(max.(p, 0)) * dx` |
| 5 | slope_int_neg | `sum(max.(-p, 0)) * dx` |
| 6 | slope_int_abs | `sum(abs.(p)) * dx` |
| 7 | slope_rms | `sqrt(mean(p.^2))` |
| 8 | slope_mean_pos | `mean(p[p .> 0])` (o 0 se vuoto) |
| 9 | slope_std_pos | `std(p[p .> 0])` (o 0 se <2 elem) |
| 10 | slope_mean_neg | `mean(p[p .< 0])` (o 0) |
| 11 | slope_std_neg | `std(p[p .< 0])` (o 0) |
| 12 | slope_max | `maximum(p)` |
| 13 | slope_min | `minimum(p)` |
| 14 | slope_std_all | `std(p)` |
| 15 | slope_std_sq_pos | `std(p[p.>0].^2)` (o 0) |
| 16 | slope_L_up_frac | `count(>(0), p) / length(p)` |
| 17 | slope_sign_changes_per_km | `n_sign_changes(p) / L` |
| 18 | slope_max_run_up_km | `max_run_positive(p) / 1000` |
| 19 | vlim_mean | `sum(len_i * v_i) / L` |
| 20 | vlim_std | dev. std pesata per len_i |
| 21 | vlim_max | `maximum(v_i)` |
| 22 | vlim_min | `minimum(v_i)` |
| 23 | vlim_sum_abs_dv2 | `sum(abs.(diff(v_i.^2)))` |
| 24 | vlim_changes_per_km | `(M-1) / L` dove M = n° segmenti |
| 25 | vlim_sum_dv_pos_sq | `sum(max.(diff(v_i), 0).^2)` |
| 26 | vlim_sum_dv_neg_sq | `sum(max.(-diff(v_i), 0).^2)` |
| 27 | vlim_frac_low | `sum(len_i for v_i < 80) / L` |
| 28 | vlim_frac_mid | `sum(len_i for 80 ≤ v_i < 100) / L` |
| 29 | vlim_frac_high | `sum(len_i for v_i ≥ 100) / L` |
| 30 | stops_density | `length(stops) / L` |
| 31 | stops_spacing_mean | `mean(diff([0; stops; L]))` (o `L` se vuoto) |
| 32 | stops_spacing_std | `std(diff([0; stops; L]))` (o 0) |
| 33 | stops_sum_v2 | `sum(vlim_at(x, segments)^2 for x in stops)` |
| 34 | stops_mean_v | `mean([vlim_at(x) for x in stops])` (o 0) |
| 35 | stops_std_v | `std([vlim_at(x) for x in stops])` (o 0) |
| 36 | stops_sum_v2_segweighted | `sum(v_i^2 * count(x -> x in seg_i, stops) for seg_i)` |
| 37 | stops_mean_p | `mean([slope_at(x, p) for x in stops])` (o 0) |
| 38 | stops_sum_abs_p | `sum(abs(slope_at(x, p)) for x in stops)` |
| 39 | stops_frac_on_slope | `count(x -> abs(slope_at(x,p)) > 5, stops) / max(length(stops),1)` |
| 40 | cross_Lup_v | `sum(L_i * mean_pos(p_in_seg_i) * v_i for seg)` |
| 41 | cross_Ldn_v | come sopra con `mean_neg` |
| 42 | cross_brake_energy_signed | `sum(vlim_at(x)^2 * sign(slope_at(x,p)) for x in stops)` |
| 43 | cross_thermal_fatigue | `sum(L_i * var_p_in_seg_i * v_i for seg)` |
| 44 | cross_stops_v_seg | `sum(L_i * v_i * n_stops_in_seg_i for seg)` |
| 45 | cross_abs_p_highv | `sum(L_i * mean(abs_p_in_seg_i) for seg if v_i > 100)` |
| 46 | cross_up_lowv | `sum(L_i * mean_pos(p_in_seg_i) for seg if v_i < 80)` |
| 47 | cross_mean_p_v | media lungo x di `p(x) * vlim(x)` |
| 48 | cross_int_p_v | integrale di `p(x) * vlim(x) dx` |
| 49 | cross_var_p_v | varianza di `p(x) * vlim(x)` |
| 50–59 | bin_p_1…10 | `mean(p)` nel k-esimo decile di lunghezza |
| 60–69 | bin_v_1…10 | `mean(vlim)` pesata per lunghezza nel k-esimo decile |

**NB sui valori mancanti:** mai ritornare `NaN`. Se una feature è indefinita (es. media su vettore
vuoto) → sostituisci con `0.0`. Validazione finale: `@assert all(isfinite, features)`.

### 6.3 Pipeline `scripts/03_features.jl`

Carica `raw_rows.csv` + `profiles.jld2` → per ogni riga applica `extract_features` → accumula
matrice `N × 69` → scrivi `data_generated/features_matrix.csv` (header = `FEATURE_NAMES`).

---

## 7. Step D+E — Assembly + Split (`src/dataset.jl` + `scripts/04_assemble.jl`)

### 7.1 Assembly

Join per `row_idx`:
- 69 colonne feature (da features_matrix.csv)
- 4 colonne output: `H2_cons`, `SOC_end`, `num_repl_FC`, `num_repl_batt`
- 1 colonna stratificazione: `source_group` = `basename(source_file)` (senza estensione)

Output: `data_generated/dataset_final.csv`. Tipo: tutti `Float32` per le feature/output,
`String` per `source_group`.

### 7.2 Split stratificato

```julia
function train_test_split(df::DataFrame; test_frac=0.2, seed=42) -> (train::DataFrame, test::DataFrame)
```

Per ogni gruppo `source_group`, preleva il 20% delle righe come test. Usa `Random.seed!(seed)` una
volta all'inizio. Scrivi `train.csv`, `test.csv`.

**Acceptance:** ogni `source_group` presente in entrambi i set; nessuna duplicazione.

---

## 8. Step F.1 — Model (`src/model.jl`)

Copia esatta dell'architettura del dummy EXECUTION_PLAN precedente, con `n_input = 69`:

```julia
using Flux

mutable struct MLPSurrogate
    chain::Flux.Chain
end
Flux.@functor MLPSurrogate (chain,)
(m::MLPSurrogate)(x) = m.chain(x)

function build_model(n_input::Int = 69)
    chain = Flux.Chain(
        Flux.Dense(n_input => 128, relu),
        Flux.Dense(128     => 64,  relu),
        Flux.Dense(64      => 32,  relu),
        Flux.Dense(32      => 4),                # linear output
    )
    MLPSurrogate(chain)
end
```

Assert post-costruzione: `@assert length(model.chain.layers) == 4`.

---

## 9. Step F.2 — Training (`src/train.jl` + `scripts/05_train.jl`)

**Normalizzazione:** z-score per colonna **calcolato solo sul train set**, salvato in `results/norm_stats.bson`
per riuso in evaluate.

**Loss** (pesata):
```julia
const W = Float32[1.0, 1.0, 2.0, 2.0]

function loss_fn(ŷ::AbstractMatrix{Float32}, y::AbstractMatrix{Float32})
    sum(W .* mean((ŷ .- y).^2, dims=2)) / 4
end
```

**Training loop** con Zygote:
```julia
function train!(model, X_tr::Matrix{Float32}, Y_tr::Matrix{Float32},
                X_val::Matrix{Float32}, Y_val::Matrix{Float32};
                epochs=200, batch_size=32, lr=1e-3, patience=20)
    opt_state = Optimisers.setup(Optimisers.Adam(lr), model)
    best_val = Inf32; no_improve = 0; log = Vector{NamedTuple}()

    for epoch in 1:epochs
        idx = shuffle(1:size(X_tr, 2))
        epoch_loss = 0f0; nb = 0
        for i in 1:batch_size:length(idx)-batch_size+1
            bi = idx[i:i+batch_size-1]
            xb = X_tr[:, bi]; yb = Y_tr[:, bi]
            lval, grads = Zygote.withgradient(model) do m
                loss_fn(m(xb), yb)
            end
            Optimisers.update!(opt_state, model, grads[1])
            epoch_loss += lval; nb += 1
        end
        train_l = epoch_loss / nb
        val_l   = loss_fn(model(X_val), Y_val)
        push!(log, (epoch=epoch, train_loss=train_l, val_loss=val_l))

        if val_l < best_val - 1f-5
            best_val = val_l; no_improve = 0
            BSON.@save "results/model.bson" model
        else
            no_improve += 1
            no_improve ≥ patience && (println("Early stop @ epoch $epoch"); break)
        end
        epoch % 10 == 0 && println("Epoch $epoch  train=$(round(train_l;digits=5))  val=$(round(val_l;digits=5))")
    end
    CSV.write("results/training_log.csv", DataFrame(log))
    return model
end
```

**Script `05_train.jl`:** carica `train.csv`, splitta 80/20 internamente per val, normalizza,
chiama `train!`, salva `model.bson` e `norm_stats.bson`.

**Acceptance:** training converge (val_loss < 0.5 alla fine); `model.bson` esiste; nessun NaN.

---

## 10. Step G — Evaluation (`src/evaluate.jl` + `scripts/06_evaluate.jl`)

Carica `model.bson`, `norm_stats.bson`, `test.csv`. Normalizza test input con le stats del train.

**Metriche per output** `k ∈ {1,2,3,4}`:
- `MSE_k = mean((ŷ_k - y_k)^2)`
- `MAE_k = mean(abs(ŷ_k - y_k))`
- `R²_k  = 1 - SS_res/SS_tot`
- Per k=3,4 (interi): `ŷ_int = clamp.(round.(Int, ŷ_k), 0, 6)`, `accuracy = mean(ŷ_int .== Int.(y_k))`

Output: `results/metrics.csv` (righe = {H2_cons, SOC_end, num_repl_FC, num_repl_batt}; colonne = MSE, MAE, R², [accuracy]).

**Plot** in `results/plots/`:
- `scatter_<output>.png` — predicted vs actual per ciascun output
- `residuals_<output>.png` — istogramma residui
- `training_curve.png` — train/val loss da `training_log.csv`

**Report finale** `results/test_report.md`:
- Tabella metriche
- Hyperparameters utilizzati
- Dimensione train/test
- Top 5 e bottom 5 predizioni per errore
- Conclusione: "accettabile/da migliorare" + proposte concrete

---

## 11. Testing (`test/runtests.jl` + file specifici)

Ogni `src/` file ha un `test_*.jl` associato. Esempi minimi:

### 11.1 `test_ingestion.jl`
- Conversione stringa europea `"0,5"` → `0.5`
- Filtro TCO: dati fittizi, verifica scarto
- Nessun NaN nel DataFrame risultante

### 11.2 `test_profile_synth.jl`
- `synthesize_slope` con seed fisso produce output bit-identici su chiamate successive
- Output in range `[-35, 35]`
- Lunghezza `== Int(L*1000)+1`
- `synthesize_stops` con `n_stops=0` → vettore vuoto
- Spaziatura minima > 1 km

### 11.3 `test_features.jl`
- `extract_features` con profilo piatto `p ≡ 0` → `slope_int_pos == 0`, `slope_max == 0`, etc.
- Lunghezza output `== 69`
- `all(isfinite, out) == true`
- Con profilo `p ≡ 10` → `slope_mean_pos ≈ 10`, `slope_int_neg ≈ 0`

### 11.4 `test_dataset.jl`
- Split stratificato preserva `source_group` in entrambi i set
- `nrow(train) + nrow(test) == nrow(df)`

### 11.5 `test_model.jl`
- `build_model(69)` restituisce chain con 4 layer
- Forward pass su `rand(Float32, 69, 10)` restituisce matrice `4×10`
- Gradient via Zygote è non-nullo

### 11.6 `runtests.jl`
```julia
using Test
@testset "MLTrenoSurrogate" begin
    include("test_ingestion.jl")
    include("test_profile_synth.jl")
    include("test_features.jl")
    include("test_dataset.jl")
    include("test_model.jl")
end
```

Comando: `julia --project=. -e 'using Pkg; Pkg.test()'` → **tutti i test devono passare**.

---

## 12. Wave 4 — Review (eseguita dopo pipeline completata)

### Review-A — Stabilità
Esegui la pipeline 3 volte con seed globali `{42, 123, 777}` modificando la seed del
`train_test_split` e del training. Compila `results/stability.csv` con R² per output per run.
Criterio: `std(R²) < 0.1` per ciascun output.

### Review-B — Code review
Checklist automatica (uno script `scripts/review_code.jl`):
- Grep `Float64` in feature extraction hot path → flag (dovrebbe essere `Float32` in train)
- Cerca `for` loop senza `@inbounds` dove sensato
- Verifica docstring su tutte le funzioni esportate
- Verifica nessun `NaN` propagation (search `NaN` nel codice)
- Verifica nessun hardcoded absolute path fuori da `scripts/`

### Review-C — Report finale
Genera `results/test_report.md` che **chiuda il ciclo**:
1. Riassunto metriche (da `metrics.csv`)
2. Stabilità (da `stability.csv`)
3. Code review findings
4. **Conclusioni critiche**: 69 feature sono appropriate? Dataset sintetico ha influenza? Quali
   feature hanno importance più alta (analisi permutation importance su un seed)?
5. Proposte next step:
   - Feature pruning via importance
   - Aumentare dataset con più simulazioni
   - Provare Enzyme.jl quando stable
   - Output head separato per interi (classification)

---

## 13. Criteri di accettazione globali

Il lavoro è **accettato** se:
- [ ] `Pkg.test()` passa (tutti i testset green)
- [ ] `scripts/01_ingest.jl` → `06_evaluate.jl` girano in sequenza senza errori
- [ ] `results/metrics.csv` esiste, ha 4 righe, R² ≥ 0.7 per ≥ 2 output
- [ ] `results/plots/*.png` generati (≥ 8 plot)
- [ ] `results/test_report.md` compilato, completo, con conclusioni azionabili
- [ ] `results/stability.csv` mostra `std(R²) < 0.1` su 3 run
- [ ] `scripts/review_code.jl` non flagga issue critici

---

## 14. Comandi di esecuzione (quick reference)

```bash
# 1. Setup env
cd ml_treno && julia --project=. -e 'using Pkg; Pkg.instantiate()'

# 2. Run tests (prima di tutto)
julia --project=. -e 'using Pkg; Pkg.test()'

# 3. Pipeline completa
julia --project=. scripts/01_ingest.jl
julia --project=. scripts/02_synthesize.jl
julia --project=. scripts/03_features.jl
julia --project=. scripts/04_assemble.jl
julia --project=. scripts/05_train.jl
julia --project=. scripts/06_evaluate.jl

# 4. Review
julia --project=. scripts/review_code.jl
# Eseguire 3 run stabilità cambiando seed in 05_train.jl
```

---

*Fine del piano. Per i prompt specifici per ogni agente OpenCode, vedi `AGENT_PROMPTS.md`.*
