using KomaMRICore, StatsBase

function piecewise_linear_interp(values::Vector{<:Real}, scale::Int=2)
    n = length(values)
    if n < 2
        return values
    end
    
    # Output length: original points + (scale-1) interpolated points between each pair
    out_len = (n - 1) * scale + 1
    result = zeros(Float32, out_len)
    
    for i in 1:(n-1)
        base_idx = (i - 1) * scale + 1
        v0 = values[i]
        v1 = values[i + 1]
        
        for j in 0:(scale-1)
            t = j / scale
            result[base_idx + j] = v0 + t * (v1 - v0)
        end
    end
    
    # Set the last point
    result[end] = values[end]
    
    return result
end

function upsample(obj::Phantom, factor::Int)
    Phantom{Float32}(
        name = string(factor) * " upsampled " * obj.name,
        x = repeat(obj.x, inner=factor) .+ repeat(collect(range(0f0, median(diff(obj.x)) * (factor - 1) / factor, length=factor)), outer = length(obj.x)),
        y = repeat(obj.y, inner=factor) .+ repeat(collect(range(0f0, median(diff(obj.y)) * (factor - 1) / factor, length=factor)), outer = length(obj.y)),
        z = repeat(obj.z, inner=factor) .+ repeat(collect(range(0f0, median(diff(obj.z)) * (factor - 1) / factor, length=factor)), outer = length(obj.z)),
        ρ = piecewise_linear_interp(obj.ρ, factor),
        T1 = piecewise_linear_interp(obj.T1, factor),
        T2 = piecewise_linear_interp(obj.T2, factor),
        T2s = piecewise_linear_interp(obj.T2s, factor),
        Δw = piecewise_linear_interp(obj.Δw, factor),
        Dλ1 = piecewise_linear_interp(obj.Dλ1, factor),
        Dλ2 = piecewise_linear_interp(obj.Dλ2, factor),
        Dθ = piecewise_linear_interp(obj.Dθ, factor),
        motion = upsample(obj.motion, factor)
    )
end

function upsample(obj::Motion, factor::Int)
    up_x = repeat(obj.action.dx, inner = [factor, 1])
    up_y = repeat(obj.action.dy, inner = [factor, 1])
    up_z = repeat(obj.action.dz, inner = [factor, 1])

    mret = Motion{Float32}(
        action=Path{Float32}(dx = up_x, dy = up_y, dz = up_z),
        time=obj.time,
        spins=obj.spins
    )
    return mret
end
