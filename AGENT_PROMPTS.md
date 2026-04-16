# AGENT PROMPTS — OpenCode Multi-Agent Orchestration

Prompt pronti all'uso per OpenCode con modello `gml-5:cloud`. Ogni prompt è self-contained.
Ogni agente deve leggere `EXECUTION_PLAN.md` nella working directory come riferimento primario.

**Working directory di tutti gli agenti:**
`/Users/kairos/Library/CloudStorage/GoogleDrive-emanuele.dalessio@uniroma1.it/Il mio Drive/Dottorato/ml_treno`

**Dataset sorgente readonly:**
`/Users/kairos/Library/CloudStorage/GoogleDrive-emanuele.dalessio@uniroma1.it/Il mio Drive/Dottorato/ml_treno_H2/Data`

---

## Esecuzione in Wave

| Wave | Agenti | Parallelo? | Dipende da |
|------|--------|-----------|------------|
| 1 | α, β, γ | SÌ (3 in parallelo) | — |
| 2 | δ, ε | Sequenziale (δ poi ε) | Wave 1 |
| 3 | ζ | Singolo | Wave 2 |
| 4 | review-A, review-B, review-C | SÌ (3 in parallelo) | Wave 3 |

---

## Wave 1

### Prompt Agente α — Ingestion

```
You are a Julia engineer. Read `EXECUTION_PLAN.md` in the working directory, focus on Section 3
(Step A — Ingestion).

Your task: implement three files:
1. `Project.toml` — exactly as specified in Section 2 of EXECUTION_PLAN.md
2. `src/ingestion.jl` — exposing `ingest_all(data_root::AbstractString)::DataFrame`
3. `scripts/01_ingest.jl` — entry point that calls `ingest_all` and writes
   `data_generated/raw_rows.csv`
4. `test/test_ingestion.jl` — unit tests as listed in Section 11.1

Hard constraints:
- Use XLSX.jl to read `.xlsx`; handle European number format (comma decimal) by replacing `','`
  with `'.'` before parsing Floats when cells come as strings.
- Ignore files starting with `~$` (Excel temp files).
- Filter rows with column `TCO (€/km)` > 500.
- The sheet name is the value of the parameter that file varies (e.g., sheet "10" in the stops
  file → n_stops=10). For `opt_results_real_routes.xlsx`, use the sheet index (1..N) as
  `template_id`.
- Every row must get a deterministic seed: `seed = hash((source_file, sheet_name, row_idx)) % UInt32`.
- Output schema columns listed in Section 3 — respect names and types exactly.

Deliverables to commit: the 4 files + any missing parent directories.
Verify: `julia --project=. scripts/01_ingest.jl` runs and produces a non-empty CSV.
Run `julia --project=. -e 'using Pkg; Pkg.test()'` — your tests must pass.
Report back: total rows, rows filtered, and breakdown per source file.
```

---

### Prompt Agente β — Profile Synthesis + Templates

```
You are a Julia engineer. Read `EXECUTION_PLAN.md`, focus on Sections 4 (templates) and 5
(profile synthesis).

Your task: implement four files:
1. `src/templates.jl` — constant `REAL_ROUTE_TEMPLATES` with the 6 Italian routes as specified
2. `src/profile_synth.jl` — exposing:
   - `synthesize_slope(rng, L, slope_baseline)::Vector{Float64}`
   - `synthesize_vlim(rng, L, v_max_baseline; p=nothing)::Vector{Tuple{Float64,Float64,Float64}}`
   - `synthesize_stops(rng, L, n_stops)::Vector{Float64}`
   - `synthesize_row(row)::NamedTuple` that wraps all three given a row from raw_rows.csv
3. `scripts/02_synthesize.jl` — reads raw_rows.csv, generates profiles, saves
   `data_generated/profiles.jld2` (use JLD2.jl, key = row_idx::Int, value = NamedTuple with
   fields L, p, vlim_segments, stops)
4. `test/test_profile_synth.jl` — unit tests per Section 11.2

Hard constraints:
- Strict determinism: same seed → same output bit-for-bit. Use `MersenneTwister(seed)` per row.
- Slope profile: 1 sample per meter, length `Int(L*1000) + 1`, moving-average smoothed over
  100m window, clipped to [-35, +35] ‰.
- Vlim segments: piecewise constant, values in {60, 80, 100, 120, 140, 160}, lengths sum to L.
- Stops: ordered, min spacing 1 km.
- Handle edge cases: n_stops=0 → empty vector; L very small → K=3 macro-segments minimum.

Deliverables: 4 files. Do NOT run the script yet if Agent α hasn't finished ingestion — your
tests should use synthetic seeds and small L values (e.g., L=5.0 km) so they don't depend on
raw_rows.csv.

Verify: `using Pkg; Pkg.test()` passes. Report back sample profile statistics for L=50km,
slope_baseline=6.0.
```

