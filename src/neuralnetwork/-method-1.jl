@__(function neuralnetwork_definition(;
    input,
    output,
    #kernel,
    dilation,
    feature_scale,
    keywords...
)
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
    println(show_layer(chain))
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
    GC.gc()
    Bas3Lux.CUDA.reclaim()
    model = neuralnetwork_definition(;
        input=(128, 128, 3), #TODO: make this dynamic
        output=(128, 128, 2), #TODO: make this dynamic
        #kernel=keywords[:kernel],
        #kernel=3,
        keywords...
    )
    error = 0.0
    


    function generate_patches(height, width, patch_height, patch_width)
        patches = []

        for row_start in 1:patch_height:height
            row_end = min(row_start + patch_height - 1, height)

            for col_start in 1:patch_width:width
                col_end = min(col_start + patch_width - 1, width)

                push!(patches, (row_start:1:row_end, col_start:1:col_end))
            end
        end

        return patches
    end

    index = 1
    for (input, output) in validation_sets
        @time begin
            
            #=
            error += @__(weighted_crossentropy_error(
                model,
                parameters,
                state,
                reshape(data(input), (4032, 3024, 3, 1)) |> _gpu_device,
                reshape(data(output), (4032, 3024, 2, 1)) |> _gpu_device;
                weight_1=0.95,
                weight_2=0.05,
          
          
                ))[1]
            =#
            #=
            error += @__(weighted_crossentropy_error(
                model,
                parameters,
                state,
                Bas3Lux.CUDA.cu(reshape(data(input), (4032, 3024, 3, 1)); unified=true),
                Bas3Lux.CUDA.cu(reshape(data(output), (4032, 3024, 2, 1)); unified=true);
                weight_1=0.95,
                weight_2=0.05,
            ))[1]
            =#
            
            input_data = data(input)
            output_data = data(output)
            for indices in generate_patches(756, 1008, 128, 128)
                #println((indices..., 3))
                if length(indices[1]) != 128 || length(indices[2]) != 128
                    continue
                else
                    error += @__(weighted_crossentropy_error(
                        model,
                        parameters,
                        state,
                        reshape(input_data[indices..., 1:3], (128, 128, 3, 1)) |> _gpu_device,
                        reshape(output_data[indices..., 1:2], (128, 128, 2, 1)) |> _gpu_device;
                        weight_1=0.99,
                        weight_2=0.01,
                    ))[1]
                end
            end
            
        end
        index += 1
    end
    
    #=
    parameters = parameters |> _cpu_device
    state = state |> _cpu_device
    for (input, output) in validation_sets
        error += @__(weighted_crossentropy_error(
            model,
            parameters,
            state,
            reshape(data(input), (4032, 3024, 3, 1)),
            reshape(data(output), (4032, 3024, 2, 1));
            weight_1=0.95,
            weight_2=0.05,
        ))[1]
    end
    =#
    println(error)
    return error
end)

