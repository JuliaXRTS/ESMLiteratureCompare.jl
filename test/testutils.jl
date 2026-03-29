using DataFrames
using TOML


# ── Helpers ──────────────────────────────────────────────────────────────────
 
"""Write a minimal two-column CSV to `path`."""
function write_test_csv(path::String; xs = 0.0:0.5:2.0, ys = nothing)
    ys = isnothing(ys) ? sin.(xs) : ys
    open(path, "w") do io
        println(io, "q,value")
        for (x, y) in zip(xs, ys)
            println(io, "$x,$y")
        end
    end
end
 
"""
Write an info.toml that matches the schema described in the module docs.
`curves` is a vector of NamedTuples, e.g. `[(file="a.csv", ombar=0.5)]`.
All other fields can be overridden via keyword arguments.
"""
function write_test_toml(path::String; 
    paper            = "TestPaper",
    figure           = "1",
    quantity         = "real response function",
    normalization    = "kF/pi^2",
    running_param    = "q",
    running_param_unit = "dimless",
    fixed_param      = "ombar",
    fixed_param_unit = "dimless",
    density          = 2e23,
    density_unit     = "cm^-3",
    temperature      = 0.0,
    temperature_unit = "eV",
    curves           = [(file = "curve_0.csv", ombar = 0.0),
                        (file = "curve_1.csv", ombar = 0.5)],
)
    d = Dict(
        "paper"              => paper,
        "figure"             => figure,
        "quantity"           => quantity,
        "normalization"      => normalization,
        "running_param"      => running_param,
        "running_param_unit" => running_param_unit,
        "fixed_param"        => fixed_param,
        "fixed_param_unit"   => fixed_param_unit,
        "density"            => density,
        "density_unit"       => density_unit,
        "temperature"        => temperature,
        "temperature_unit"   => temperature_unit,
        "curves"             => [Dict(string(k) => v for (k, v) in pairs(c))
                                 for c in curves],
    )
    open(path, "w") do io
        TOML.print(io, d)
    end
end
