module Bas3ImageSegmentation
    #-dependency-function-1
    using Bas3
    import Base.size
    import Base.length
    import Base.minimum
    import Base.maximum
    using Bas3Lux
    const skip = Bas3Lux.Skip
    const infer = Bas3Lux.Infer
    using Bas3GradientOptimization
    using Bas3Random
    using Bas3IGABOptimization

    using Colors, ColorSchemes, ColorTypes
    using MLUtils
    using Statistics
    using StaticArrays
    using Augmentor
    export augment, Either, FlipX, FlipY, NoOp, ShearX, ShearY, Rotate, Zoom, CropSize, RCropSize, Scale, ElasticDistortion, ColorJitter, GaussianBlur
    using Images, ImageMagick
    export colorview
    using RecursiveArrayTools
    using Distributed
    using JLD2
    #-field_macro-hierarchy_type-1
    #-value_type-trait_type-1
    Base.include(Bas3ImageSegmentation, "./Image_Data/-value-1.jl")
    const v_RGB = RGB{Float32}; export v_RGB
    #-union_type-1
    #-method-macro-1
    Base.include(Bas3ImageSegmentation, "./Image_Data/-method-1.jl")
    Base.include(Bas3ImageSegmentation, "./error/-method-1.jl")
    Base.include(Bas3ImageSegmentation, "./neuralnetwork/-method-1.jl")
    Base.include(Bas3ImageSegmentation, "./load_input_and_output/-method-1.jl")
    # v2.0.0: Unified image loading API
    export load_images
    # Deprecated (will be removed in v3.0.0)
    export load_input_and_output
    Base.include(Bas3ImageSegmentation, "./augment/-method-1.jl")
    #-global-1
    const input_shape = ((:red, :green, :blue),)
    const output_shape = (:background, :scar, :redness, :hematoma, :necrosis)
    const shape_color = Dict(
        :background => v_RGB(0, 0, 0),
        :foreground => v_RGB(1, 1, 1),
        :scar => v_RGB(0, 1, 0),       # GREEN
        :redness => v_RGB(1, 0, 0),    # RED
        :hematoma => v_RGB(0.854902, 0.647059, 0.12549), # goldenrod approximation
        :necrosis => v_RGB(0, 0, 1)    # BLUE
    )
    
    struct v_Binary end
    const Binary = v_Binary()
    struct v_Continuous end
    const Continuous = v_Continuous()
    #=
    const shape_types = Dict{Symbol, Union{v_Binary, v_Continuous}}(
        :red => v_Continuous(),
        :green => v_Continuous(),
        :blue => v_Continuous(),
        :background => v_Binary(),
        :scar => v_Binary(),
        :redness => v_Binary(),
        :hematoma => v_Binary(),
        :necrosis => v_Binary()
    )
    =#
    function shape_type(symbol::v_Symbol)
        return shape_type(v__Value(symbol))
    end
    shape_type(::v__Value{:red}) = v_Continuous()
    shape_type(::v__Value{:green}) = v_Continuous()
    shape_type(::v__Value{:blue}) = v_Continuous()
    shape_type(::v__Value{:background}) = v_Binary()
    shape_type(::v__Value{:scar}) = v_Binary()
    shape_type(::v__Value{:redness}) = v_Binary()
    shape_type(::v__Value{:hematoma}) = v_Binary()
    shape_type(::v__Value{:necrosis}) = v_Binary()
    shape_type(::v__Value{:foreground}) = v_Binary()


    Base.include(Bas3ImageSegmentation, "./Reporter/-value_type-1.jl")
    Base.include(Bas3ImageSegmentation, "./Reporter/-constructor_type-1.jl")
    Base.include(Bas3ImageSegmentation, "./Reporter/-method-1.jl")
    Base.include(Bas3ImageSegmentation, "./Reporter/-constructor_method-1.jl")
    import XLSX
    #=
    function create_excel_sheet(x_string, y_string, excel_string)
        #x_matrix = load(joinpath(@__DIR__, string("../Surrogate/x_matrix_", Surrogate_String, ".jld2")))["x_matrix"]
        x_matrix = load(x_string)["x_matrix"]
        x_matrix_size = size(x_matrix)
        #y_vector = load(joinpath(@__DIR__, string("../Surrogate/y_vector_", Surrogate_String, ".jld2")))["y_vector"]
        y_vector = load(y_string)["y_vector"]
        y_vector_size = size(y_vector)

        index_array = sortperm(y_vector)
        #reverse!(index_array)
        index_array_size = size(index_array)[1]

        
        workbook = XLSX.openxlsx(function (workbook)
            sheet = workbook["Surrogate"]
            #=
            sheet[1, 1] = "Learning_Rate"
            sheet[1, 2] = "Batch_Array_Size"
            sheet[1, 3] = "Iterations"
            sheet[1, 4] = "Factor"
            sheet[1, 5] = "Weight_1"
            sheet[1, 6] = "Weight_2"
            sheet[1, 7] = "Weight_3"
            sheet[1, 8] = "Scale"
            sheet[1, 9] = "Factor"
            sheet[1, 10] = "Kernel"
            sheet[1, 11] = "Error"
            =#
            for index = 1:index_array_size[1]
                sheet[index + 1, 1] = x_matrix[:, index_array[index]]
                sheet[index + 1, x_matrix_size[1] + 1] = y_vector[index_array[index]]
            end
            #save excel sheet
        end, excel_string, mode="rw")
        #=
        for index = 1:index_array_size[1]
            Base.print(index, " ", x_matrix[:, index_array[index]], " ", y_vector[index_array[index]], "\n")
        end
        =#
    end
    =#
    import XLSX
    @__(function write_xlsx(path, optimizer; input=Bas3IGABOptimization.inputs(surrogate(optimizer)), output=Bas3IGABOptimization.outputs(surrogate(optimizer)))
        println(path)
        println(input)
        println(output)
        _surrogate = surrogate(optimizer)
        _sampler = sampler(optimizer)
        _names = Bas3IGABOptimization.Bas3QuasiMonteCarlo.names(_sampler)
        println(Bas3IGABOptimization.Bas3QuasiMonteCarlo.names(_sampler))
        println(typeof(input))
        println(typeof(output))
        _length = length(output)
        names_length = length(_names)
        sorted_index_vector = sortperm(output)
        XLSX.openxlsx(function _openxlsx(workbook)
            sheet = workbook["Optimierung_1"]
            # Write header
            for i in 1:names_length
                sheet[1, i] = String(_names[i])
            end
            sheet[1, _length + 1] = "Output"
            # Write data
            for i in 1:length(input)
                sheet[i + 1, 1:names_length] = [input[i]...]
            end
            for i in 1:length(output)
                sheet[i + 1, names_length + 1] = output[sorted_index_vector[i]]
            end
        end, path; mode="rw")
    end)
    @__(function write_xlsx(path, optimizer; input=Bas3IGABOptimization.inputs(surrogate(optimizer)), output=Bas3IGABOptimization.outputs(surrogate(optimizer)), denormalize)
        _sampler = sampler(optimizer)
        _names = Bas3IGABOptimization.Bas3QuasiMonteCarlo.names(_sampler)
        _length = length(output)
        names_length = length(_names)
        sorted_index_vector = sortperm(output)
        XLSX.openxlsx(function _openxlsx(workbook)
            sheet = workbook["Optimierung_1"]
            # Write header
            for i in 1:names_length
                sheet[1, i] = String(_names[i])
            end
            sheet[1, _length + 1] = "Output"
            # Write data
            for i in 1:length(input)
                kws = (;
                    (
                        begin
                            _names[j] => input[i][j]
                        end
                        for j in 1:names_length
                    )...
                )
                kws = values(denormalize(;kws...))
                println(kws)
                sheet[i + 1, 1:names_length] = [kws...]
            end
            for i in 1:length(output)
                sheet[i + 1, names_length + 1] = output[sorted_index_vector[i]]
            end
        end, path; mode="rw")
        
    end)
    export write_xlsx

    function Bas3.convert(
        image_type::v__Type{<:c__Image_Data{v__Tuple{type, size_type, Tuple{:scar, :redness, :hematoma, :necrosis, :background}, channels_type}} where {size_type, channels_type}},
        image
        ) where {type}
        #println("CALL: convert(image_type::v__Type{<:c__Image_Data{v__Tuple{type, size_type, (:scar, :redness, :hematoma, :necrosis, :background), channels_type}} where {size_type, channels_type}}, image)")
        #=
        d = data(image)
        #foreground = output_data[:, :, 2] .+ output_data[:, :, 3] .+ output_data[:, :, 4] .+ output_data[:, :, 5]
        foreground = d[:, :, 3]
        background = d[:, :, 5]
        return image_type(
            foreground,
            background
        )
        =#
        return image
    end
    function Bas3.convert(
        image_type::v__Type{<:c__Image_Data{v__Tuple{type, size_type, Tuple{:foreground, :background}, channels_type}} where {size_type, channels_type}},
        image
        ) where {type}
        #println("CALL: convert(image_type::v__Type{<:c__Image_Data{v__Tuple{type, size_type, (:foreground, :background), channels_type}} where {size_type, channels_type}}, image)")
        
        d = data(image)
        foreground = d[:, :, 2] .+ d[:, :, 3] .+ d[:, :, 4] .+ d[:, :, 1]
        background = d[:, :, 5]
        return image_type(
            foreground,
            background
        )
        
        return image
    end
    #=
    struct t__convert__Image_Data_Scar_Redness_Hematoma_Necrosis_Background <: t__ end
    struct t__convert__Image_Data_Foreground_Background <: t__ end
    function Bas3.convert(
        ::t__convert__Image_Data_Foreground_Background, image_type,
        ::t__convert__Image_Data_Scar_Redness_Hematoma_Necrosis_Background, image
        )
        println("CALL: convert")
        scar_image = image[:scar]
        redness_image = image[:redness]
        hematoma_image = image[:hematoma]
        necrosis_image = image[:necrosis]
        background_image = image[:background]
        foreground_image = scar_image .+ redness_image .+ hematoma_image .+ necrosis_image
        return image_type(
            foreground_image,
            background_image
        )
    end
    function subsets(arr...)
        n = length(arr)
        result = Array{Any, 1}(undef, 2^n - 1)
        # We use k binary number to represent which elements to include
        for i in 1:(2^n - 1)
            subset = []
            for j in 1:n
                if (i >> (j - 1)) & 1 == 1
                    push!(subset, arr[j])
                end
            end
            result[i] = v__Tuple{subset...}
        end
        return result
    end
    function Bas3.t__convert(
        ::v__Type{
            <:c__Image_Data{
                <:v__Tuple{
                    type,
                    size_type,
                    <: u__{subsets(:foreground, :background)...},
                    channels_type
                }
            } where {size_type, channels_type}
        }) where {type}
        println("CALL: t__convert")
        return t__convert__Image_Data_Foreground_Background()
    end
    =#


end