@__(function neuralnetwork_workload(;
    neuralnetwork_definition=Bas3ImageSegmentation.neuralnetwork_definition,
    neuralnetwork_setup=Bas3ImageSegmentation.neuralnetwork_setup,
    neuralnetwork_validation=Bas3ImageSegmentation.neuralnetwork_validation,
    validation_sets,
    keywords...
)
    @info "[WORKLOAD] Starting neural network workload" validation_sets_length=length(validation_sets)
    println(keywords)
    #=
    (training_sets = Serialization.__deserialized_types__.var"#_training_sets#18"{Serialization.__deserialized_types__.var"#_training_sets#12#19"}(Serialization.__deserialized_types__.var"#_training_sets#12#19"()),
    callback = Serialization.__deserialized_types__.var"#_callback#20"{Serialization.__deserialized_types__.var"#_callback#13#21"}(Serialization.__deserialized_types__.var"#_callback#13#21"()),
    tasks_length = 24,
    time_stabilized = 0.25,
    test_probability = 0.25,
    test_coverage = 0.66,
    observation_total = 20000,
    learning_rate = 0.41,
    batch_observations_length = 20.0,
    set_observations_factor = 3.5,
    set_observations_iterations = 5.0,
    images_resolution = 192.0,
    weight_1 = 0.4,
    weight_2 = 0.2,
    weight_3 = 0.5,
    weight_4 = 0.4,
    weight_5 = 0.4,
    kernel = 5.0)
    =#
    #=
    keywords = (;
        #=
        training_sets=keywords.training_sets,
        callback=keywords.callback,
        tasks_length=keywords.tasks_length,
        time_stabilized=keywords.time_stabilized,
        test_probability=keywords.test_probability,
        test_coverage=keywords.test_coverage,
        observation_total=keywords.observation_total,
        =#
        training_sets=keywords[:training_sets],
        callback=keywords[:callback],
        tasks_length=keywords[:tasks_length],
        time_stabilized=keywords[:time_stabilized],
        test_probability=keywords[:test_probability],
        test_coverage=keywords[:test_coverage],
        observation_total=keywords[:observation_total],
        learning_rate=0.41,
        batch_observations_length=128.0,
        set_observations_factor=4.0,
        set_observations_iterations=5.0,
        resolution=300.0,
        weight_1=0.4,
        weight_2=0.2,
        kernel=3.0
    )
    =#
    println(Bas3Lux.CUDA.pool_status())
    #_size = round(Int64, keywords[:resolution])
    #_size = (_size, _size)
    #=
    println("training_sets: ", typeof(training_sets), " ", typeof(training_sets) <: Function)
    for (input, output) in training_sets(; _length=10, _size)
        println(typeof(input), " ", typeof(output))
    end
    println("validation_sets: ", typeof(validation_sets), " ", typeof(validation_sets) <: Function)
    for (input, output) in validation_sets
        println(typeof(input), " ", typeof(output))
    end
    =#
    _gpu_device = gpu_device()
    _cpu_device = cpu_device()
    while true
        model = neuralnetwork_definition(;
            #input=(_size..., 3),
            #output=(_size..., 2),
            #_size,
            #kernel=3,
            keywords...
        )
        parameters, state, optimizer = neuralnetwork_setup(;
            model,
            keywords...
        )
        parameters = parameters |> _gpu_device
        state = state |> _gpu_device
        optimizer = optimizer |> _gpu_device

        parameters, state, optimizer = neuralnetwork_training(;
            _gpu_device,
            _cpu_device,
            model,
            parameters,
            optimizer,
            state,
            #_size,
            keywords...
        )
        
        @info "[WORKLOAD] Training phase complete, starting validation..."
        error = neuralnetwork_validation(;
            model,
            parameters,
            state,
            _gpu_device,
            _cpu_device,
            validation_sets,
            keywords...
        )
        if isnan(error) == false
            @info "[WORKLOAD] ✓ Workload complete!" final_error=round(error; digits=6)
            return error
        end
        @warn "[WORKLOAD] NaN error detected, retrying training..."
    end
end)
function neuralnetwork_training__spawn_training_set_thread(
    tasks,
    to_producer_channels,
    to_producer_channels_length,
    to_consumer_channel,
    training_sets
)
    push!(to_producer_channels, Channel{Bool}(1))

    to_producer_channels_length += 1
    println("NEW TASK ", to_producer_channels_length)

    put!(to_producer_channels[to_producer_channels_length], true)
    Task = let to_producer_channels = to_producer_channels, to_producer_channels_length = to_producer_channels_length
        Threads.@spawn(while true
            yield()
            if take!(to_producer_channels[to_producer_channels_length]) == true
                #=
                Task = Threads.@async(
                    begin
                        try
                            #return training_sets(; _length=set_observations_length, _size)
                            return training_sets()
                        catch
                            return ArgumentError("error")
                        end
                    end
                )
                put!(to_consumer_channel, (to_producer_channels_length, fetch(Task)))
                =#
                try
                    put!(to_consumer_channel, (to_producer_channels_length, training_sets()))
                catch e
                    @error "Spawned task failed" exception=(e, catch_backtrace())
                    rethrow()
                end
            else
                println("KILL TASK ", to_producer_channels_length)
                break
            end
        end)
    end
    push!(tasks, Task)
    #=
    try
        take!(to_consumer_channel)
        put!(to_producer_channels[to_producer_channels_length], true)
    catch
        break
    end
    =#

    return tasks, to_producer_channels, to_producer_channels_length, to_consumer_channel
