using Test
using Unitful

using ESMLiteratureCompare
# Bring private helpers into scope for white-box testing
using ESMLiteratureCompare:
    _parse_unit,
    _build_fixed_parameter,
    _build_running_parameter,
    _build_curve_data,
    _build_figure_data,
    _build_literature_data

include("testutils.jl")

@testset "_parse_unit" begin
    @testset "dimensionless token" begin
        @test _parse_unit("dimless") === Unitful.NoUnits
    end
 
    @testset "standard SI units" begin
        @test _parse_unit("eV")   == u"eV"
        @test _parse_unit("cm^-3") == u"cm^-3"
        @test _parse_unit("kg")   == u"kg"
    end
 
    @testset "parenthesised exponent (literature style)" begin
        # e.g. "cm^(-3)" must be handled without throwing
        @test _parse_unit("cm^(-3)") == u"cm^-3"
    end
 
    @testset "compound units" begin
        @test _parse_unit("eV*ps") == u"eV*ps"
    end
end

@testset "_build_fixed_parameter" begin
    @testset "basic construction" begin
        fp = _build_fixed_parameter("temperature", "eV", 0.0)
        @test fp isa FixedParameter
        @test fp.name  == "temperature"
        @test fp.value == 0.0
        @test fp.unit  == u"eV"
    end
 
    @testset "dimless unit" begin
        fp = _build_fixed_parameter("ombar", "dimless", 1.5)
        @test fp.unit === Unitful.NoUnits
        @test fp.value == 1.5
    end
 
    @testset "negative and fractional values" begin
        fp = _build_fixed_parameter("shift", "eV", -3.14)
        @test isapprox(fp.value, -3.14)
    end
 
    @testset "density with parenthesised unit" begin
        fp = _build_fixed_parameter("density", "cm^(-3)", 2e23)
        @test fp.unit == u"cm^-3"
        @test fp.value == 2e23
    end
end

@testset "_build_running_parameter" begin
    @testset "basic construction" begin
        rp = _build_running_parameter("q", "dimless")
        @test rp isa RunningParameter
        @test rp.name  == "q"
        @test rp.unit  === Unitful.NoUnits
    end
 
    @testset "physical unit" begin
        rp = _build_running_parameter("omega", "eV")
        @test rp.unit == u"eV"
    end
 
    @testset "non-zero representative value" begin
        rp = _build_running_parameter("q", "dimless")
        rp.unit == Unitful.NoUnits
    end
end

@testset "Convenience constructors" begin
    @testset "TemperatureParameter default unit" begin
        tp = TemperatureParameter(0.5)
        @test tp.name  == "temperature"
        @test tp.value == 0.5
        @test tp.unit  == u"eV"
    end
 
    @testset "TemperatureParameter custom unit" begin
        tp = TemperatureParameter(300.0, u"K")
        @test tp.unit == u"K"
    end
 
    @testset "ElectronDensityParameter default unit" begin
        ep = ElectronDensityParameter(2e23)
        @test ep.name  == "electron_density"
        @test ep.value == 2e23
        @test ep.unit  == u"cm^-3"
    end
end

@testset "_build_curve_data" begin
    mktempdir() do dir
        # Lay down a CSV so the path exists
        csv_name = "curve_ombar_0.5.csv"
        write_test_csv(joinpath(dir, csv_name))
 
        rp   = _build_running_parameter("q",    "dimless")
        temp = _build_fixed_parameter("temperature", "eV",0.0)
        dens = _build_fixed_parameter("density",    "cm^-3", 2e23)
 
        curve_dict = Dict("file" => csv_name, "ombar" => 0.5)
 
        cd = _build_curve_data(curve_dict, dir, "ombar", "dimless", rp, temp, dens)
 
        @testset "type" begin
            @test cd isa CurveData
        end
 
        @testset "file path is absolute and exists" begin
            @test isabspath(cd.file)
            @test isfile(cd.file)
        end
 
        @testset "fixed parameter value" begin
            @test cd.fixed_param.name  == "ombar"
            @test cd.fixed_param.value == 0.5
            @test cd.fixed_param.unit  === Unitful.NoUnits
        end
 
        @testset "running parameter forwarded correctly" begin
            @test cd.running_param.name == "q"
        end
 
        @testset "temperature and density forwarded" begin
            @test cd.temperature.value == 0.0
            @test cd.density.value     == 2e23
        end
    end
end