---

### Prompt Agente γ — Model skeleton

```
You are a Julia engineer. Read `EXECUTION_PLAN.md`, focus on Section 8 (Model).

Your task: implement two files:
1. `src/model.jl` — expose `MLPSurrogate` struct + `build_model(n_input::Int=69)::MLPSurrogate`
   per spec (4 Dense layers: 128→64→32→4, identity output). Use `Flux.@functor`.
2. `test/test_model.jl` — unit tests per Section 11.5

Hard constraints:
- Exactly 4 Dense layers — no BatchNorm, Dropout, or anything else.
- Output layer (Dense 32→4) has NO activation.
- Forward pass must work on `Matrix{Float32}` input of shape `(n_input, n_samples)`.
- Test that Zygote gradient through the model is non-nothing.

Deliverables: 2 files.
Verify: `using Pkg; Pkg.test()` passes for test_model.jl.
Report back: printout of `build_model(69)` and number of trainable parameters.
```

---

## Wave 2

### Prompt Agente δ — Feature Extraction

```
You are a Julia engineer. Read `EXECUTION_PLAN.md`, focus on Section 6 (Feature extraction).

Depends on: Agent β's `profile_synth.jl` must exist.

Your task: implement three files:
1. `src/features.jl` — expose:
   - `FEATURE_NAMES::Vector{String}` (length 69, exact order per Section 6.1)
   - `extract_features(; p, vlim_segments, stops, L, P_nom_fc, C_batt)::Vector{Float64}`
2. `scripts/03_features.jl` — reads raw_rows.csv + profiles.jld2, computes features per row,
   saves `data_generated/features_matrix.csv` with header = FEATURE_NAMES + `row_idx` column.
3. `test/test_features.jl` — unit tests per Section 11.3

Hard constraints:
- Implement ALL 69 features per the exact table in Section 6.2.
- Never return NaN: if a feature is undefined (empty slice, etc.) return 0.0.
- `@assert all(isfinite, features)` at the end of extract_features.
- Feature value must be independent of profile length only through normalization (e.g., densities
  use L, integrals use dx=1e-3).
- Implement all helpers (`vlim_at`, `slope_at`, `max_run_positive`, `n_sign_changes`, `bin_means`)
  in the same file.
- The cross_* features in Group 10 are the most error-prone — double-check dimensional consistency.

Deliverables: 3 files.
Verify:
  - `using Pkg; Pkg.test()` passes.
  - `julia --project=. scripts/03_features.jl` runs after Agent α+β produced their outputs.
Report back: first row of features_matrix.csv and a sanity check that no column is all-zero
or all-same.
```

---

### Prompt Agente ε — Dataset Assembly

