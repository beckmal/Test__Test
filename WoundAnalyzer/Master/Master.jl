import Random
#Random.seed!(1234)
const reporters = try
    for (key, value) in reporters
        stop(value)
    end
    Bas3GLMakie.GLMakie.closeall()
    reporters
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
    using Bas3ImageSegmentation.JLD2
    import Base.size
    import Base.length
    import Base.minimum
    import Base.maximum
    import Bas3.convert
    using Random
    using Mmap
    using Statistics

    using Bas3_EnvironmentTools
    import Bas3_EnvironmentTools.Distributed.RemoteChannel
    Dict()
end

#=
struct t__convert__Image_Data_Scar_Redness_Hematoma_Necrosis_Background <: t__ end
struct t__convert__Image_Data_Foreground_Background <: t__ end
function Bas3.convert(
    ::t__convert__Image_Data_Foreground_Background, image_type,
    ::t__convert__Image_Data_Scar_Redness_Hematoma_Necrosis_Background, image
    )
    @info "CALL: convert"
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
    @info "CALL: t__convert"
    return t__convert__Image_Data_Foreground_Background()
end
=#
const workers = try
    workers
catch
    local environment_variables = (
        "JULIA_NUM_THREADS" => "24",
        "JULIA_CUDA_HARD_MEMORY_LIMIT" => "80%",
        "JULIA_CUDA_SOFT_MEMORY_LIMIT" => "80%"
    )
    local workers = @start_processes(
        #=
        "Worker" => (;
            address="osw-x@192.168.0.248",
            shell=:wincmd,
            exe_path="C:/Users/osw-x/AppData/Local/Programs/Julia-1.11.2/bin/julia.exe",
            environment_path="C:/Users/osw-x/.julia",
            environment_variables=(
                "JULIA_NUM_THREADS" => "24",
                #"JULIA_CUDA_HARD_MEMORY_LIMIT" => "none",
                "JULIA_CUDA_SOFT_MEMORY_LIMIT" => "33%"
            )
        ),
        (;
            #machine=1,
            #threads=12,
            #available=false,
            virtual=true,
        ),
        =#
        #=
        "Worker" => (;
            #machine=1,
            environment_path="C:/Users/OsW-x/Julia_Worker/.julia", #TODO: make this optional somehow homedir() ?
            environment_variables=(
                "JULIA_NUM_THREADS" => "24",
                #"JULIA_CUDA_HARD_MEMORY_LIMIT" => "none",
                "JULIA_CUDA_SOFT_MEMORY_LIMIT" => "33%"
            )
            #dir="=@."
        ),
        =#
        
        
        #=
        "Worker" => (;
            address="Julia_Worker@143.93.52.28",
            shell=:wincmd,
            exe_path="C:/Users/Julia_Worker/AppData/Local/Programs/Julia-1.11.5/bin/julia.exe",
            environment_path="C:/Users/Julia_Worker/.julia",
            environment_variables=(
                "JULIA_NUM_THREADS" => "24",
                #"JULIA_CUDA_HARD_MEMORY_LIMIT" => "none",
                "JULIA_CUDA_SOFT_MEMORY_LIMIT" => "40%"
            )
        ),
        
        "Worker" => (;
            address="Julia_Worker@143.93.62.171",
            shell=:wincmd,
            exe_path="C:/Users/Julia_Worker/AppData/Local/Programs/Julia-1.11.5/bin/julia.exe",
            environment_path="C:/Users/Julia_Worker/.julia",
            environment_variables=(
                "JULIA_NUM_THREADS" => "24",
                #"JULIA_CUDA_HARD_MEMORY_LIMIT" => "none",
                "JULIA_CUDA_SOFT_MEMORY_LIMIT" => "40%"
            )
            #dir="@.",
        ),
        =#
        
        # Local worker only (for running on this Linux machine)
        "Worker" => (;
            environment_variables=(
                "JULIA_NUM_THREADS" => "24",
                "JULIA_CUDA_SOFT_MEMORY_LIMIT" => "80%"
            )
        ),
        
        ; update=true #TODO: also resolve the environments
    )

    @everywhere(workers, begin
        using Bas3ImageSegmentation
        using Bas3ImageSegmentation.Bas3
        #using Bas3ImageSegmentation.Bas3QuasiMonteCarlo
        #using Bas3ImageSegmentation.Bas3GaussianProcess
        #using Bas3ImageSegmentation.Bas3SciML_Core
        #using Bas3ImageSegmentation.Bas3Surrogates_Core
        using Bas3ImageSegmentation.Bas3IGABOptimization
        using Bas3ImageSegmentation.Bas3Lux
        using Bas3ImageSegmentation.Bas3Lux.Bas3Random
        import Bas3ImageSegmentation.Bas3Lux.OptChain
        import Bas3ImageSegmentation.Bas3Lux.GrdAccumulation
        import Bas3ImageSegmentation.Bas3Lux.Descent
        using Bas3Observables
        import Base.size
        import Base.length
        import Base.minimum
        import Base.maximum
        import Bas3.convert

        using Bas3_EnvironmentTools
        import Bas3_EnvironmentTools.Distributed.RemoteChannel
    end) 

    workers
