abstract type ScaleType end

struct LogScaleType<:ScaleType
end

struct LinearScaleType<:ScaleType
end

function ScaleType(s::Symbol)
    if s==:linear
        return LinearScaleType()
    elseif s == :log
        return LogScaleType()
    else
        error("s must be either :linear or :log")
    end
end