```
You are a Julia engineer. Read `EXECUTION_PLAN.md`, focus on Section 7 (Assembly + Split).

Depends on: Agents α, β, δ outputs.

Your task: implement three files:
1. `src/dataset.jl` — expose:
   - `assemble_dataset(raw_rows_path, features_path)::DataFrame`
   - `train_test_split(df::DataFrame; test_frac=0.2, seed=42)::Tuple{DataFrame,DataFrame}`
2. `scripts/04_assemble.jl` — entry point that calls both, writes
   `data_generated/dataset_final.csv`, `data_generated/train.csv`, `data_generated/test.csv`.
3. `test/test_dataset.jl` — unit tests per Section 11.4

Hard constraints:
- Join by `row_idx`.
- Output DataFrame has 69 feature columns + 4 output columns + 1 `source_group` column.
- All numeric columns as Float32 on write (CSV.write with Float32 input).
- Split stratified by `source_group` (every group must appear in both splits if it has ≥5 rows).
- Reproducibility: same seed → same split.

Deliverables: 3 files.
Verify: `using Pkg; Pkg.test()` passes. `julia --project=. scripts/04_assemble.jl` runs.
Report back: row counts for train/test and group distribution.
```

---

## Wave 3

### Prompt Agente ζ — Training + Evaluation

```
You are a Julia engineer. Read `EXECUTION_PLAN.md`, focus on Sections 9 (Training) and 10
(Evaluation).

Depends on: Agent ε's train.csv / test.csv + Agent γ's model.jl.

Your task: implement five files:
1. `src/train.jl` — expose `train!(model, X_tr, Y_tr, X_val, Y_val; epochs, batch_size, lr,
   patience)::MLPSurrogate` + helper `zscore_fit(X)::(μ,σ)` and `zscore_apply(X, μ, σ)`.
2. `scripts/05_train.jl` — full training pipeline:
   - Load train.csv
   - Split 80/20 for train/val (seed=42)
   - Z-score normalize features (save stats to `results/norm_stats.bson`)
   - `build_model(69)` then `train!`
   - Save best model to `results/model.bson`, log to `results/training_log.csv`
3. `src/evaluate.jl` — expose `evaluate(model, X_test, Y_test, norm_stats)::DataFrame` with
   MSE/MAE/R²/accuracy per output.
4. `scripts/06_evaluate.jl` — load model + norm_stats + test.csv, compute metrics, generate
   plots in `results/plots/` (scatter per output, residual histograms, training curve), write
   `results/metrics.csv` and `results/test_report.md`.
5. Optional: `test/test_train.jl` — smoke test with tiny synthetic data.

Hard constraints:
- AD backend: **Zygote.jl** only. No Enzyme.
- Use `Zygote.withgradient` + `Optimisers.update!` pattern (see Section 9 snippet).
- All arrays as `Float32` in training.
- Loss weights: `W = Float32[1.0, 1.0, 2.0, 2.0]` per Section 9.
- Early stopping with patience=20.
- For integer outputs (3, 4): also report accuracy after `clamp.(round.(Int, ŷ), 0, 6)`.
- Report template for `test_report.md`:
  ```
  # Test Report — MLP Surrogate

  ## Dataset
  - Train: N rows, Val: N rows, Test: N rows

  ## Hyperparameters
  - epochs: …, batch_size: 32, lr: 1e-3, patience: 20

  ## Metrics
  | Output | MSE | MAE | R² | Accuracy |
  |---|---|---|---|---|
  | H2_cons | … | … | … | — |
  ...

  ## Training curve
  ![](plots/training_curve.png)

  ## Conclusions
  - …
  - Suggested next steps: …
  ```

Deliverables: 5 files + all output artifacts under `results/`.
Verify:
  - `julia --project=. scripts/05_train.jl` completes without NaN, saves model.bson
  - `julia --project=. scripts/06_evaluate.jl` produces metrics.csv + plots + test_report.md
Report back: final metrics table and whether acceptance criteria (R² ≥ 0.7 for ≥ 2 outputs) are met.
```

---

## Wave 4 — Review (tutti in parallelo)

### Prompt Agente review-A — Stability