end
import .Threads
#TODO: double batching?
function neuralnetwork_training__computation(parameters, state, model, gpu_temp_input_model_array, gpu_temp_output_model_array, optimizer; keywords...)
    error, Pullback = let parameters = parameters, state = state, model = model, gpu_temp_input_model_array = gpu_temp_input_model_array, gpu_temp_output_model_array = gpu_temp_output_model_array
        pullback(
            (parameters) -> (
                @__(weighted_crossentropy_error(
                model,
                parameters,
                state,
                gpu_temp_input_model_array,
                gpu_temp_output_model_array;
                keywords...
            ))[1]
            #quadratic_error(model, parameters, state, gpu_temp_input_model_array, gpu_temp_output_model_array)[1];
            ),
            parameters
        )
    end
    Gradients = only(Pullback(error))

    update!(optimizer, parameters, Gradients)
    return error
end
import InteractiveUtils.@code_warntype
import .Threads.nthreads
function neuralnetwork_training(;
    #(gpu_device=>_gpu_device),
    _gpu_device,
    _cpu_device,
    model,
    parameters,
    optimizer,
    state,
    training_sets,
    batch_observations_length,
    set_observations_factor,
    observation_total=1,
    #_size,
    set_observations_iterations,
    callback,
    tasks_length=1,
    test_probability=0.1,
    test_coverage=0.5,
    time_array_index=1,
    time_stabilized=1.0,
    history_time_array_length=10,
    keywords...
)


    #println("batch_observations_length ", batch_observations_length)
    #println("set_observations_factor ", set_observations_factor)
    batch_observations_length = round(Int64, batch_observations_length)
    set_observations_iterations = round(Int64, set_observations_iterations)

    set_observations_length = round(Int64, batch_observations_length * set_observations_factor)
    previous_set_observations_length = 0

    _training_sets = () -> training_sets(; _length=set_observations_length, keywords...)

    to_producer_channels_length = 0
    to_producer_channels = Array{Channel{Bool},1}()
    to_consumer_channel = Channel{v__Tuple{Int64,v__Tuple{Any,Any}}}(1)
    tasks = Array{Threads.Task,1}()
    #if tasks_length > 0
    for _1 in 1:tasks_length
        tasks, to_producer_channels, to_producer_channels_length, to_consumer_channel = neuralnetwork_training__spawn_training_set_thread(
            tasks,
            to_producer_channels,
            to_producer_channels_length,
            to_consumer_channel,
            _training_sets
        )
    end


    while true
        if isready(to_consumer_channel) == true
            break
        else
            if true in istaskfailed.(tasks)
                fetch.(tasks)
                throw(ArgumentError("error in task"))
            end
            yield()
        end
    end

    #end

    Array_Index, set = take!(to_consumer_channel)
    put!(to_producer_channels[Array_Index], true)
    #=
    memory_parameters = Base.summarysize(parameters)
    memory_state = Base.summarysize(state)
    memory_optimizer = Base.summarysize(optimizer)
    input_data = data(set[1][1])
    output_data = data(set[1][2])
    println(typeof(input_data), " ", typeof(output_data))
    memory_gpu_temp_input_model_array = reshape(input_data, size(input_data)..., 1) |> _gpu_device
    memory_gpu_temp_output_model_array = reshape(output_data, size(output_data)..., 1) |> _gpu_device
    memory_observation = Base.sizeof(memory_gpu_temp_input_model_array) + Base.sizeof(memory_gpu_temp_output_model_array)
    #memory_observation = Base.summarysize(set[1])

    #memory_accelerator = Bas3Lux.CUDA.free_memory()
    #println(fieldnames(typeof(Bas3Lux.CUDA.memory_stats())))
    #(:size, :size_updated, :live, :last_time, :last_gc_time, :last_freed)
    #memory_accelerator = Bas3Lux.CUDA.memory_stats().size
    memory_accelerator = (Bas3Lux.CUDA.memory_limits().hard) * 0.8

    memory_factor = floor(Int64, (((memory_accelerator - memory_parameters - memory_state) * 0.8) / memory_observation))
    #=
    println("memory_observation ", memory_observation)
    println("memory_accelerator ", memory_accelerator)
    println("memory_parameters ", memory_parameters)
    println("memory_state ", memory_state)
    println("memory_factor ", memory_factor)
    =#
    #calculate in gb
    println("memory_observation ", round(memory_observation / 1024^3; digits=2), " GB")
    println("memory_accelerator ", round(memory_accelerator / 1024^3; digits=2), " GB")
    println("memory_parameters ", round(memory_parameters / 1024^3; digits=2), " GB")
    println("memory_state ", round(memory_state / 1024^3; digits=2), " GB")
    println("memory_factor ", memory_factor, " (", round(memory_factor * memory_observation / 1024^3; digits=2), " GB)")
    =#
    #neuralnetwork_training__computation(parameters, state, model, gpu_temp_input_model_array, gpu_temp_output_model_array; keywords...)
    optimizer = optimizer |> _cpu_device
    parameters = parameters |> _cpu_device
    state = state |> _cpu_device
    test_optimizer = deepcopy(optimizer) |> _gpu_device
    test_parameters = deepcopy(parameters) |> _gpu_device
    test_state = deepcopy(state) |> _gpu_device
    #test_input, test_output = set[1]
    #test_input, test_output = set[1][1], set[2][1]
    #println(typeof(test_input), " ", typeof(test_output))
    test_input_data = ()->(data(set[1][rand(1:length(set[1]))]))
    test_output_data = ()->(data(set[2][rand(1:length(set[2]))]))
    #println(size(test_input_data), " ", size(test_output_data))
    adjust!(test_optimizer, n=1)
    allocate_accelerator_memory = function _allocate_accelerator_memory(memory_factor)
        (
            (;
                input=cat((test_input_data() for _1 in 1:memory_factor)...; dims=4) |> _gpu_device,
                output=cat((test_output_data() for _1 in 1:memory_factor)...; dims=4) |> _gpu_device
            ),
            (;
                input=cat((test_input_data() for _1 in 1:memory_factor)...; dims=4) |> _gpu_device,
                output=cat((test_output_data() for _1 in 1:memory_factor)...; dims=4) |> _gpu_device
            )
        )
    end

    #=
    while low <= high
        mid = (low + high) ÷ 2
        println("Trying memory_factor = ", mid)

        try
            accelerator_memory = allocate_accelerator_memory(mid)

            neuralnetwork_training__computation(
                test_parameters,
                test_state,
                model,
                accelerator_memory[rand(1:2)].input,
                accelerator_memory[rand(1:2)].output,
                test_optimizer;
                keywords...
            )
            Bas3Lux.CUDA.unsafe_free!(accelerator_memory[1].input)
            Bas3Lux.CUDA.unsafe_free!(accelerator_memory[1].output)
            Bas3Lux.CUDA.unsafe_free!(accelerator_memory[2].input)
            Bas3Lux.CUDA.unsafe_free!(accelerator_memory[2].output)
            # Success: Try a higher memory_factor
            best = mid
            low = mid + 1
        catch e
            if isa(e, Bas3Lux.CUDA.OutOfGPUMemoryError) == false
                throw(e)  # Propagate unknown errors
            end
            # Failure: Try a smaller memory_factor
            high = mid - 1
        end
    end
    accelerator_memory = nothing
    GC.gc()
    Bas3Lux.CUDA.reclaim()
    =#
    #=
    function memory_limit_exceeded(bytes::Integer)
    limit = memory_limits()
    limit.hard > 0 || return false

    dev = device()
    used_bytes = if stream_ordered(dev) && driver_version() >= v"12.2"
        # we configured the memory pool to do this for us
        return false
    elseif stream_ordered(dev)
        pool = pool_create(dev)
        Int(attribute(UInt64, pool, MEMPOOL_ATTR_RESERVED_MEM_CURRENT))
    else
        # NOTE: cannot use `memory_info()`, because it only reports total & free memory.
        #       computing `total - free` would include memory allocated by other processes.
        #       NVML does report used memory, but is slow, and not available on all platforms.
        memory_stats().live
    end

    return used_bytes + bytes > limit.hard
    end
    =#
    limit = Bas3Lux.CUDA.memory_limits()
    @info "[MEMORY] Starting memory factor optimization" batch_observations_length soft_limit_gb=round(limit.soft/1024^3; digits=2)
    low = 1
    high = 1
    best = 1
    while high <= batch_observations_length
        @info "[MEMORY] Testing overload" memory_factor=high
        flag = false
        GC.gc()
        Bas3Lux.CUDA.reclaim()
        accelerator_memory = allocate_accelerator_memory(high)
        stats = Bas3Lux.CUDA.memory_stats()
        if stats.live < limit.soft
            neuralnetwork_training__computation(
                test_parameters,
                test_state,
                model,
                accelerator_memory[rand(1:2)].input,
                accelerator_memory[rand(1:2)].output,
                test_optimizer;
                keywords...
            )
            #Bas3Lux.CUDA.unsafe_free!(accelerator_memory[1].input)
            #Bas3Lux.CUDA.unsafe_free!(accelerator_memory[1].output)
            #Bas3Lux.CUDA.unsafe_free!(accelerator_memory[2].input)
            #Bas3Lux.CUDA.unsafe_free!(accelerator_memory[2].output)
            # Success: Try a higher memory_factor
            stats = Bas3Lux.CUDA.memory_stats()
            
            if stats.live < limit.soft
                #low = best
                best = high
                high = high * 2
            else
                flag = true
            end
        else
            flag = true
        end
        if flag == true
            break
        end
    end
    low = best
    #high = best
    @info "[MEMORY] Binary search phase" low high
    while low <= high
        mid = (low + high) ÷ 2
        @info "[MEMORY] Testing" memory_factor=mid
        flag = false
        GC.gc()
        Bas3Lux.CUDA.reclaim()
        accelerator_memory = allocate_accelerator_memory(mid)
        stats = Bas3Lux.CUDA.memory_stats()
        if stats.live < limit.soft
            neuralnetwork_training__computation(
                test_parameters,
                test_state,
                model,
                accelerator_memory[rand(1:2)].input,
                accelerator_memory[rand(1:2)].output,
                test_optimizer;
                keywords...
            )
            #Bas3Lux.CUDA.unsafe_free!(accelerator_memory[1].input)
            #Bas3Lux.CUDA.unsafe_free!(accelerator_memory[1].output)
            #Bas3Lux.CUDA.unsafe_free!(accelerator_memory[2].input)
            #Bas3Lux.CUDA.unsafe_free!(accelerator_memory[2].output)
            # Success: Try a higher memory_factor
            stats = Bas3Lux.CUDA.memory_stats()
            if stats.live < limit.soft
                best = mid
                low = mid + 1
            else
                flag = true
            end
        else
            flag = true
        end
        if flag == true
            high = mid - 1
        end
    end
    #=
    @code_warntype             neuralnetwork_training__computation(
                test_parameters,
                test_state,
                model,
                accelerator_memory[rand(1:2)].input,
                accelerator_memory[rand(1:2)].output,
                test_optimizer;
                keywords...
            )
            =#
    accelerator_memory = nothing
    memory_factor = best
    @info "[MEMORY] ✓ Optimization complete" memory_factor gpu_mem_used_gb=round(Bas3Lux.CUDA.memory_stats().live/1024^3; digits=2)
    flush(stdout); flush(stderr)
    GC.gc()
    Bas3Lux.CUDA.reclaim()
    @info "[MEMORY] After reclaim" gpu_pool_status=Bas3Lux.CUDA.pool_status()
    #println(Bas3Lux.CUDA.pool_status())
    test_optimizer = test_optimizer |> _cpu_device
    test_parameters = test_parameters |> _cpu_device
    test_state = test_state |> _cpu_device

    optimizer = optimizer |> _gpu_device
    parameters = parameters |> _gpu_device  
    state = state |> _gpu_device
    #throw("")
    if memory_factor < 1
        memory_factor = 1
    end
    #memory_gpu_temp_input_model_array = rand(Float32, size(input_data)..., 3, memory_factor) |> _gpu_device
    #memory_gpu_temp_output_model_array = rand(Float32, size(output_data)..., 2, memory_factor) |> _gpu_device
    #throw("")
    temp_time_array_index = time_array_index
    time_array_array_length = batch_observations_length #TODO: limit this somehow based on available memor

    if batch_observations_length <= memory_factor
        time_array_array_length = batch_observations_length
    else
        time_array_array_length = memory_factor
    end
    time_array_array = Array{Array{Float64,1},1}(undef, time_array_array_length)
    for Index = 1:time_array_array_length
        time_array_array[Index] = Array{Float64,1}()
    end

    observations = 0
    observation_delta = 0

    gpu_semaphore = Base.Semaphore(1)

    time_start = time_previous = time()
    last_log_time = time_start
    log_interval = 5.0  # Log every 5 seconds
    batch_count = 0
    iteration_count = 0
    last_error = 0.0
    micro_batch_count = 0
    set_count = 0

    local absolute_performance = 0.0
    @info "[TRAINING] ═══════════════════════════════════════════════════════════════"
    @info "[TRAINING] Starting training loop" target_observations=observation_total batch_size=batch_observations_length iterations_per_set=set_observations_iterations memory_factor
    @info "[TRAINING] ═══════════════════════════════════════════════════════════════"
    flush(stdout); flush(stderr)
    while true
        set_count += 1
        println("[SET] Starting set $set_count with $(length(set[1])) samples")
        flush(stdout)

        macro_dataloader = DataLoader(set, batchsize=batch_observations_length)

        for _2 = 1:set_observations_iterations
            iteration_count += 1
            println("[ITER] Starting iteration $iteration_count (set $set_count, iter $_2/$(round(Int, set_observations_iterations)))")
            flush(stdout)
            for (temp_input_model_array, temp_output_model_array) in macro_dataloader
                batch_count += 1
                current_set_observations_length = length(temp_input_model_array)

                if current_set_observations_length != previous_set_observations_length
                    Offset = mod(current_set_observations_length, temp_time_array_index)
                    local Gradient_Accumulation
                    if Offset != 0
                        if current_set_observations_length < temp_time_array_index
                            temp_time_array_index = current_set_observations_length
                        end
                        Gradient_Accumulation = Int((current_set_observations_length - Offset) / temp_time_array_index) + 1
                    else
                        Gradient_Accumulation = Int(current_set_observations_length / temp_time_array_index) # + 1
                    end
                    adjust!(optimizer, n=Gradient_Accumulation)
                    previous_set_observations_length = Int(current_set_observations_length)
                end
                
                Micro_Dataloader = DataLoader((temp_input_model_array, temp_output_model_array), batchsize=temp_time_array_index)
                Micro_Iterations = 1
                for _3 in 1:Micro_Iterations
                    observations += current_set_observations_length
                    observation_delta += current_set_observations_length
                    micro_batch_in_iter = 0
                    for (temp_input_model_array, temp_output_model_array) in Micro_Dataloader
                        micro_batch_count += 1
                        micro_batch_in_iter += 1
                        #Bas3Lux.CUDA.@time begin
                        gpu_temp_input_model_array = cat(data.(temp_input_model_array)...; dims=4) |> _gpu_device
                        gpu_temp_output_model_array = cat(data.(temp_output_model_array)...; dims=4) |> _gpu_device
                        array_size = size(gpu_temp_input_model_array)[4]
                        #accelerator_memory[1].input[:, :, :, 1:array_size] = cat(data.(temp_input_model_array)...; dims=4)
                        #accelerator_memory[1].output[:, :, :, 1:array_size] = cat(data.(temp_output_model_array)...; dims=4)
                        Base.acquire(gpu_semaphore)
                        #@async begin
                            #=
                            error, Pullback = let parameters = parameters, state = state, model = model, gpu_temp_input_model_array = gpu_temp_input_model_array, gpu_temp_output_model_array = gpu_temp_output_model_array
                                pullback(
                                    (parameters) -> (
                                        @__(weighted_crossentropy_error(
                                        model,
                                        parameters,
                                        state,
                                        gpu_temp_input_model_array,
                                        gpu_temp_output_model_array;
                                        keywords...
                                    ))[1]
                                    #quadratic_error(model, parameters, state, gpu_temp_input_model_array, gpu_temp_output_model_array)[1];
                                    ),
                                    parameters
                                )
                            end
                            Gradients = only(Pullback(error))

                            update!(optimizer, parameters, Gradients)
                            =#
                            error = neuralnetwork_training__computation(
                                parameters,
                                state,
                                model,
                                gpu_temp_input_model_array,
                                gpu_temp_output_model_array,
                                #accelerator_memory[1].input[:, :, :, 1:array_size],
                                #accelerator_memory[1].output[:, :, :, 1:array_size],
                                optimizer;
                                keywords...
                            )
                            last_error = error
                            
                            # Log every 10 micro-batches or on first batch
                            if micro_batch_count == 1 || micro_batch_count % 10 == 0
                                println("[BATCH] #$micro_batch_count | iter=$iteration_count | obs=$observations | err=$(round(error; digits=4)) | batch_size=$array_size")
                                flush(stdout)
                            end
                            
                            callback(;
                                error,
                                model,
                                parameters,
                                state,
                                input=v__Image_Data(shape(temp_input_model_array[1]), gpu_temp_input_model_array),
                                #output=v__Image_Data((:background, :scar, :redness, :hematoma, :necrosis), gpu_temp_output_model_array),
                                output=v__Image_Data(shape(temp_output_model_array[1]), gpu_temp_output_model_array),
                                observation_delta=array_size,
                                _cpu_device,
                                _gpu_device,
                                absolute_performance
                            )
                            #Bas3Lux.CUDA.unsafe_free!(gpu_temp_input_model_array)
                            #Bas3Lux.CUDA.unsafe_free!(gpu_temp_output_model_array)
                            #GC.gc()
                            #Bas3Lux.CUDA.reclaim()
                            stats = Bas3Lux.CUDA.memory_stats()
                            if stats.live < limit.soft
                                GC.gc()
                                Bas3Lux.CUDA.reclaim()
                            end
                            
                            # Periodic logging
                            current_time = time()
                            if current_time - last_log_time > log_interval
                                elapsed = current_time - time_start
                                obs_per_sec = observations / elapsed
                                progress_pct = 100.0 * observations / observation_total
                                eta_seconds = (observation_total - observations) / max(obs_per_sec, 1.0)
                                gpu_mem_gb = round(stats.live / 1024^3; digits=2)
                                progress_bar = repeat("█", round(Int, progress_pct / 5)) * repeat("░", 20 - round(Int, progress_pct / 5))
                                println("[TRAINING] $(progress_bar) $(round(progress_pct; digits=1))% | obs: $observations/$observation_total | err: $(round(last_error; digits=4)) | $(round(obs_per_sec; digits=0)) obs/s | ETA: $(round(eta_seconds/60; digits=1))min | GPU: $(gpu_mem_gb)GB | perf: $(round(absolute_performance; digits=0))")
                                flush(stdout)
                                last_log_time = current_time
                            end
                            
                            Base.release(gpu_semaphore)
                            #Bas3Lux.CUDA.unsafe_free!(gpu_temp_input_model_array)
                            #Bas3Lux.CUDA.unsafe_free!(gpu_temp_output_model_array)
                        #end
                        #end
                        #println(array_size)
                    end

                    if observations > observation_total
                        for _1 = 1:to_producer_channels_length
                            Array_Index, set = take!(to_consumer_channel)
                            put!(to_producer_channels[Array_Index], false)
                        end
                        fetch.(tasks)
                        Base.acquire(gpu_semaphore)
                        total_time = time() - time_start
                        final_obs_per_sec = observations / total_time
                        @info "[TRAINING] ✓ Training complete!" total_observations=observations total_batches=batch_count total_iterations=iteration_count total_time_min=round(total_time/60; digits=2) final_obs_per_sec=round(final_obs_per_sec; digits=1) final_performance=round(absolute_performance; digits=1)
                        println("time_current: ", total_time)
                        println("observations: ", observations)
                        println("observations/time_current: ", final_obs_per_sec)
                        return parameters, state, optimizer
                    end
                end
                
                
                if  (
                    current_set_observations_length == batch_observations_length
                    ) && (
                        (time() - time_previous) > time_stabilized
                    )
                    Base.acquire(gpu_semaphore)

                    time_current = time()
                    push!(time_array_array[time_array_index], observation_delta / (time_current - time_previous))
                    if length(time_array_array[time_array_index]) > history_time_array_length
                        popfirst!(time_array_array[time_array_index])
                    end
                    time_previous = time_current
                    observation_delta = 0

                    
                    #println(length.(time_array_array))
                    if rand() >= (1 - test_probability)
                        temp_time_array_index = rand(1:1:time_array_array_length)
                        #println("RETEST ", temp_time_array_index)
                    else
                        time_array_index_array = Array{Int64,1}()
                        time_untested_flag = false
                        untested_time_array_array_length = 0
                        for index in shuffle(1:1:time_array_array_length)
                            time_array_length = length(time_array_array[index])
                            if time_array_length > 0
                                push!(time_array_index_array, index)
                            else
                                untested_time_array_array_length += 1
                                if untested_time_array_array_length >= round(Int64, time_array_array_length * (1 - test_coverage))
                                    temp_time_array_index = index
                                    time_untested_flag = true
                                    #println("TEST ", temp_time_array_index)
                                    break
                                end
                            end
                        end
                        if time_untested_flag == false
                            average_time_array = [sum(time_array_array[index]) / length(time_array_array[index]) for index in time_array_index_array]
                            
                            #println(round.(average_time_array; digits=1))
                            average_time_array_index = argmax(average_time_array)
                            temp_time_array_index = time_array_index_array[average_time_array_index]
                            #absolute_performance = sum(time_array_array[temp_time_array_index]) / length(time_array_array[temp_time_array_index])
                            absolute_performance = average_time_array[average_time_array_index]
                            #println("SELECT ", temp_time_array_index, " ", sum(time_array_array[temp_time_array_index]) / length(time_array_array[temp_time_array_index]))
                        end
                    end
                    if time_array_index != temp_time_array_index
                        time_array_index = temp_time_array_index
                        previous_set_observations_length = 0
                    end

                    Base.release(gpu_semaphore)
                end
            end
        end

        if (
            isready(to_consumer_channel) == false
        ) && (
            length(tasks) < nthreads()
        ) && (
            ((1 - (Base.Sys.free_memory() / Base.Sys.total_memory())) < 0.8) || (to_producer_channels_length == 0)
        )
            tasks, to_producer_channels, to_producer_channels_length, to_consumer_channel = neuralnetwork_training__spawn_training_set_thread(
                tasks,
                to_producer_channels,
                to_producer_channels_length,
                to_consumer_channel,
                _training_sets
            )
        end

        Array_Index, set = take!(to_consumer_channel)
        put!(to_producer_channels[Array_Index], true)
    end
end


