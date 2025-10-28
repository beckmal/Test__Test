function crossentropy_error(Model, Parameters, State, input_model_array, output_model_array)
    predicted_output_model_array, State = Model(input_model_array, Parameters, State)
    predicted_output_model_array = softmax(predicted_output_model_array, dims=3)
    return mean(sum(- output_model_array .* log.(predicted_output_model_array .+ eps(eltype(predicted_output_model_array))), dims=3)), State
end
function quadratic_error(Model, Parameters, State, input_model_array, output_model_array)
    predicted_output_model_array, State = Model(input_model_array, Parameters, State)
    return sum((predicted_output_model_array - output_model_array) .^ 2), State
end
function weighted_crossentropy_error(Model, Parameters, State, weight_1, weight_2, weight_3, input_model_array, output_model_array)
    predicted_output_model_array, State = Model(input_model_array, Parameters, State)
    predicted_output_model_array = softmax(predicted_output_model_array, dims=3)
    error_array = - output_model_array .* log.(predicted_output_model_array .+ eps(eltype(predicted_output_model_array)))

    return mean(sum(cat(error_array[:, :, 1:1, :] * weight_1,
                         error_array[:, :, 2:2, :] * weight_2,
                         error_array[:, :, 3:3, :] * weight_3,
                         dims=Val(3)
                     ),
                     dims=3
                )
    ), State
end
function weighted_crossentropy_error(Model, Parameters, State, weight_1, weight_2, weight_3, weight_4, input_model_array, output_model_array)
    predicted_output_model_array, State = Model(input_model_array, Parameters, State)
    predicted_output_model_array = softmax(predicted_output_model_array, dims=3)
    error_array = - output_model_array .* log.(predicted_output_model_array .+ eps(eltype(predicted_output_model_array)))

    return mean(sum(cat(error_array[:, :, 1:1, :] * weight_1,
                         error_array[:, :, 2:2, :] * weight_2,
                         error_array[:, :, 3:3, :] * weight_3,
                         error_array[:, :, 4:4, :] * weight_4,
                         dims=Val(3)
                     ),
                     dims=3
                )
    ), State
end
@__(function weighted_crossentropy_error(Model, Parameters, State, input_model_array, output_model_array; weight_1, weight_2, weight_3, weight_4, weight_5, keywords...)
    predicted_output_model_array, State = Model(input_model_array, Parameters, State)
    predicted_output_model_array = softmax(predicted_output_model_array, dims=3)
    error_array = - output_model_array .* log.(predicted_output_model_array .+ eps(eltype(predicted_output_model_array)))

    return mean(sum(cat(error_array[:, :, 1:1, :] * weight_1,
                         error_array[:, :, 2:2, :] * weight_2,
                         error_array[:, :, 3:3, :] * weight_3,
                         error_array[:, :, 4:4, :] * weight_4,
                         error_array[:, :, 5:5, :] * weight_5,
                         dims=Val(3)
                     ),
                     dims=3
                )
    ), State
end; Transform=false, Transform_Keyword=true)
@__(function weighted_crossentropy_error(Model, Parameters, State, input_model_array, output_model_array; weight_1, weight_2, keywords...)
    predicted_output_model_array, State = Model(input_model_array, Parameters, State)
    predicted_output_model_array = softmax(predicted_output_model_array, dims=3)
    error_array = - output_model_array .* log.(predicted_output_model_array .+ eps(eltype(predicted_output_model_array)))

    return mean(sum(cat(error_array[:, :, 1:1, :] * weight_1,
                         error_array[:, :, 2:2, :] * weight_2,
                         dims=Val(3)
                     ),
                     dims=3
                )
    ), State
end; Transform=false, Transform_Keyword=true)
@__(function weighted_crossentropy_error(Model, Parameters, State, input_model_array, output_model_array; weight_1, weight_2, weight_3, keywords...)
    predicted_output_model_array, State = Model(input_model_array, Parameters, State)
    predicted_output_model_array = softmax(predicted_output_model_array, dims=3)
    error_array = - output_model_array .* log.(predicted_output_model_array .+ eps(eltype(predicted_output_model_array)))

    return mean(sum(cat(error_array[:, :, 1:1, :] * weight_1,
                         error_array[:, :, 2:2, :] * weight_2,
                         error_array[:, :, 3:3, :] * weight_3,
                         dims=Val(3)
                     ),
                     dims=3
                )
    ), State
end; Transform=false, Transform_Keyword=true)
function weighted_focal_crossentropy_error(Model, Parameters, State, weight_1, weight_2, weight_3, input_model_array, output_model_array, gamma=2.0)
    predicted_output_model_array, State = Model(input_model_array, Parameters, State)
    predicted_output_model_array = softmax(predicted_output_model_array, dims=3)
    error_array = - output_model_array .* log.(predicted_output_model_array .+ eps(eltype(predicted_output_model_array))) .* (1 .- predicted_output_model_array) .^ gamma

    return mean(sum(cat(error_array[:, :, 1:1, :] * weight_1,
                        error_array[:, :, 2:2, :] * weight_2,
                        error_array[:, :, 3:3, :] * weight_3,
                        dims=Val(3)
                    ),
                    dims=3
                )
    ), State
end

function confusion_elements(Model, Parameters, State, input_model_array, output_model_array)
    predicted_output_model_array, State = Model(input_model_array, Parameters, State)
    predicted_output_model_array = softmax(predicted_output_model_array, dims=3)

    predicted_output_model_array = predicted_output_model_array .> 0.5
    output_model_array = output_model_array .> 0.5

    #=
    true_positive = sum(predicted_output_model_array .* output_model_array, dims=3)
    true_negative = sum((1 .- predicted_output_model_array) .* (1 .- output_model_array), dims=3)
    false_positive = sum(predicted_output_model_array .* (1 .- output_model_array), dims=3)
    false_negative = sum((1 .- predicted_output_model_array) .* output_model_array, dims=3)
    =#
    true_positive = predicted_output_model_array .* output_model_array
    true_negative = (1 .- predicted_output_model_array) .* (1 .- output_model_array)
    false_positive = predicted_output_model_array .* (1 .- output_model_array)
    false_negative = (1 .- predicted_output_model_array) .* output_model_array
    return (;
        true_positive=true_positive,
        true_negative=true_negative,
        false_positive=false_positive,
        false_negative=false_negative
    ), State
end
function intersection_over_union_loss(Model, Parameters, State, input_model_array, output_model_array)

    _confusion_elements, State = confusion_elements(Model, Parameters, State, input_model_array, output_model_array)
    #compute intersection over union
    #if _confusion_elements.true_positive == 0
    #    return 1.0, State #return loss of 1 if there is no intersection
    #else
        intersection = _confusion_elements.true_positive
        
        union = _confusion_elements.true_positive + _confusion_elements.false_positive + _confusion_elements.false_negative
        iou = intersection ./ union
        #iou[iou .== NaN] .= 0.0
        #compute loss
        loss = 1 .- iou
        #return loss
        #return mean(loss), State
        loss_1 = mean(loss[:, :, 1, :])
        loss_2 = mean(loss[:, :, 2, :])

        if isnan(loss_1)
            loss_1 = 1.0
        end
        if isnan(loss_2)
            loss_2 = 1.0
        end
        return loss_1, loss_2, State
    #end
end
export crossentropy_error, quadratic_error, weighted_crossentropy_error, weighted_focal_crossentropy_error, intersection_over_union_loss