```
You are a Julia QA engineer. The full pipeline is implemented in `ml_treno/`. Run it 3 times
with different seeds and verify stability.

Task:
1. For each seed in {42, 123, 777}:
   a. Edit `scripts/05_train.jl` setting the train/val split seed to this value.
   b. Run the full pipeline from scratch: `01_ingest.jl` → `06_evaluate.jl`.
   c. Capture `results/metrics.csv`.
2. Build `results/stability.csv` with columns: seed, output, MSE, MAE, R², accuracy.
3. Compute per-output `std(R²)` across the 3 runs.
4. Criterion: `std(R²) < 0.1` for each output. Flag any violation.

Deliverables: `results/stability.csv` and a short Markdown summary `results/stability_report.md`.
Do NOT modify other code — only the seed constant in 05_train.jl (and revert it at the end).
Report back: the stability table and pass/fail verdict.
```

---

### Prompt Agente review-B — Code Review

```
You are a senior Julia code reviewer. Review all files under `ml_treno/src/` and `ml_treno/scripts/`.

Checklist (produce a markdown report `results/code_review.md`):

1. **Type hygiene**
   - Training hot path uses `Float32` (not Float64).
   - Feature extraction can use Float64 — flag if mixed types cause allocation.

2. **Numerical safety**
   - No `NaN` / `Inf` propagation: empty slices handled, division by zero guarded.
   - `@assert all(isfinite, ...)` present at critical boundaries.

3. **Performance**
   - No `@inbounds` missing in obvious hot loops (slope integrals, feature extraction).
   - No unnecessary `copy` in training loop.

4. **Maintainability**
   - Every exported function has a docstring (one line is fine).
   - No hardcoded absolute paths outside `scripts/*.jl`.
   - No dead code, no TODO left behind.

5. **Testing**
   - Each `src/*.jl` has a corresponding `test/test_*.jl`.
   - `Pkg.test()` passes.

For each issue found, classify: Critical (blocks acceptance) / Warning / Suggestion.
Output format:
```
## src/features.jl
- [Critical] Line 42: NaN risk if `stops` is empty on line 40
- [Warning] Line 87: Float64 in hot loop, costs allocation
- [Suggestion] Line 100: extract helper for readability
```

Do NOT modify code — only report. Report back: summary counts per severity.
```

---

### Prompt Agente review-C — Final Report

```
You are a ML research writer. Aggregate all pipeline outputs into a final report.

Inputs to read:
- `results/metrics.csv`
- `results/stability.csv` and `stability_report.md`
- `results/code_review.md`
- `results/training_log.csv`
- `results/plots/*.png`

Output: overwrite `results/test_report.md` with a comprehensive report:

1. **Executive summary** (2-3 sentences: does the surrogate work?)
2. **Pipeline overview**: 1 paragraph describing the data synthesis + 69-feature approach.
3. **Results table** (per output: MSE, MAE, R², accuracy).
4. **Stability analysis** (deviation across 3 seeds).
5. **Code quality** (summary of review-B findings).
6. **Acceptance criteria checklist** — tick each criterion from Section 13 of EXECUTION_PLAN.md.
7. **Diagnosis & next steps** — concrete proposals:
   - Feature pruning via permutation importance?
   - More real data needed?
   - Architecture changes?
   - Separate integer head?
   - Real slope/vlim data from Ansys when available.

Style: technical but accessible to a PhD supervisor in Energy Engineering (not ML).
Deliverable: `results/test_report.md`.
Report back: the executive summary paragraph.
```

---

## Nota finale per l'orchestratore

Dopo Wave 4, verificare manualmente che **tutti** i criteri della Sezione 13 di
`EXECUTION_PLAN.md` siano soddisfatti. Se uno fallisce:
- R² < 0.7 su tutti gli output → rilancia Wave 3 con hyperparameters diversi (lr più alta,
  più epoche, batch più grande).
- std(R²) > 0.1 → dataset troppo piccolo o feature troppo rumorose; considera feature pruning.
- Review-B segnala critical → rimanda ai rispettivi agenti delle Wave precedenti per fix mirato.

*Fine del documento.*
