# fase4/05_ultimo_bit.jl: diagnostica delle 4374 righe in cui costo_da_grandezze non ridà total_cost_EUR_km al bit.
#   julia -t 8 --project=fase4 fase4/05_ultimo_bit.jl
# Ipotesi: la campagna (PC Windows) ha calcolato x^y a esponente intero (Base.Math.pow_body(x, n), che finisce
# con muladd) senza FMA, questo Mac (Apple M4) con FMA. Qui, SOLO in questo processo, pow_body(::Float64, ::Integer)
# si ridefinisce con i muladd scritti a*b + c (non fusi) e si ricalcola il costo di tutte le completed.
# Non tocca train-powertrain né i dati. Scrive risultati/05_ultimo_bit.txt.

include(joinpath(@__DIR__, "comune.jl"))

prima = 1.04^15.0
@eval Base.Math @noinline function pow_body(x::Float64, n::Integer)
    y = 1.0
    xnlo = -0.0
    ynlo = 0.0
    n == 3 && return x*x*x
    if n < 0
        rx = inv(x)
        n==-2 && return rx*rx
        isfinite(x) && (xnlo = -fma(x, rx, -1.) * rx)
        x = rx
        n = -n
    end
    while n > 1
        if n&1 > 0
            err = y * xnlo + x * ynlo          # era muladd(y, xnlo, x*ynlo)
            y, ynlo = two_mul(x,y)
            ynlo += err
        end
        err = x*2*xnlo
        x, xnlo = two_mul(x, x)
        xnlo += err
        n >>>= 1
    end
    err = y * xnlo + x * ynlo                  # era muladd(y, xnlo, x*ynlo)
    return ifelse(isfinite(x) & isfinite(err), x * y + err, x*y)   # era muladd(x, y, err)
end
dopo = 1.04^15.0

function main()
    D = carica_tutto(vcat(COL_COSTO, ["stato", "costo", "total_cost_EUR_km"]))
    N = length(D["stato"])
    idx = findall(==(Int8(1)), D["stato"])
    tot = zeros(Int, Threads.nthreads() * 2); cst = zeros(Int, Threads.nthreads() * 2)
    cols = [D[c] for c in COL_COSTO]
    Threads.@threads :static for i in idx
        g = Dict{String,Float64}(c => v[i] for (c, v) in zip(COL_COSTO, cols))
        r = TP.costo_da_grandezze(g; cfg = CFG)
        t = Threads.threadid()
        r.costo_totale === D["total_cost_EUR_km"][i] || (tot[t] += 1)
        r.costo === D["costo"][i] || (cst[t] += 1)
    end
    log_su(joinpath(RIS, "05_ultimo_bit.txt")) do io
        println(io, "# Ultimo bit del costo ricostruito (", now(), ", Julia ", VERSION, ", ", Sys.CPU_NAME, ")")
        println(io, "1,04^15 con pow_body di Julia (FMA su questa macchina): ", repr(prima), "; con pow_body a muladd non fusi: ", repr(dopo))
        println(io, "completed: ", fmt(length(idx)))
        println(io, "con pow_body a muladd non fusi: costo_totale !== total_cost_EUR_km in ", sum(tot), " righe; costo !== costo in ", sum(cst), " righe")
        println(io, "(con pow_body di Julia su questa macchina: 4374 e 1241, passi 1 e 2)")
    end
end
main()
