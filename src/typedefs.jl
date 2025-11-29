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


abstract type ControlPointType end

struct SharpControlPoint<:ControlPointType
    PT::Point2f
end

struct SmoothControlPoint<:ControlPointType
    PT::Point2f
end

struct HandlePoint<:ControlPointType
    PT::Point2f
end