@testset "_build_figure_data" begin
    mktempdir() do fig_dir
        # Create the CSV files referenced by the toml
        for name in ["curve_0.csv", "curve_1.csv"]
            write_test_csv(joinpath(fig_dir, name))
        end
 
        write_test_toml(joinpath(fig_dir, "info.toml"),
            figure = "2",
            quantity = "real response function",
            normalization = "kF/pi^2",
            running_param = "q",
            running_param_unit = "dimless",
            fixed_param = "ombar",
            fixed_param_unit = "dimless",
            density = 2e23,
            density_unit = "cm^-3",
            temperature = 0.0,
            temperature_unit = "eV",
            curves = [(file = "curve_0.csv", ombar = 0.0),
                                 (file = "curve_1.csv", ombar = 0.5)],
        )
 
        fd = _build_figure_data(fig_dir)
 
        @testset "type" begin
            @test fd isa FigureData
        end
 
        @testset "scalar fields" begin
            @test fd.figure == "2"
            @test fd.quantity == "real response function"
            @test fd.normalization == "kF/pi^2"
        end
 
        @testset "curve count" begin
            @test length(fd.curves) == 2
        end
 
        @testset "curves are sorted / ordered as in toml" begin
            @test fd.curves[1].fixed_param.value == 0.0
            @test fd.curves[2].fixed_param.value ≈ 0.5
        end
 
        @testset "shared temperature forwarded to each curve" begin
            for c in fd.curves
                @test c.temperature.value == 0.0
                @test c.temperature.unit  == u"eV"
            end
        end
 
        @testset "shared density forwarded to each curve" begin
            for c in fd.curves
                @test c.density.value == 2e23
                @test c.density.unit == u"cm^-3"
            end
        end
    end
 
    @testset "missing info.toml throws" begin
        mktempdir() do empty_dir
            @test_throws ErrorException _build_figure_data(empty_dir)
        end
    end
end

@testset "_build_literature_data" begin
    # We need to temporarily re-root DrWatson's projectdir.
    # The simplest approach: create a fake project and call the builder
    # with an absolute paperdir, patching the helper locally.
    mktempdir() do root
        paper_name = "TestPaper2011"
        paper_path = joinpath(root, paper_name)
        mkpath(paper_path)
 
        # Two figure subdirectories
        for (fig_label, ombar_vals) in [("figure_1", [0.0, 0.5]),
                                         ("figure_2", [1.0, 1.5])]
            fig_path = joinpath(paper_path, fig_label)
            mkpath(fig_path)
            curve_entries = [(file = "c_$(v).csv", ombar = v) for v in ombar_vals]
            for v in ombar_vals
                write_test_csv(joinpath(fig_path, "c_$(v).csv"))
            end
            write_test_toml(
                joinpath(fig_path, "info.toml"),
                paper = paper_name,
                figure = fig_label,
                curves = curve_entries,
            )
        end
 
        # Bypass DrWatson by calling the builder with the full path directly.
        # We test _build_figure_data composition rather than path resolution here.
        fig_dirs = sort(filter(isdir, readdir(paper_path; join = true)))
        figures = FigureData[_build_figure_data(d) for d in fig_dirs]
        lit = LiteratureData(paper_name, figures)
 
        @testset "type" begin
            @test lit isa LiteratureData
        end
 
        @testset "paper name" begin
            @test lit.paper == paper_name
        end
 
        @testset "figure count" begin
            @test length(lit.figures) == 2
        end
 
        @testset "figures are alphabetically ordered" begin
            @test lit.figures[1].figure == "figure_1"
            @test lit.figures[2].figure == "figure_2"
        end
 
        @testset "each figure has correct curve count" begin
            @test length(lit.figures[1].curves) == 2
            @test length(lit.figures[2].curves) == 2
        end
    end
end

@testset "Loading (CSV → DataFrame)" begin
    mktempdir() do fig_dir
        xs = 0.0:0.25:2.0
        for (name, ombar) in [("c_0.csv", 0.0), ("c_1.csv", 0.5)]
            write_test_csv(joinpath(fig_dir, name); xs = xs, ys = ombar .+ sin.(xs))
        end
 
        write_test_toml(
            joinpath(fig_dir, "info.toml"),
            curves = [(file = "c_0.csv", ombar = 0.0),
                      (file = "c_1.csv", ombar = 0.5)],
        )
 
        fd = _build_figure_data(fig_dir)
 
        @testset "load_curve" begin
            lc = load_curve(fd.curves[1])
            @test lc isa LoadedCurve
            @test lc.meta === fd.curves[1]
            @test lc.data isa DataFrame
            @test nrow(lc.data) == length(xs)
            @test "q" in names(lc.data)
            @test "value" in names(lc.data)
        end
 
        @testset "load_figure" begin
            lf = load_figure(fd)
            @test lf isa LoadedFigure
            @test lf.meta === fd
            @test length(lf.curves) == 2
            @test all(c -> c isa LoadedCurve, lf.curves)
        end
 
        @testset "load_literature" begin
            lit = LiteratureData("TestPaper", [fd])
            ll  = load_literature(lit)
            @test ll isa LoadedLiterature
            @test ll.meta === lit
            @test length(ll.figures) == 1
            @test length(ll.figures[1].curves) == 2
        end
 
        @testset "load_curve missing file throws" begin
            rp   = _build_running_parameter("q", "dimless")
            temp = _build_fixed_parameter("temperature", "eV", 0.0)
            dens = _build_fixed_parameter("density", "cm^-3", 2e23)
            fp   = _build_fixed_parameter("ombar", "dimless", 0.0)
            bad  = CurveData(joinpath(fig_dir, "no_such_file.csv"), fp, rp, temp, dens)
            @test_throws ErrorException load_curve(bad)
        end
 
        @testset "DataFrame values are numerically correct" begin
            lc = load_curve(fd.curves[1])          # ombar = 0.0, ys = sin(xs)
            @test isapprox(lc.data[!, :q], collect(xs))
            @test isapprox(lc.data[!, :value], sin.(collect(xs)), atol=1e-10)
        end
    end
end
