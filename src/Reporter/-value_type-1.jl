struct v__Reporter_Image_Data{channel_type,type}
    #input::Ref{input_type} #input data
    #output::Ref{NamedTuple{(:reference, :predicted), Tuple{output_type, output_type}}} #output data
    channel::channel_type #channel for communication with the master
    observations_current::Ref{type} #how many observations to wait before sending a report
    observations_limit::Ref{type} #how many observations to wait before sending a report
    function v__Reporter_Image_Data(input_type, output_type, observations_limit, update_handler)
        channel = RemoteChannel(
            () -> Channel{
                Tuple{
                    Int64,
                    #NamedTuple{(:input, :output), Tuple{input_type, NamedTuple{(:reference, :predicted), Tuple{output_type, output_type}}}}
                    Any
                }
            }(1)
        )
        errormonitor(Threads.@async begin
            while true
                message, keywords = take!(channel)
                if message == 0
                    println("STOP v__Reporter_Image_Data")
                    break
                else
                    update_handler(; keywords...) #call the update handler with the keywords
                end
            end
        end)
        type = typeof(observations_limit)
        return new{
            typeof(channel),
            type
        }(channel, Ref{type}(0), Ref{type}(observations_limit))
    end
end
struct v__Reporter_Error{channel_type,type}
    error::Array{Float64,1}
    observation::Array{type,1}
    channel::channel_type #channel for communication with the master
    observation_total::Ref{type} #how many observations to wait before sending a report
    observations_current::Ref{type} #how many observations to wait before sending a report
    observations_limit::Ref{type} #how many observations to wait before sending a report
    function v__Reporter_Error(observations_limit, update_handler)
        error_type = Array{Float64,1}
        type = typeof(observations_limit)
        observation_type = Array{type,1}
        channel = RemoteChannel(
            () -> Channel{
                Tuple{
                    Int64,
                    #NamedTuple{(:error, :observation), Tuple{error_type, observation_type}}
                    Any
                }
            }(1)
        )
        errormonitor(Threads.@async begin
            error = error_type()
            observation = observation_type()
            while true
                message, keywords = take!(channel)
                if message == 0
                    println("STOP v__Reporter_Error")
                    break
                elseif message == 1
                    empty!(error)
                    empty!(observation)
                else
                    error = cat(error, keywords.error; dims=1)
                    observation = cat(observation, keywords.observation; dims=1)
                    update_handler(; error, observation)
                end
            end
        end)
        return new{
            typeof(channel),
            type
        }(
            error_type(),
            observation_type(),
            channel,
            Ref{type}(0),
            Ref{type}(0),
            Ref{type}(observations_limit)
        )
    end
end
struct v__Reporter_Performance{channel_type,type}
    absolute_performance::Array{Float64,1}
    observation::Array{type,1}
    channel::channel_type #channel for communication with the master
    observation_total::Ref{type} #how many observations to wait before sending a report
    observations_current::Ref{type} #how many observations to wait before sending a report
    observations_limit::Ref{type} #how many observations to wait before sending a report
    function v__Reporter_Performance(observations_limit, update_handler)
        performance_type = Array{Float64,1}
        type = typeof(observations_limit)
        observation_type = Array{type,1}
        channel = RemoteChannel(
            () -> Channel{
                Tuple{
                    Int64,
                    #NamedTuple{(:performance, :observation), Tuple{performance_type, observation_type}}
                    Any
                }
            }(1)
        )
        errormonitor(Threads.@async begin
            absolute_performance = performance_type()
            observation = observation_type()
            while true
                message, keywords = take!(channel)
                if message == 0
                    println("STOP v__Reporter_Performance")
                    break
                elseif message == 1
                    empty!(absolute_performance)
                    empty!(observation)
                else
                    absolute_performance = cat(absolute_performance, keywords.absolute_performance; dims=1)
                    observation = cat(observation, keywords.observation; dims=1)
                    update_handler(; absolute_performance, observation)
                end
            end
        end)
        return new{
            typeof(channel),
            type
        }(
            performance_type(),
            observation_type(),
            channel,
            Ref{type}(0),
            Ref{type}(0),
            Ref{type}(observations_limit)
        )
    end
end
struct v__Reporter_Composition{reporters_type}
    reporters::reporters_type
    function v__Reporter_Composition(reporters)
        return new{typeof(reporters)}(reporters)
    end
end