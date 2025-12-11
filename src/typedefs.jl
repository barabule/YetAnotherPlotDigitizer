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


struct CubicBezierCurve{PT<:Point2{<:Real}} 
    points::Vector{PT} #ordering: CP handle handle CP handle handle etc
    is_smooth::Vector{Bool}
    
    function CubicBezierCurve(pts::Vector, is_smooth::Vector{Bool})
        npts = length(pts)  
        num_CP = length(is_smooth)
        @assert npts>=4 && mod(npts-1, 3)==0
        @assert num_CP >= 2 && num_CP == div(npts-1, 3) + 1
        PT = eltype(pts)
        return new{PT}(pts, is_smooth)
    end
end


function CubicBezierCurve(pts::Vector{PT}) where PT
    npts = length(pts)
    #4-7-10-13-17 etc are valid lengths
    nsegs = div(npts-1, 3)
    nsegs >= 1 || return nothing
    is_smooth = fill(true, nsegs+1)
    is_smooth[1] = false
    is_smooth[end] = false
    return CubicBezierCurve(pts, is_smooth)
end


function number_of_segments(C::CubicBezierCurve)
    
    # 4 -> 1s; 7->2; 10-> 3 etc
    return number_of_cubic_segments(C.points)
end

function number_of_cubic_segments(pts::Vector{PT}) where PT
    N = length(pts)
    div(N-1, 3)
end

function add_segment!(C::CubicBezierCurve,  
                        segment_id::Integer)

    @assert segment_id in 1:number_of_segments(C)
    id_h1 = (segment_id-1) * 3 + 2 #index of the previous handle data
    #prev and next handles
    H1, H2 = C.points[id_h1], C.points[id_h1 + 1]
    
    # L12 = norm(H2 - H1)
    # dir = (H2 - H1) / L12
    CP = 0.5 * H1 + 0.5 * H2
    Hbefore = 0.75 * H1 + 0.25 * H2
    Hafter = 0.25 * H1 + 0.75 * H2

   
    points = C.points
    add_to_middle!(points, id_h1, (Hbefore, CP, Hafter))
    is_smooth = C.is_smooth
    add_to_middle!(is_smooth, segment_id, (true))
    # @info "segid", segment_id
    # @info "N cp", number_of_segments(C)+1, "L is_sm", length(C.is_smooth)
    return nothing
end


function remove_control_point!(C::CubicBezierCurve, cpid::Integer)
    length(C.points) <=4 && return nothing
    num_cp = number_of_segments(C) + 1
    ptid = 3*(cpid-1)+1 #id of CP in points vector
    id_start = cpid == 1 ? 1 : ptid-1
    id_end = cpid == num_cp ? ptid : ptid + 1

    points = C.points
    deleteat!(points, id_start:id_end)
    is_smooth = C.is_smooth
    deleteat!(is_smooth, cpid)
    return nothing
end


function is_control_point(id::Integer)
    return mod(id,3)==1
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


function move!(C::CubicBezierCurve, id::Integer, position)

    NCP = length(C.points)
    @assert id in 1:NCP "Id ($id) must be within 1:$NCP"

    if is_control_point(id)
        # @info "CP move", id
        move_CP!(C, id, position)
    else
        i_CP, i_handle = get_attached_cp_and_handle(C, id)
        move_handle!(C, (id, i_CP, i_handle), position)
    end
    
    return nothing
end


function move_CP!(C::CubicBezierCurve, id, position) #move CP and attached handles
    
    PT = C.points[id]
    movedir = position - PT
    
    C.points[id] = position
    # @info "id", id, "num_pts", length(C.points)
    if id>1 #move preceding handle if not the 1st point
        H1 = C.points[id-1] + movedir
        C.points[id-1] = H1
        # @info "moved pre"
    end
    if id<length(C.points) #move succeding handle if not the last point
        H2 = C.points[id+1] + movedir
        C.points[id+1] = H2
        # @info "moved post"
    end
    return nothing
end


function move_handle!(C::CubicBezierCurve, ids, position)
    (id_this_handle, id_CP, id_other_handle) = ids
    
    
    C.points[id_this_handle] = position
    
    #check if associated control point is smooth
    cp_id = div(id_CP-1, 3) + 1
    !C.is_smooth[cp_id] && return nothing#only move this handle  
    
    isnothing(id_other_handle) && return nothing # 1st or last CP    
    
    #if smooth, preserve the length of the other handle and make it parallel to this handle, leave the CP alone
    handle_length_other = norm(C.points[id_CP] - C.points[id_other_handle])
    handle_dir = normalize(C.points[id_this_handle] - C.points[id_CP])

    C.points[id_other_handle] = C.points[id_CP] - handle_dir * handle_length_other

    return nothing
