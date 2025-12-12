struct CurveData{T}
    name::String
    points::Vector{SVector{2,T}}
    color::Color
    curve_type::Symbol
    is_smooth::Vector{Boool}
end


function add(CD::CurveData, pos)
    pts = CD.points
    ct = CD.curve_type
    if ct == :bezier
        C = CubicBezierCurve(pts, CD.is_smooth)
        segment_id = find_closest_projected_segment(C, pos)
        add_segment!(C, segment_id)
        return CurveData(
                    CD.name, 
                    C.points, 
                    CD.color, 
                    ct, 
                    C.is_smooth,
        )
    else
        add_point!(pts, pos)
        return CurveData(
                    CD.name, 
                    pts, 
                    CD.color, 
                    ct, 
                    CD.is_smooth,
        )
    end
    nothing
end


function rem(CD::CurveData, pos)
    pts = CD.points
    ct = CD.curve_type
    if ct == :bezier
        C = CubicBezierCurve(pts, CD.is_smooth)
        cpid = find_closest_control_point_to_position(C, pos)
        remove_control_point!(C, cpid)
        return CurveData(
                CD.name,
                C.points,
                CD.color,
                ct,
                CD.is_smooth
        )
    else
        min_pts = minimum_points(ct)
        remove_point!(pts, pos; min_pts)
        return CurveData(
                CD.name, 
                pts, 
                CD.color, 
                ct, 
                CD.is_smooth,
        )
    end
    nothing
end


function move(CD::CurveData, idx, pos)
    pts = CD.points
    ct = CD.curve_type
    if ct == :bezier
        C = CubicBezierCurve(pts, CD.is_smooth)
        move!(C, idx, pos)
        return CurveData(
            CD.name,
            C.points,
            CD.color,
            ct,
            CD.is_smooth
        )
    else
        move_itp!(pts, dragged_index, new_data_pos)
        return CurveData(
            CD.name,
            pts,
            CD.color,
            ct,
            CD.is_smooth
        )
    end
    nothing
end


function update(CD::CurveData; 
                name = nothing,
                color = nothing,)


    pts = CD.points
    
    is_smooth = CD.is_smooth

    
    name =isnothing(name) ? CD.name : name
    @assert typeof(name) == typeof(CD.name)

    color = isnothing(color) ? CD.color : color
    @assert typeof(color) == typeof(CD.color)

    return CurveData(
        name,
        pts,
        color,
        CD.curve_type,
        is_smooth,
    )
end


function change_curve_type(CD::CurveData, ct::Symbol)
    @assert in(ct, InterpolationTypeList) "$ct not found in curve type list"

    ct_prev = CD.curve_type

    ct == ct_prev && return CD #no effect

    pts = CD.points
    N = length(pts)
    
    if !has_valid_number_of_points(N, ct)#check if valid amound of points for the new ct
        make_valid!(pts, ct)
    end

    if ct == :bezier
        is_smooth = fill(false, div(length(pts)-1, 3))
    else
        is_smooth = CD.is_smooth
    end

    return CurveData(
        CD.name,
        pts,
        CD.color,
        ct,
        is_smooth
    )
end


function eval_curve(CD::CurveData; N = 1000)# for plotting

    pts = CD.points
    ct = CD.curve_type

    if ct == :bezier
        nseg = number_of_cubic_segments(pts)
        N_segments = round(Int, N / nseg)
        return piecewise_cubic_bezier(pts; N_segments)
    else
        itp = make_new_interpolator(pts, ct)
        return eval_pts(itp; N)
    end
    nothing
end


function sample_curve(CD::CurveData; 
                    samples = 1000, 
                    arclen = false, 
                    lut_samples = 100) #for exporting

    pts = CD.points
    ct = CD.curve_type

    if ct == :bezier
        if arclen
            return sample_cubic_bezier_curve(pts; samples, lut_samples)
        else
            return sample_cubic_bezier_curve_horizontally(pts; samples, lut_samples)
        end
    end
    #not bezier
    interpolator = make_new_interpolator(pts, ct)
    if arclen
        return eval_pts_arclen(interpolator; N)
    else
        return eval_pts(interpolator; N)
    end
    nothing
end


function toggle_sharp(CD::CurveData, pos)
    ct = CD.curve_type
    ct == :bezier || return CD

    pts = CD.points
    C = CubicBezierCurve(pts, CD.is_smooth)
    cp_id = find_closest_control_point_to_position(C, pos)
    toggle_smoothness(C, cp_id)

    return CurveData(
        CD.name,
        C.points,
        CD.color,
        ct,
        C.is_smooth
    )
end