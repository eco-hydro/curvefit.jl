using Libdl

using nlminb_jll
# const libnlminb = "/mnt/e/Research/julia/nlminb/src/nlminb.so"
# const libnlminb = "/mnt/e/Research/julia/nlminb.f/build/libnlminb.so"
# const libnlminb = "/mnt/e/Research/julia/nlminb.f/libnlminb.so"

# port_cpos <-
#     c(## iv[]:
#       ## MXFCAL       MXITER         OUTLEV  (port.c)
#       eval.max = 17L, iter.max = 18L, trace = 19L,
#                       maxiter  = 18L,
#       ##  v[]:
#       ## AFCTOL      RFCTOL         XCTOL        XFTOL
#       abs.tol = 31L, rel.tol = 32L, x.tol = 33L, xf.tol = 34L,
#       ## LMAX0        LMAXS           SCTOL
#       step.min = 35L, step.max = 36L, sing.tol = 37L,
#       ## DINIT          ETA0 (for nlminb *only*)
#       scale.init = 38L, diff.g = 42L)

"""
Param 
- dot Other parameters to objective, e.g. t, y, w, FUN
## FUN::Function, y::T, t::T, 
-  eval_max, iter_max: The default value in fortran is 200 and 150. But they 
are set to 1000 at here.

## Return
- `par`
- `objective`
- `convergence`
- `iterations`
- `evaluations`

## Example
```julia
t = Array(1.0:8:366)
y = doubleLog_Beck(par, t)
ypred = doubleLog_Beck(par0, t)
par0 = [0.05, 0.6, 45, 0.1, 200, 0.2]
@time opt_par = nlminb(par0, goal!, doubleLog_Beck!, y, t, ypred, verbose = false,
    eval_max = 1000, iter_max = 1000)
```
"""
function nlminb(start::AbstractArray{T,1}, 
    objective::Function, dot...;
    # gr::Union{Function,Nothing} = nothing, 
    # hs::Union{Function,Nothing} = nothing, 
    lower = nothing, 
    upper = nothing, 
    verbose = false,
    eval_max = 1000, iter_max = 1000) where T<:Real
    
    par  = start
    npar = length(par);
    iv   = zeros(Int32, 78 + 3 * npar);
    v    = zeros(Float64, 130 + Int((npar * (npar + 27)) / 2));
    
    # Init iv and v, .Call("port_ivset", 2, iv, v)    
    ccall((:Rf_divset, libnlminb), Cvoid, 
        (Int32, Ptr{Int32}, Int32, Int32, Ptr{Float64}), 
        2, iv, length(iv), length(v), v);
    # int alg, int iv[], int liv, int lv, double v[]

    iv[17] = eval_max
    iv[18] = iter_max

    if lower !== nothing && upper !== nothing
        b = zeros(npar * 2);             # boundaries, double
        @inbounds for i = 1:npar
            b[(i - 1) * 2 + 1] = lower[i]
            b[i * 2]           = upper[i]
        end
    else
        b = C_NULL
    end
    
    # other params
    d  = ones(npar); # scale 
    g  = h = C_NULL  # set grad and hess to NULL
    fx = Inf64      # Inf64, goal value

    for i = 1:eval_max
        # global fx, b, d, fx, g, h, iv, v, npar, par
        ccall((:nlminb_iterate, libnlminb), Cvoid, 
            (Ptr{Float64}, Ptr{Float64}, Float64, Ptr{Float64}, Ptr{Float64}, 
            # (Ptr{Cvoid}, Ptr{Float64}, Float64, Ptr{Float64}, Ptr{Float64}, 
            Ptr{Cvoid}, Cint, Cint, Cint, Ptr{Float64}, Ptr{Float64}),
            b, d, fx, g, h, 
            iv, length(iv), length(v), npar, v, par)
        # par0 will be modified of each iteration
        fx = objective(par, dot...)
        # fx = objective(par)
        nlminb_inspect_loop(i, par, fx; verbose = verbose)
        if (iv[1] >= 3); break; end
    end
    
    Dict(
        "par"         => par,
        "objective"   => fx,
        "convergence" => 3 <= iv[1] <= 6 ? 0 : 1,
        "iterations"  => iv[31],
        "evaluations" => Dict("function" => iv[6], "gradient" => iv[30])
    )
end


export nlminb

function nlminb_inspect_loop(i, par, fx; verbose = true)
    if verbose
        println("iteration: i = $i")
        @show par;
        @show fx
        # n = length(dot...)
        # println(n, dot...)
        # @show dot...
        # @show iv;
        # @show v;
    end
end
