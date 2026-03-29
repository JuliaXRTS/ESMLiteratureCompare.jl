module ESMLiteratureCompare

const _DATA_DIR_NAME = "data"

using DrWatson
using Unitful
using DataFrames
using TOML
using CSV

export FixedParameter, RunningParameter
export TemperatureParameter, ElectronDensityParameter
export CurveData, LoadedCurve
export FigureData, LoadedFigure
export LiteratureData, LoadedLiterature
export load_curve, load_figure, load_literature

### path helper

function paperdir(paper_name)
    return projectdir(_DATA_DIR_NAME, paper_name)
end

function figdir(paper_name, fig_name)
    return projectdir(_DATA_DIR_NAME, paper_name, fig_name)
end

function avail_papers()
    return readdir(projectdir(_DATA_DIR_NAME))
end

function avail_figures(paper_name)
    return readdir(paperdir(paper_name))
end

### unit parsing

"""
    _parse_unit(unit_str) -> Unitful.Units

Parse a unit string from info.toml into a Unitful unit.
Handles the special token `"dimless"` (→ `Unitful.NoUnits`) and
strips parentheses that some authors write, e.g. `"cm^(-3)"`.
"""
function _parse_unit(unit_str::String)
    unit_str == "dimless" && return Unitful.NoUnits

    # remove unnecessary brackets
    cleaned = replace(unit_str, r"[()]" => "")   
    return uparse(cleaned)
end

### Parameters

abstract type AbstractParameter end

"""
    FixedParameter{T<:Real, U<:Unitful.Units}

A named scalar parameter with physical units (e.g. temperature = 1 eV).
"""
struct FixedParameter{T<:Real, U<:Unitful.Units} <: AbstractParameter
    name::String
    value::T
    unit::U
end

"""
    _build_fixed_parameter(name, unit_str, value) -> FixedParameter

Construct a `FixedParameter` from raw info.toml fields.
"""
function _build_fixed_parameter(name::String, unit_str::String, value::Real)
    return FixedParameter(name, value, _parse_unit(unit_str))
end

"""
    RunningParameter{U<:Unitful.Units, T<:Real}

The x-axis quantity that is swept across a curve (e.g. momentum transfer q).
"""
struct RunningParameter{U<:Unitful.Units} <: AbstractParameter
    name::String
    unit::U
end

"""
    _build_running_parameter(name, unit_str) -> RunningParameter

Construct a `RunningParameter` from raw info.toml fields.
"""
function _build_running_parameter(name::String, unit_str::String)
    return RunningParameter(name, _parse_unit(unit_str))
end

# TODO:
# - find out if these need type aliasses
TemperatureParameter(value, unit = u"eV") = FixedParameter("temperature", value, unit)
ElectronDensityParameter(value, unit = u"cm^(-3)") = FixedParameter("electron_density", value, unit)


### Metadata

# TODO: 
# - consider: rename "Data" to config, or path, because it is misleading compared to the
# actual data loaded from it
abstract type AbstractData end

"""
    CurveData

Metadata for a single curve inside a figure.

Fields:
- `file`          – absolute path to the CSV file
- `fixed_param`   – the curve-specific label (e.g. omega = 0.5)
- `running_param` – the x-axis quantity (e.g. q)
- `temperature`   – global temperature shared by all curves in the figure
- `density`       – global electron density shared by all curves in the figure
"""
struct CurveData <: AbstractData
    file::String
    fixed_param::FixedParameter
    running_param::RunningParameter
    temperature::FixedParameter
    density::FixedParameter
end


"""
    _build_curve_data(curve_dict, fig_dir, fixed_param_name, fixed_param_unit,
                      running_param, temperature, density) -> CurveData

Build a `CurveData` from one entry in the `curves` array of an info.toml.

The curve-specific fixed-param value is stored under its own name in the dict
(e.g. `{ file = "…", ombar = 0.5 }`), so we look it up by `fixed_param_name`.
"""
function _build_curve_data(
    curve_dict      :: Dict,
    fig_dir         :: String,
    fixed_param_name:: String,
    fixed_param_unit:: String,
    running_param   :: RunningParameter,
    temperature     :: FixedParameter,
    density         :: FixedParameter,
)
    file       = joinpath(fig_dir, curve_dict["file"])
    fp_value   = Float64(curve_dict[fixed_param_name])
    fixed_param = _build_fixed_parameter(fixed_param_name, fixed_param_unit, fp_value)

    return CurveData(file, fixed_param, running_param, temperature, density)
