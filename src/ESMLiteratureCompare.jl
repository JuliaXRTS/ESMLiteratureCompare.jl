module ESMLiteratureCompare

const _DATA_DIR_NAME = "data"

using DrWatson
using Unitful


function paperdir(paper_name)
    return projectdir(_DATA_DIR_NAME,paper_name)
end

function avail_paper()
    return readdir(_DATA_DIR_NAME)
end

abstract type AbstractParameter end

struct FixedParameter{T<:Real} <: AbstractParameter
    name::String
    value::T
    unit::Units
end

# TODO:
# - find out if these need type aliasses
TempeatureParameter(value, unit = u"eV") = FixedParameter("temperature", value, unit)
ElectronDensityParameter(value, unit = u"cm^(-3)") = FixedParameter("electron_density", value, unit)

# TODO: 
# builds fixed parameter from info.toml entry
function _build_fixed_parameter(name,unit,value)
    
end

struct RunningParameter <: AbstractParameter
    name::String
    unit::Units
end

# TODO: 
# builds running parameter from info.toml entry
function _build_running_parameter(name,unit,value)
    
end



# TODO: 
# - consider: rename "Data" to config, or path, because it is misleading compared to the
# actual data loaded from it
abstract type AbstractData end

struct CurveData <: AbstractData 
    curve::String
    fixed_parameter::FixedParameter
    running_parameter::RunningParameter
    temperature::FixedParameter
    density::FixedParameter
end

# build curve data from <figure>/info.toml curve entry
function _build_curve_data() end


struct FigureData <: AbstractData 
    figure::String
    curves::Vector{CurveData}
end

# build figure data from <figure>/info.toml 
function _build_figure_data() end

struct LiteratureData <: AbstractData 
    paper::string
    figures::Vector{FigureData}
end

# build literature data from <paper_name>/info.toml entry
function _build_literature_data(paper_name) end

# TODO: 
# - loads literature data from the constructed path
function load_literature(lit::LiteratureData) end


end