end


function piecewise_cubic_bezier(C::CubicBezierCurve; 
                                N_segments = 50,
                                )
    
    piecewise_cubic_bezier(C.points; N_segments)
end


function sample_cubic_bezier_curve(C::CubicBezierCurve; samples = 100, lut_samples = 20)
    return sample_cubic_bezier_curve(C.points; samples, lut_samples)
end

# util

function find_closest_control_point_to_position(C::CubicBezierCurve, position)

    d_closest = Inf
    i_closest = -1
    points = C.points
    ids_cp = filter(i-> is_control_point(i), 1:length(points))

    for (i, id_cp) in enumerate(ids_cp)
        d = norm(points[id_cp] - position)
        if d < d_closest
            i_closest = i
            d_closest = d
        end
    end
    return i_closest #index of cp in C.is_smooth
end


function toggle_smoothness(C::CubicBezierCurve, cp_id)
    
    @assert cp_id in eachindex(C.is_smooth)
    (cp_id == 1 || cp_id == lastindex(C.is_smooth)) && return nothing #don't modify 1st and last - always sharp
    C.is_smooth[cp_id] = !C.is_smooth[cp_id]
    if C.is_smooth[cp_id] #reset tangency if smooth again
        cp_pt_id = 3(cp_id-1) + 1
        CP = C.points[cp_pt_id]

        h1_id, h2_id = cp_pt_id - 1, cp_pt_id + 1
        H11, H1 = C.points[h1_id-1], C.points[h1_id]
        H2, H22 = C.points[h2_id], C.points[h2_id+1]
        new_dir = normalize(H22 - H11)
        l1, l2 = norm(CP - H1), norm(CP - H2)
        
        C.points[h1_id] = CP - new_dir * l1
        C.points[h2_id] = CP + new_dir * l2
    end
    return nothing
end

"""
    find_closest_point_to_position(C::CubicBezierCurve, position; thresh = 20, area= :square)

Returns the index of the closest point of CubicBezierCurve C to position.
thresh is the detectability threshold, points have to be closer than that to be detected. 
"""
function find_closest_point_to_position(C::CubicBezierCurve, position; thresh = 20, area= :square)
    d_closest = Inf
    i_closest = -1
    points = C.points
    
    p = area == :square ? Inf : 2
    for i in eachindex(points)
        d = norm(points[i] - position, p)
        if d < d_closest
            i_closest = i
            d_closest = d
        end
    end
    d_closest > thresh && return -1
    return i_closest 
end


"""
    find_closest_segment(C::CubicBezierCurve, position)

Return the index of the closest segment of curve C to position.
"""
function find_closest_segment(C::CubicBezierCurve, position)
    cp_id = find_closest_control_point_to_position(C, position)
    #check which side of the cp to return
    
    cp_id == 1 && return 1
    nsegs = number_of_segments(C)
    cp_id > nsegs && return nsegs #last CP

    #check which CP is closer
    seg_before = cp_id-1
    pt_id_CP_before = (seg_before-1) * 3 + 1
    CP_bef = C.points[pt_id_CP_before]
    d_bef = norm(CP_bef - position)
    
    seg_after  = cp_id
    pt_id_CP_after = (seg_after -1) * 3 + 1
    CP_after = C.points[pt_id_CP_after]
    d_aft = norm(CP_after - position)

    return d_bef<d_aft ? seg_before : seg_after
end


"""
    closest_projected_segment(C::CubicBezierCurve, position)

Finds the closest segment of C to position by projecting position on the linesegments made by consecutive controlpoints.
The segment with the smallest projected distance wins, with preference to segments where the projection is inside the segment.
"""
function find_closest_projected_segment(C::CubicBezierCurve, position)

    nseg = number_of_segments(C)
    dmin = Inf
    iseg = -1
    dmaybe = Inf # in case the projected point lands outside the line segment
    imaybe = -1 #
    for i in 1:nseg
        seg_start = 3 * (i-1)+1 #1, 4, 7
        seg_end = seg_start + 3 #4, 7, 10

        C_start = C.points[seg_start]
        C_end = C.points[seg_end]

        line_proj = closest_point_to_line_segment(C_start, C_end, position)
        dproj = line_proj.distance
        dproj > dmin && continue
        
        tproj = line_proj.parameter
        if 0 <= tproj <= 1
            dmin = dproj
            iseg = i
            continue
        end
        # tproj is outside the Cstart - Cend line
        if dproj < dmaybe #we get next best thing
            dmaybe = dproj
            imaybe = i 
        end
    end
    iseg = iseg == -1 ? imaybe : iseg #no projection within segment so pick the closest alternative
    return iseg
end