end

@everywhere begin
    const input_type = @__(Bas3ImageSegmentation.c__Image_Data{Float32, (:red, :green, :blue)})
    const raw_output_type = @__(Bas3ImageSegmentation.c__Image_Data{Float32, (:scar, :redness, :hematoma, :necrosis, :background)})
    const output_type = @__(Bas3ImageSegmentation.c__Image_Data{Float32, (:foreground, :background)})
    #output_type = raw_output_type
end

const data_loaded = try
    data_loaded
catch
    let
        @everywhere begin
            const temp_sets = []
        end

        _length = 10000
        

        for index in 1:_length
            input, output = JLD2.load(joinpath("/mnt/c/Users/OsW-x/Desktop/Datasets", "augmented/$(index).jld2"), "set")
            output = convert(output_type, output)
            @everywhere begin
                push!(temp_sets, (memory_map($(input)), memory_map($(output))))
            end
        end
        _index_array = shuffle(1:_length)
        @everywhere begin
            const training_sets = [temp_sets...]
            const validation_sets = [temp_sets[$(_index_array)]...]
            @info "training_sets" typeof(training_sets) size(training_sets)
            @info "validation_sets" typeof(validation_sets) size(validation_sets)
        end
    end
    true
end

@everywhere begin

    const _size = (100, 50)
    @__(function neuralnetwork_definition(;
        #input,
        #output,
        #kernel,
        dilation,
        feature_scale,
        keywords...
    )
        input=(_size..., 3) #TODO: make this dynamic
        output=(_size..., 2) #TODO: make this dynamic
        infer = Bas3Lux.Infer
        skip = Bas3Lux.Skip
        kernel = 3
        kernel = round(Int64, kernel)
        Dilation = round(Int64, dilation)
        #pad = round(Int64, (kernel + 1) / 2)
        #pad = round(Int64, (kernel + Dilation) / 2)
        pad = 0
        #pad = 1
        kernel = (kernel, kernel, skip)
        feature_scale = round(Int64, feature_scale)
        first_feature_scale = @__(function _first_feature_scale(depth)
            return feature_scale * depth
        end)
        second_feature_scale = @__(function _second_feature_scale(depth)
            return first_feature_scale(depth) + feature_scale
        end)
        
        chain = Chain(
            Upsample(:bilinear; scale=(infer, infer, skip)),
            Convolution(kernel, relu; pad=pad, Dilation=Dilation, output=(infer, infer, first_feature_scale(1))),
            Convolution(kernel, relu; pad=pad, Dilation=Dilation, output=(infer, infer, first_feature_scale(1))),
            Convolution(kernel, relu; pad=pad, Dilation=Dilation, output=(infer, infer, first_feature_scale(1))),
            Cat(
                Chain(
                    MaxPool((2, 2, skip)),
                    Convolution(kernel, relu; pad=pad, Dilation=Dilation, output=(infer, infer, first_feature_scale(2))),
                    Convolution(kernel, relu; pad=pad, Dilation=Dilation, output=(infer, infer, first_feature_scale(2))),
                    Convolution(kernel, relu; pad=pad, Dilation=Dilation, output=(infer, infer, first_feature_scale(2))),
                    Cat(
                        Chain(
                            MaxPool((2, 2, skip)),
                            Convolution(kernel, relu; pad=pad, output=(infer, infer, first_feature_scale(3))),
                            Convolution(kernel, relu; pad=pad, output=(infer, infer, first_feature_scale(3))),
                            #Convolution(kernel, relu; pad=pad, output=(infer, infer, first_feature_scale(3))),
                            #=
                            Cat(
                                Chain(
                                    MaxPool((2, 2, skip)),
                                    Convolution(kernel, relu; pad=pad, output=(infer, infer, first_feature_scale(4))),
                                    Convolution(kernel, relu; pad=pad, output=(infer, infer, second_feature_scale(4))),
                                    Convolution(kernel, relu; pad=pad, output=(infer, infer, first_feature_scale(4))),
                                    Upsample(:bilinear; scale=(infer, infer, skip)),
                                ),
                                Nop();
                                dimension=3
                            ),
                            =#
                            #Convolution(kernel, relu; pad=pad, output=(infer, infer, second_feature_scale(3))),
                            Convolution(kernel, relu; pad=pad, output=(infer, infer, first_feature_scale(3))),
                            Upsample(:bilinear; scale=(infer, infer, skip)),
                        ),
                        Nop();
                        dimension=3
                    ),
                    #Convolution(kernel, relu; pad=pad, output=(infer, infer, first_feature_scale(2))),
                    Convolution(kernel, relu; pad=pad, output=(infer, infer, first_feature_scale(2))),
                    Convolution(kernel, relu; pad=pad, output=(infer, infer, first_feature_scale(2))),
                    Upsample(:bilinear; scale=(infer, infer, skip)),
                ),
                Nop();
                dimension=3
            ),
            #Convolution(kernel, relu; pad=pad, output=(infer, infer, first_feature_scale(1))),
            Convolution(kernel, relu; pad=pad, output=(infer, infer, first_feature_scale(1))),
            Convolution(kernel, relu; pad=pad, output=(infer, infer, first_feature_scale(1))),
            Convolution(kernel, relu; pad=pad);
            input=input,
            output=output,
        )
        
        #=
        chain = Chain(
            Upsample(:bilinear; scale=(infer, infer, skip)),
            Convolution(kernel, relu; pad=pad, output=(infer, infer, 6)),
            Cat(
                Chain(
                    MaxPool((2, 2, skip)),
                    Convolution(kernel, relu; pad=pad, output=(infer, infer, 6)),
                    Cat(
                        Chain(
                            MaxPool((2, 2, skip)),
                            Convolution(kernel, relu; pad=pad, output=(infer, infer, 6)),
                            Cat(
                                Chain(
                                    MaxPool((2, 2, skip)),
                                    Convolution(kernel, relu; pad=pad, output=(infer, infer, 6)),
                                    Convolution(kernel, relu; pad=pad, output=(infer, infer, 6)),
                                    Upsample(:bilinear; scale=(infer, infer, skip)),
                                ),
                                Nop();
                                dimension=3
                            ),
                            Convolution(kernel, relu; pad=pad, output=(infer, infer, 6)),
                            Upsample(:bilinear; scale=(infer, infer, skip)),
                        ),
                        Nop();
                        dimension=3
                    ),
                    Convolution(kernel, relu; pad=pad, output=(infer, infer, 6)),
                    Upsample(:bilinear; scale=(infer, infer, skip)),
                ),
                Nop();
                dimension=3
            ),
            Convolution(kernel, relu; pad=pad);
            input=input,
            output=output,
        )
            =#
        @info "chain" show_layer(chain)
        return structural_simplify(chain)
    end)
    @__(function neuralnetwork_setup(;
        model,
        learning_rate,
        batch_observations_length,
        keywords...
    )
        batch_observations_length = round(Int64, batch_observations_length)

        parameters, state = setup(Bas3Random.Default_Random, model)
        optimizer = setup(
            OptChain(
                GrdAccumulation(batch_observations_length),
                Descent(learning_rate)
            ),
            parameters
        )
        return parameters, state, optimizer
    end)
    @__(function neuralnetwork_validation(;
            model,
            parameters,
            state,
            _gpu_device,
            _cpu_device,
            validation_sets,
            keywords...
        )
        @info "CALL: neuralnetwork_validation"
        GC.gc()
        Bas3Lux.CUDA.reclaim()
        model = neuralnetwork_definition(;
            #input=(128, 64, 3), #TODO: make this dynamic
            #output=(128, 64, 2), #TODO: make this dynamic
            #kernel=keywords[:kernel],
            #kernel=3,
            keywords...
        )
        loss_1 = 0.0
        loss_2 = 0.0
        _length = 0

        index = 1
        for (input, output) in validation_sets
            #println(size(data(input)), " ", size(data(output)))
            
                temp_loss_1, temp_loss_2 = intersection_over_union_loss(
                    model,
                    parameters,
                    state,
                    reshape(data(input), (size(data(input))..., 1)) |> _gpu_device,
                    reshape(data(output), (size(data(output))..., 1)) |> _gpu_device,
                )[1:2]
                loss_1 += temp_loss_1
                loss_2 += temp_loss_2
                _length += 1
            
            index += 1
        end
        #=
        loss = loss / _length
        println("LOSS: ", loss)
        return loss
        =#

        loss_1 = loss_1 / _length
        loss_2 = loss_2 / _length
        @info "LOSS 1: " loss_1
        @info "LOSS 2: " loss_2
        return loss_1 + loss_2
    end)

    @__(function _training_sets(; _length, keywords...)
        local inputs, outputs

        inputs = Vector{@__(input_type{_size})}(undef, _length)
        outputs = Vector{@__(output_type{_size})}(undef, _length)

        for index in 1:_length
            set_index = rand(1:length(training_sets))
            input, output = training_sets[set_index]
            inputs[index] = input
            outputs[index] = output
        end

        return inputs, outputs
    end; Transform=false)