end


"""
    FigureData

Metadata for one figure: which physical quantity is plotted, how it is
normalised, and the list of `CurveData` descriptors.
"""
struct FigureData <: AbstractData
    figure::String
    quantity::String
    normalization::String
    curves::Vector{CurveData}
end

"""
    _build_figure_data(fig_dir) -> FigureData

Parse the `info.toml` found in `fig_dir` and build a `FigureData`.

The directory is expected to follow the layout:
    data/<paper>/figure_<N>/info.toml
    data/<paper>/figure_<N>/<curve>.csv  …
"""
function _build_figure_data(fig_dir::String)
    d = TOML.parsefile(joinpath(fig_dir, "info.toml"))

    figure        = string(d["figure"])
    quantity      = d["quantity"]
    normalization = d["normalization"]

    temperature = _build_fixed_parameter("temperature", d["temperature_unit"], d["temperature"])
    density     = _build_fixed_parameter("density",     d["density_unit"],     d["density"])

    # `running_param_value` is optional; default to 0.0 when not provided
    running_param = _build_running_parameter(
        d["running_param"],
        d["running_param_unit"],
    )

    fixed_param_name = d["fixed_param"]
    fixed_param_unit = d["fixed_param_unit"]

    curves = CurveData[
        _build_curve_data(
            curve_dict, fig_dir,
            fixed_param_name, fixed_param_unit,
            running_param, temperature, density,
        )
        for curve_dict in d["curves"]
    ]

    return FigureData(figure, quantity, normalization, curves)
end

"""
    LiteratureData

Top-level metadata for one paper, collecting all its stored figures.
"""
struct LiteratureData <: AbstractData
    paper::String
    figures::Vector{FigureData}
end

"""
    _build_literature_data(paper_name) -> LiteratureData

Discover every subdirectory under `data/<paper_name>/`, treat each as a
figure directory, and assemble a `LiteratureData`.
"""
function _build_literature_data(paper_name::String)
    pdir     = paperdir(paper_name)
    fig_dirs = filter(isdir, readdir(pdir; join=true))
    isempty(fig_dirs) && @warn "No figure directories found under $pdir"

    figures = FigureData[_build_figure_data(d) for d in sort(fig_dirs)]
    return LiteratureData(paper_name, figures)
end


### Loaded data
"""
    LoadedCurve

Pairs a `CurveData` descriptor with the actual two-column DataFrame read from
the CSV file. Column names are preserved as-is from the CSV header.
"""
struct LoadedCurve
    meta::CurveData
    data::DataFrame
end

"""
    load_curve(cd::CurveData) -> LoadedCurve

Read the CSV file referenced by `cd` into a DataFrame.
"""
function load_curve(cd::CurveData)
    isfile(cd.file) || error("CSV not found: $(cd.file)")
    return LoadedCurve(cd, CSV.read(cd.file, DataFrame))
end

"""
    LoadedFigure

Pairs a `FigureData` descriptor with all its `LoadedCurve`s.
"""
struct LoadedFigure
    meta::FigureData
    curves::Vector{LoadedCurve}
end

"""
    load_figure(fd::FigureData) -> LoadedFigure

Load all curves belonging to a figure.
"""
function load_figure(fd::FigureData)
    return LoadedFigure(fd, LoadedCurve[load_curve(c) for c in fd.curves])
end

"""
    LoadedLiterature

Pairs a `LiteratureData` descriptor with all its `LoadedFigure`s.
This is the top-level object used for plotting and comparison.
"""
struct LoadedLiterature
    meta::LiteratureData
    figures::Vector{LoadedFigure}
end

"""
    load_literature(lit::LiteratureData) -> LoadedLiterature

Load every figure and its CSV data for a paper. This is the main entry point
for downstream plotting and ESM comparison code.

# Example
```julia
lit    = _build_literature_data("Mihaila2011")
loaded = load_literature(lit)
# loaded.figures[1].curves[1].data  →  DataFrame with digitised points
```
"""
function load_literature(lit::LiteratureData)
    return LoadedLiterature(lit, LoadedFigure[load_figure(f) for f in lit.figures])
end


end
