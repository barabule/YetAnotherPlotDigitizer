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
abstract type MainControlPoint <: ControlPointType end

struct SharpControlPoint<:MainControlPoint
    point::Point2f 
end

struct SmoothControlPoint<:MainControlPoint
    point::Point2f
end

struct HandlePoint<:ControlPointType #tangent handle pt
    point::Point2f #
end


struct CubicBezierCurve
    points::Vector{ControlPointType} #ordering: CP handle handle CP handle handle etc
end

function CubicBezierCurve(pts::Vector{PT}) where PT
    npts = length(pts)
    #4-7-10-13-17 etc are valid lengths
    nsegs = div(npts-1, 3)
    ncurvepts = 3nsegs + 1 # <= npts
    
    CPTS = [SharpControlPoint(pts[1])] #first and last cpts are SharpControlPoint
    for s in 1:nsegs
        idx = 1 + 3(s-1)
        last_CP = s==nsegs ? SharpControlPoint(Point2f(pts[idx+3])) : SmoothControlPoint(Point2f(pts[idx+3]))
        push!(CPTS, HandlePoint(Point2f(pts[idx+1])), HandlePoint(Point2f(pts[idx+2])), last_CP)
    end
    return CubicBezierCurve(CPTS)
end

function number_of_segments(C::CubicBezierCurve)
    N = length(C.points)
    # 4 -> 1s; 7->2; 10-> 3 etc
    return div(N-1, 3)
end


function add_segment!(C::CubicBezierCurve,  
                        segment_id::Integer,
                        CP::Union{MainControlPoint, Nothing}= nothing,
                        handle_first::Union{HandlePoint, Nothing} = nothing,
                        handle_second::Union{HandlePoint, Nothing} = nothing)
    @assert segment_id in 1:number_of_segments(C)
    id_h1 = (segment_id-1) * 3 + 2 #index of the previous handle point
    #prev and next handles
    H1, H2 = C.points[id_h1].point, C.points[id_h1 + 1].point
    
    L12 = norm(H2 - H1)
    dir = (H2 - H1) / L12
    CP = isnothing(CP) ? SmoothControlPoint(0.5 * H1 + 0.5 * H2) : CP #by default add a smooth pc
    Hbefore = isnothing(handle_first) ? HandlePoint(CP.point - L12/4 * dir) : handle_first
    Hafter = isnothing(handle_second) ? HandlePoint(CP.point + L12/4 * dir) : handle_second

   
    points = C.points
    add_to_middle!(points, idh1+1, (Hbefore, CP, Hafter))
    return nothing
end


function remove_segment!(C::CubicBezierCurve, id::Integer)
    length(C.points)<=4 && return C
    NSegs = number_of_segments(C)
    @assert id in 1:NSegs

    id_start = id==1 ? 1 : 3*(id-1)+1 #delete also the 1st cp if first  segment
    id_end = id==NSegs ? id_start+4 : id_start+3 #delete also the last cp if last segment

    pts = C.points
    deleteat!(pts, id_start:id_end)
    return nothing
end

function is_control_point(id::Integer)
    return mod(i,3)==1
end

function get_attached_cp_and_handle(C::CubicBezierCurve, id::Integer)
    if is_control_point(id-1)
        id_CP = id-1
        id_handle = id-1 ==1 ? nothing : id-2
    else
        id_CP = id+1
        id_handle = id+1 == length(C.points) ? nothing : id + 2
    end
    return (id_CP, id_handle)
end


function move!(C::CubicBezierCurve, id::Integer, position::Point2f)

    NCP = length(C.points)
    @assert id in 1:NCP "Id ($id) must be within 1:$NCP"

    if is_control_point(id)
        move_CP!(C, id, position)
    else
        i_CP, i_handle = get_attached_cp_and_handle(C, id)
        move_handle!(C, (id, i_CP, i_handle), position, C.points[id])
    end
    
    return nothing
end

function move_CP!(C::CubicBezierCurve, id, position) #move CP and attached handles
    
    CP = C.points[id]
    movedir = position - CP.point
    new_CP = typeof(CP)(position)
    C.points[id] = new_CP
    if id!=1
        H1 = HandlePoint(C.points[id-1].point + movedir)
        C.points[id-1] = H1
    elseif id != length(C.points)
        H2 = HandlePoint(C.point[id+1].point + movedir)
        C.point[id+1] = H2
    end
    return nothing
end


function move_handle!(C::CubicBezierCurve, ids, position, ::HandlePoint)
    (id_this_handle, id_CP, id_other_handle) = ids
    
    
    C.points[id_this_handle] = HandlePoint(position)
    
    isa(C.points[id_CP], SharpControlPoint) && return nothing#only move this handle  
    
    isnothing(id_other_handle) && return nothing # 1st or last CP    
    
    #if smooth, preserve the length of the other handle and make it parallel to this handle, leave the CP alone
    handle_length_other = norm(C.points[id_CP].point - C.points[id_other_handle].point)
    handle_dir = normalize(C.points[id_this_handle].point - C.points[id_CP].point)

    C.points[id_other_handle] = HandlePoint( C.points[id_CP].point - handle_dir * handle_length_other)


    return nothing
end


#eval wrappers
function piecewise_cubic_bezier(C::CubicBezierCurve; 
                                N_segments = 50,
                                )
    PTS = [CP.point for CP in C.points]
    piecewise_cubic_bezier(PTS; N_segments)
end


function sample_cubic_bezier_curve(C::CubicBezierCurve; samples = 100, lut_samples = 20)
    PTS = [CP.point for CP in C.points]
    return sample_cubic_bezier_curve(PTS; samples, lut_samples)
end

# util

function find_closest_control_point_to_position(C::CubicBezierCurve, position)

    d_closest = Inf
    i_closest = -1
    points = C.points
    ids_cp = filter(i-> is_control_point(i), 1:length(points))

    for id_cp in ids_cp
        d = norm(points[id_cp].point - position)
        if d < d_closest
            i_closest = id_cp
            d_closest = d
        end
    end
    return i_closest #index of control point in C.points
end


function toggle_smoothness(C::CubicBezierCurve, id)
    @assert id in 1:length(C.points)

    (id == 1 || id==length(C.points)) && return nothing

    !is_control_point(id) && return nothing

    CP = C.points[id]
    new_CP = isa(CP, SharpControlPoint) ? SmoothControlPoint(CP.point) : SharpControlPoint(CP.point)
    C.points[id] = new_CP

    return nothing
end