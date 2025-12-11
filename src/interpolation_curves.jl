
ITP = DataInterpolations.AbstractInterpolation
#allowable interpolation types
const InterpolationTypeList = (
    :bezier,
    :linear,
    :akima,
    :constant,
    :smoothedconstant,
    :quadraticspline,
    :cubicspline,
    :pchip,
    # :bspline,
)

const InterpolationTypeNames = (
    "Bezier",
    "Linear",
    "Akima",
    "Constant",
    "SmoothedConstant",
    "QuadraticSpline",
    "CubicSpline",
    "PCHIP",
    # "BSpline",
)

ITP_Dict = Dict{Symbol, Integer}(InterpolationTypeList[i] => i  for i in eachindex(InterpolationTypeList))

function make_new_interpolator(pts::Vector{PT}, interpolatortype::Symbol) where PT
    if interpolatortype == :bezier
        return nothing 
    end
    u, t = last.(pts), first.(pts)
    if !in(interpolatortype, InterpolationTypeList)
        error("Interpolation type not found: $(interpolatortype)")
    end
    @assert issorted(t) "t must be sorted!"

    if interpolatortype == :linear
        itp = LinearInterpolation
    end
    
    if interpolatortype == :akima
        itp = AkimaInterpolation
    end
    
    if interpolatortype == :constant
        itp = ConstantInterpolation
    end
    
    if interpolatortype == :smoothedconstant
        itp = SmoothedConstantInterpolation
    end
    
    if interpolatortype == :cubicspline
        itp = CubicSpline
    end
    
    if interpolatortype == :pchip
        itp = PCHIPInterpolation
    end
    
    if interpolatortype == :quadraticspline
        itp = QuadraticSpline
    end

    if interpolatortype == :bspline
        return BSplineInterpolation(u, t, 3, :ArcLen, :Uniform)
    end
    return itp(u, t)
end


function find_closest(pts::Vector{PT}, pt) where PT
     
    dmin, idx = Inf, -1
    for i in eachindex(pts)
        dist = norm(pt - pts[i])
        if dist < dmin
            dmin = dist
            idx = i
        end
    end
    @assert idx != -1
    return idx
end


function move_itp!(pts::Vector{PT}, idx, position) where PT
    #check if moving the point would produce an unsorted array 
    t = position[1]
    invalid = (idx !=1 && pts[idx-1][1]>=t) || (idx !=lastindex(pts) && pts[idx+1][1]<= t)
    if !invalid
        pts[idx] = PT(position)
    end
    return nothing
end


function eval_pts(itp::ITP; N= 1000)
    t = itp.t
    ti = LinRange(first(t), last(t), N)
    ui = itp(ti)
    return [SVector{2}(ti[i], ui[i]) for i in eachindex(ti)]
end


function eval_pts_arclen(itp::ITP; N = 1000, LUT_size = 100)
    t = itp.t
    u = itp.u

    tlut = LinRange(first(t), last(t), LUT_size)
    LUT = cumsum(itp(tlut)) #arclen lut
    Ltotal = last(LUT)

    Li = LinRange(0, Ltotal, N)
    
    P1 = SVector{2}(first(tlut), first(LUT))
    PT = typeof(P1)
    out = [P1]
    previndex = 1
    for i in 2:N-1
        Ltarget = Li[i]
        for j in previndex+1:lastindex(LUT)
            if LUT[j] > Ltarget
                previndex = j-1
                break
            end
        end
        s = (Ltarget - LUT[previndex]) / (LUT[previndex + 1] - LUT[previndex])
        s1, s2 = tlut[previndex], tlut[previndex+1]
        tout = s1 * (1- s) + s2 * s
        tout = clamp(tout, first(t), last(t))#prevent going out of bounds
        push!(out, PT(tout, itp(tout)))

    end
   
    push!(out, PT(last(t),last(u)))
    @assert length(out) == N "ups"
    return out
end




function add_point!(pts::Vector{PT}, pos) where PT
    idx = -1
    for (i, point) in enumerate(pts)
        if point[1] > pos[1]
            idx = i
            break
        end
    end
    if idx == -1
        push!(pts, PT(pos...))
    else
        splice!(pts, idx:idx-1, [PT(pos...)]) 
    end
    nothing
end

function minimum_points(itp_type::Symbol)
    if in(itp_type, (:akima, :cubicspline, :quadratic, :pchip) )
        return 3
    elseif in(itp_type, (:bspline, :bezier) )
        return 4 #degree 3
    else
        return 2
    end
end


function remove_point!(pts::Vector{PT}, pos; min_pts = 2) where PT
    length(pts)<=min_pts && return nothing
    idx = find_closest(pts, pos)
    deleteat!(pts, idx)
    nothing
end

function has_valid_number_of_points(pts::Vector{PT}, itp::Symbol) where PT
    N = length(pts)
    has_valid_number_of_points(N, itp)
end

function has_valid_number_of_points(N::Integer, itp::Symbol)
    ret = N >= minimum_points(itp)
    if itp == :bezier
        ret = ret && (mod(N-1, 3) == 0) #4, 7, 10, 13 etc
        
    end

    ret
end


function reset_curve!(pts::Vector{PT}, itp::Symbol) where PT
    N = length(pts)
    
    Nmin = minimum_points(itp)
    N == Nmin && return nothing #no point

    P1, PN = pts[1], pts[N]

    if N > Nmin && itp == :bezier # delete some points in the 'middle' to get a valid cubic bezier
        next_N = 3 * (div(N-1,3)) + 1 #next valid no of control points
        @assert next_N <= N
        #we have at least 4 points, and want to preserve the starting and ending tangency
        m = N - next_N
        idx = 3:3+m-1
        deleteat!(pts, idx)

    elseif N<Nmin #return the minimum viable amount of points in a line from the 1st to the last point in pts
        m = Nmin - N
        push!(pts, fill(zero(PT), m)...)
        dt = 1/(Nmin-1)
        for i in 1:Nmin
            t = (i-1) * dt
            pts[i] = P1 * (1-t) + PN * t
        end
    end
    
    return nothing
end

function make_valid!(pts::Vector{PT}, itp::Symbol) where PT
    itp == :bezier && return nothing

    ordering = sign(last(pts)[1]- first(pts)[1]) # 1 for increasing, -1 for decreasing
    for i in eachindex(pts)
        i==firstindex(pts) && continue

        ti = pts[i][1]
        ti_before = pts[i-1][1]

        if sign(ti - ti_before) != ordering 
            dti = i==lastindex(pts) ? pts[i][1] - pts[i-1][1] : pts[i+1][1] - pts[i][1]
            
            pts[i] = PT(ti_before + ordering * dti*1e-3, pts[i][2]) #shift ti to be 'after ti_before'
        end
    end
    return nothing
end