end


optimizer_keywords = Ref{Any}()
@__(function main(workers, reporters)
    @info "[MASTER] Starting main function" num_workers=length(workers)
    
    @info "[MASTER] Creating Figure..."
    figure = Figure()
    @info "[MASTER] Displaying Figure..."
    display(figure)
    @info "[MASTER] Figure displayed, setting up plots..."
    
    offset = 5
    for worker in workers
        layout = GdLayout(
            figure[1:4, offset]
        )
        image_plot = c__Plot(
            layout[1, 1],
            Bas3ImageSegmentation.neuralnetwork_workload;
            input=input_type,
            output=output_type,
            #show_window=false
        )
        error_plot = c__Plot(
            layout[2, 1],
            Bas3ImageSegmentation.neuralnetwork_workload;
            error_metric=(
                :set_error,
                :batch_error,
            )
            #show_window=false
        )
        performance_plot = c__Plot(
            layout[3, 1],
            Bas3ImageSegmentation.neuralnetwork_workload;
            performance_metric=(
                :absolute_performance,
                :split_performance,
            )
            #show_window=false
        )
        
        reporter = c__Reporter(
            (;
                input=input_type,
                output=output_type,
                update_handler=@__(function _1update_handler(; keywords...) #update handler for master, fires when new report chunks are recieved
                    #println("CALL: image_plot.update_handler(keywords...)")
                    @__(update(image_plot; keywords...))
                end; Transform=false),
                
                observations_limit=250,
            ),
            (;
                error_metric=(
                    :set_error,
                    :batch_error,
                ),
                update_handler=@__(function _2update_handler(; keywords...) #update handler for master, fires when new report chunks are recieved
                    #println("CALL: error_plot.update_handler(keywords...)")
                    @__(update(error_plot; keywords...))
                end; Transform=false),
                observations_limit=250,
            ),
            (;
                performance_metric=(
                    :absolute_performance,
                    :split_performance,
                ),
                update_handler=@__(function _3update_handler(; keywords...) #update handler for master, fires when new report chunks are recieved
                    #println("CALL: performance_plot.update_handler(keywords...)")
                    @__(update(performance_plot; keywords...))
                end; Transform=false),
                observations_limit=250,
            );
            #update_handler=@__(function _4update_handler(; keywords...) #update handler for master, fires when new report chunks are recieved
            #    @__(update(error_plot; keywords...))
            #end; Transform=false)
        )
        
        reporters[worker] = reporter
        offset += 1
    end

    #resolution = 64.0
    parameters = (;
        learning_rate=[Base.LogRange(10.0^(-5), 10.0^(-3), 20)...],
        #batch_observations_length=[LinRange(1, 10, 5)..., LinRange(11, 39, 10)..., LinRange(40, 200, 10)...],
        batch_observations_length=[LinRange(1, 25, 10)..., LinRange(26, 100, 10)...],
        set_observations_factor=(1.0):1.0:(3.0),
        set_observations_iterations=[LinRange(1, 20, 10)..., #=LinRange(40, 100, 5)...=#],
        weight_1=[Base.LogRange(10.0^(-2), 10.0^(-0), 10)...],
        weight_2=[Base.LogRange(10.0^(-2), 10.0^(-0), 10)...],
        #weight_3=(0.1):0.1:(1.0),
        #weight_4=(0.1):0.1:(1.0),
        #weight_5=(0.1):0.1:(1.0),
        #kernel=[3.0, 5.0],
        dilation=[1.0, 2.0],
        feature_scale=[90.0, 120.0, 150.0, 180.0],
        #resolution=[resolution, resolution*2],
    )
    parameter_keys = keys(parameters)
    parameter_lower_bounds = NamedTuple{parameter_keys}(minimum.(values(parameters)))
    parameter_upper_bounds = NamedTuple{parameter_keys}(maximum.(values(parameters)))
    normalized_parameters = (;
        ((key => (parameters[key] .- parameter_lower_bounds[key]) ./ (parameter_upper_bounds[key] - parameter_lower_bounds[key])) for key in parameter_keys)...
    )
    scaled_normalized_parameters = (;
        ((key => ((normalized_parameters[key] .- 0.5) .* 2.0)) for key in parameter_keys)...
    )
    scaled_normalized_upper_bounds = maximum.(values(scaled_normalized_parameters))
    scaled_normalized_lower_bounds = minimum.(values(scaled_normalized_parameters))
    
 
    denormalize_parameters = @__(function _denormalize_parameters(;keywords...)
        return (;
            (
                begin
                    if key in parameter_keys
                        key => (((value / 2) + 0.5) * (parameter_upper_bounds[key] - parameter_lower_bounds[key]) + parameter_lower_bounds[key])
                    else
                        key => value
                    end
                end
                for (key, value) in keywords
            )...
        )
    end; Transform=false)

    optimization_problem = OptProblem(
        @__(function _problem(;index, keywords...)
            keywords = denormalize_parameters(;keywords...)
            training_sets_length = length(training_sets)
            local flag2 = false
            local loss
            while true
                try
                    #=
                    #1,48735E-05	40	2	11	0,517947468	0,138949549	2	45	50	239,2916852
                    keywords = (;
                        learning_rate=0.000148735,
                        batch_observations_length=40,
                        set_observations_factor=2,
                        set_observations_iterations=11,
                        weight_1=0.517947468,
                        weight_2=0.138949549,
                        dilation=2,
                        feature_scale=45,
                        resolution=50,
                    )
                    =#
                    #6,15848E-05	625,75	2	17,88888889	0,359381366	0,003593814	1	30	128	12,65940294
                    #=
                    keywords = (;
                        learning_rate=0.0000615848,
                        #batch_observations_length=625,
                        batch_observations_length=1,
                        set_observations_factor=2,
                        set_observations_iterations=17.88888889,
                        weight_1=0.359381366,
                        weight_2=0.003593814,
                        dilation=1,
                        feature_scale=30,
                        resolution=128,
                    )
                    =#
                    loss = @__(Bas3ImageSegmentation.neuralnetwork_workload(;
                        training_sets=_training_sets,
                        validation_sets,
                        neuralnetwork_definition=neuralnetwork_definition,
                        neuralnetwork_setup=neuralnetwork_setup,
                        neuralnetwork_validation=neuralnetwork_validation,
                        callback=@__(function _callback5(; keywords...)
                            @__(update(reporters[index]; keywords...))
                        end; Transform=false),
                        tasks_length=1,
                        time_stabilized=0.5,
                        test_probability=0.01,
                        test_coverage=0.5,
                        observation_total=50000,
                        history_time_array_length=25,
                        #resolution=200,
                        keywords...
                    ); Transform=true)
                    flag2 = true
                catch error
                    if isa(error, Bas3ImageSegmentation.Bas3Lux.CUDA.OutOfGPUMemoryError) == false
                        throw(error)  # Propagate unknown errors
                    else
                        @warn "Caught OutOfGPUMemoryError"
                    end
                end
                
                reset(reporters[index])
                if flag2 == true
                    break
                end
            end
            return loss
        end; Transform=false);
        lower_bounds=scaled_normalized_lower_bounds,
        upper_bounds=scaled_normalized_upper_bounds,
        parallelization=(; workers=workers),
        #parallelization=workers
    )

    optimizer = IGABOptimizer(;
        #surrogate=@__(Surrogate{type_of(parameter_lower_bounds),Float64,GsProcess{GsKernel}}(;input=hyperparameter_input, output=hyperparameter_output)),
        #tradeoffs=[0.9, 0.8, 0.7, 0.4],
        surrogate=@__(Surrogate{type_of(values(scaled_normalized_lower_bounds)),Float64,GsProcess{GsKernel}}()),
        tradeoffs=[0.1, 0.2, 0.3, 0.6],
        sampler=DsctSample(scaled_normalized_parameters),
        incubments=@__(function _incubments(; points_length, keywords...)
                if points_length > 100
                    return 100
                else
                    incubments = round(Int64, 0.5 * points_length)
                    if incubments > 0
                        return incubments
                    else
                        return points_length
                    end
                end
            end; Transform=false),
        sample_amount=10^4,
    )


    #throw("")
    @info "[MASTER] Creating optimizer plot..."
    optimizer_plot = c__Plot(
        figure[1:4, 1:4],
        optimizer,
        optimization_problem
    )
    @info "[MASTER] Optimizer plot created, starting solve()..."

    update_index = 0

    t0 = time()
    solve(
        optimization_problem,
        optimizer;
        callback=@__(function _callback2(; keywords...)
            update_index += 1
            if update_index >= 2
                optimizer_keywords[] = keywords
                @__(update(optimizer_plot; keywords...))
                #update_index = 0
            end

            if time() - t0 > (12 * 60 * 60)
                return false
            else
                return true
            end
        end; Transform=false),
        extra_amount=0
    )

end)
@info "[MASTER] Calling main() with workers" workers
main(workers, reporters)
#"C:\Users\OsW-x\Desktop\Optimierung_1.xlsx"
#"C:/Users/OsW-x/Desktop/Optimierung_1.xlsx"
#=
@__(write_xlsx(
    "C:/Users/OsW-x/Desktop/Optimierung_8.xlsx",
    optimizer_keywords[][:Optimizer];
    denormalize=denormalize_parameters,
))
=#
