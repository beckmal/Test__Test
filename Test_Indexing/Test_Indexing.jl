import Random
#Random.seed!(1234)
const test_indexing_activated = try
    test_indexing_activated
catch
    import Pkg
    Pkg.activate(@__DIR__)
    Pkg.update()
    Pkg.resolve()
    try
        using Revise
    catch
    end

    using Bas3Plots
    import Bas3Plots.display
    import Bas3Plots.notify
    using Bas3GLMakie
    using Bas3_EnvironmentTools

    using Bas3ImageSegmentation
    using Bas3ImageSegmentation.Bas3
    #using Bas3ImageSegmentation.Bas3QuasiMonteCarlo
    #using Bas3ImageSegmentation.Bas3GaussianProcess
    #using Bas3ImageSegmentation.Bas3SciML_Core
    #using Bas3ImageSegmentation.Bas3Surrogates_Core
    using Bas3ImageSegmentation.Bas3IGABOptimization
    import Base.size
    import Base.length
    import Base.minimum
    import Base.maximum
    using Random
    using Mmap
    using Statistics
    using Bas3ImageSegmentation.JLD2

    using Bas3_EnvironmentTools
    import Bas3_EnvironmentTools.Distributed.RemoteChannel
    true
end
const input_type = @__(Bas3ImageSegmentation.c__Image_Data{Float32, (:red, :green, :blue)})
const raw_output_type = @__(Bas3ImageSegmentation.c__Image_Data{Float32, (:scar, :redness, :hematoma, :necrosis, :background)})
#output_type = raw_output_type
const output_type = @__(Bas3ImageSegmentation.c__Image_Data{Float32, (:foreground, :background)})


import Bas3.convert
@__(begin
    println(output_type)
    println(raw_output_type)
    rw = raw_output_type((rand(10, 10) for _ in 1:length(shape(raw_output_type)))...)
    println(typeof(rw))
    rw[:, :, :scar]
end)