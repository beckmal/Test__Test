import Bas3.stop;
export stop;
import Bas3.update;
export update;
import Bas3.reset;
export reset;
@__(function Bas3.update(reporter::v__Reporter_Error; error, observation_delta, keywords...)
    #println("CALL: update(v__Reporter_Error, error, observation_delta, keywords...)")
    reporter.observations_current[] -= observation_delta
    reporter.observation_total[] += observation_delta
    push!(reporter.error, error)
    push!(reporter.observation, reporter.observation_total[])
    if (reporter.observations_current[] <= 0) && (isready(reporter.channel) == false)
        put!(
            reporter.channel,
            (
                2,
                (;
                    error=reporter.error,
                    observation=reporter.observation,
                )
            )
        )
        reporter.observations_current[] = reporter.observations_limit[]

        empty!(reporter.error)
        empty!(reporter.observation)
    end
end)
@__(function Bas3.update(reporter::v__Reporter_Performance; absolute_performance, observation_delta, keywords...)
    #println("CALL: update(v__Reporter_Performance, absolute_performance, observation_delta, keywords...)")
    reporter.observations_current[] -= observation_delta
    reporter.observation_total[] += observation_delta
    push!(reporter.absolute_performance, absolute_performance)
    push!(reporter.observation, reporter.observation_total[])
    if (reporter.observations_current[] <= 0) && (isready(reporter.channel) == false)
        put!(
            reporter.channel,
            (
                2,
                (;
                    absolute_performance=reporter.absolute_performance,
                    observation=reporter.observation,
                )
            )
        )
        reporter.observations_current[] = reporter.observations_limit[]
        empty!(reporter.absolute_performance)
        empty!(reporter.observation)
    end
end)
@__(function Bas3.update(reporter::v__Reporter_Image_Data; input, output, model, parameters, state, _cpu_device, observation_delta, keywords...)
    #println("CALL: update(v__Reporter_Image_Data, input, output, model, parameters, state, _cpu_device, observation_delta, keywords...)")
    reporter.observations_current[] -= observation_delta
    if (reporter.observations_current[] <= 0) && (isready(reporter.channel) == false)
        predicted_output, state = model(data(input), parameters, state)
        put!(
            reporter.channel,
            (
                2,
                (;
                    input=v__Image_Data(input.shape, data(input)[:, :, :, 1] |> _cpu_device),
                    output=(;
                        reference=v__Image_Data(output.shape, data(output)[:, :, :, 1] |> _cpu_device),
                        predicted=v__Image_Data(output.shape, predicted_output[:, :, :, 1] |> _cpu_device)
                    ),
                )
            )
        )
        reporter.observations_current[] = reporter.observations_limit[]
    end
end)
@__(function Bas3.update(reporter::v__Reporter_Composition; keywords...)
    #println("CALL: update(v__Reporter_Composition, keywords...)")
    for reporter in reporter.reporters
        @__(update(reporter; keywords...))
    end
end)

@__(function Bas3.stop(reporter::v__Reporter_Image_Data)
        if isready(reporter.channel) == true
            take!(reporter.channel)
        end
        put!(reporter.channel, (0, nothing))
    end; Transform=false)
@__(function Bas3.stop(reporter::v__Reporter_Error)
        if isready(reporter.channel) == true
            take!(reporter.channel)
        end
        put!(reporter.channel, (0, nothing))
    end; Transform=false)
@__(function Bas3.stop(reporter::v__Reporter_Performance)
        if isready(reporter.channel) == true
            take!(reporter.channel)
        end
        put!(reporter.channel, (0, nothing))
    end; Transform=false)
@__(function Bas3.stop(reporter::v__Reporter_Composition)
    #println("CALL: stop(v__Reporter_Composition)")
    for reporter in reporter.reporters
        stop(reporter)
    end
end)
@__(function Base.reset(reporter::v__Reporter_Image_Data)
    if isready(reporter.channel) == true
        take!(reporter.channel)
    end
end)
@__(function Base.reset(reporter::v__Reporter_Error)
    if isready(reporter.channel) == true
        take!(reporter.channel)
    end
    put!(reporter.channel, (1, nothing))
    empty!(reporter.error)
    empty!(reporter.observation)
end)
@__(function Base.reset(reporter::v__Reporter_Performance)
    if isready(reporter.channel) == true
        take!(reporter.channel)
    end
    put!(reporter.channel, (1, nothing))
    empty!(reporter.absolute_performance)
    empty!(reporter.observation)
end)
@__(function Base.reset(reporter::v__Reporter_Composition)
    for reporter in reporter.reporters
        reset(reporter)
    end
end)