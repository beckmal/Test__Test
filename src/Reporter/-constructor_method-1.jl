@__(function c__Reporter(positionals...; keywords...)
    reporters = ()
    for positional in positionals
        #println(keys(positional))
        reporters = (reporters..., c__Reporter(;
            positional...,
            keywords...
        ))
    end
    return v__Reporter_Composition(reporters)
end)
@__(function c__Reporter(; input, output, observations_limit, update_handler)
    #println("CALL: c__Reporter(input, output, observations_limit, update_handler)")
    return v__Reporter_Image_Data(input, output, observations_limit, update_handler)
end)
@__(function c__Reporter(; error_metric, observations_limit, update_handler)
    #println("CALL: c__Reporter(error_metric, observations_limit, update_handler)")
    return v__Reporter_Error(observations_limit, update_handler)
end)
@__(function c__Reporter(; performance_metric, observations_limit, update_handler)
    #println("CALL: c__Reporter(performance_metric, observations_limit, update_handler)")
    return v__Reporter_Performance(observations_limit, update_handler)
end)
export c__Reporter