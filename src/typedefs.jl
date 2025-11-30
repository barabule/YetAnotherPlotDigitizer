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
    PT::Point2f #absolute
end

struct SmoothControlPoint<:ControlPointType
    PT::Point2f #absolute
end

struct HandlePoint<:ControlPointType #handle pt
        PT::Point2f #relative -> vector
end


struct CubicBezierSegment
    CP_first<:ControlPointType
    CP_second<:ControlPointType
    handle_first::HandlePoint
    handle_second::HandlePoint
end

struct CubicBezierCurve
    segments::Vector{CubicBezierSegment}
end


function add_control_point(C::CubicBezierCurve, 
                        CP::ControlPointType, 
                        id::Integer,
                        handle_first::Union{HandlePoint, Nothing} = nothing,
                        handle_second::Union{HandlePoint, Nothing} = nothing)
    #insert CP after control point id, cannot insert before 1...
    @assert id in eachindex(C.segments) #CP will be added after CP[id]

    segments = C.segments
    this_seg = segments[id]
    H1 = this_seg.CP_first + this_seg.handle_first #handle points
    H2 = this_seg.CP_second + this_seg.handle_second
    L12 = norm(H2 - H1)
    dir = (H2 - H1) / L12 # direction vector from H1 to H2
    h1 = isnothing(handle_first) ?  -dir * L12 / 4 : handle_first
    h2 = isnothing(handle_second) ?  dir * L12 / 4 : handle_second
    new_seg_before = CubicBezierSegment(this_seg.CP_first, CP, this_seg.handle_first, h1)
    new_seg_after = CubicBezierSegment(CP, this_seg.CP_second, h2, this_seg.handle_second)
    if length(segments) ==1
        new_segments = [new_seg_before, new_seg_after]
    elseif id>1 #at least 2 segment before
        new_segments = vcat(segments[1:id-1], new_seg_before, new_seg_after, segments[i+1:end])
    else #don't add the 1st portion
        new_segments =vcat(new_seg_before, new_seg_after, segments[2:end])
    end
    return CubicBezierCurve(new_segments)
end


function remove_control_point(C::CubicBezierCurve, id::Integer)
    NCP = number_of_control_points(C)
    @assert id in 1:NCP

    segments = C.segments
    length(segments)<2 && return C #don;t delete the last segment
    if id ==1 
        deleteat!(segments, 1)
        new_segments = segments
    elseif id==NCP
        deleteat!(segments, NCP-1)
        new_segments = segments
    else #we need to merge both segments sharing this CP
        seg_before = segments[id-1] # cp_id-1 - cp_id
        seg_after = segments[id] #cp_id - cp_id+1
        new_segment = CubicBezierSegment( seg_before.CP_first, 
                                        seg_after.CP_second,
                                        seg_before.handle_first,
                                        seg_after.handle_second)
        new_segments = vcat(segments[1:id-1], new_segment, segments[id+1:end])
    end
    Cnew = CubicBezierCurve(new_segmens)
    return Cnew

end

function segment_points(s::CubicBezierSegment)

    P1 = s.CP_first
    P4 = s.CP_second
    P2 = P1 + s.handle_first
    P3 = P4 + s.handle_second
    return (P1, P2, P3, P4)
end

function move_control_pt(C::CubicBezierCurve, id, new_position)
    NCP = number_of_control_points(C)
    @assert id in 1:NCP
    return move_control_pt(C, id, C.segments[id].CP_first)
end

function move_control_pt(C::CubicBezierCurve, id::Integer, CP::SmoothControlPoint, new_position::Point2f)
    new_CP = SmoothControlPoint(new_position)
    # Cp id is shared between segments id-1 and id, both handles must be updated
    segments = C.segments
    if id<2
        s1= segments[1]
        segments[1] = CubicBezierSegment(CP, s1.CP_second, s1.handle_first, s1.handle_second)
    elseif id==number_of_control_points(C)
        slast = segments[id]
        segments[id] = CubicBezierSegment(slast.CP_first, CP, slast.handle_first, slast.handle_second)
    else
        sbefore = segments[id-1]
        safter = segments[id]
        segments[id-1] = CubicBezierSegment(sbefore.CP_first, CP, sbefore.handle_first, safter.handle_second)
        segments[id] = CubicBezierSegment(CP, safter.CP_second, safter.handle_first, safter.handle_second)
    end
end

# function move_control_pt(C::)

function number_of_control_points(C::CubicBezierCurve)
    return length(C.segments) + 1
end