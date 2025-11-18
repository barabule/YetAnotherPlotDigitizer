module YetAnotherPlotDigitizer

using GLMakie
import GLMakie.GLFW
using LinearAlgebra 
using StaticArrays 
using Observables
using FileIO
using Colors


# include("bezier.jl")


export main

function main(;
        num_colors = 8,
        color_btn_height = 30,
        num_color_cols = 4,
        sidebar_width = 200,
        )

    #######GLOBALS###########################

    cmap = distinguishable_colors(num_colors, rand(RGB))

    current_color = Observable(first(cmap))

    is_colorgrid_visible = Observable(false)

    ref_img = Observable(nothing::Union{Nothing, Matrix})

    current_curve = Observable(Point2f[])
    
    #to be placed by user
    X1 = Point2f(0,0)
    X2 = Point2f(1,0)
    Y1 = Point2f(0.5, 0)
    Y2 = Point2f(0.5, 1)
    scale_rect = Observable([X1, X2, Y1, Y2])
    
    
    #######Layout#############################


    fig = Figure()

    img_ax = Axis(fig[1,1], aspect = DataAspect())

    color_grid = fig[1,2] = GridLayout(width = sidebar_width, tellheight = false)

    hidden_layout = GridLayout(bbox = (-200, -100, 0, 100))

    ####color menu#########
    
    menu_container = color_grid[1,1] = GridLayout()
    btn_color = Button(fig,
                        label = "Choose color",
                        height = color_btn_height,
                        )

    color_option_grid = GridLayout()
    color_option_grid.tellheight = false
    color_option_grid.tellwidth = false

    empty_layout = GridLayout()

    menu_container[1, 1] = hgrid!(btn_color, Box(fig, color = current_color))


    
    ########EVENTS###########################################
    
    on(is_colorgrid_visible) do val
        if val
            menu_container[2, 1] = color_option_grid
            hidden_layout[1,1] = empty_layout
        else
            menu_container[2, 1] = empty_layout
            hidden_layout[1,1] = color_option_grid
        end
    end

    on(btn_color.clicks) do _
        is_colorgrid_visible[] = true
    end
    #######################
    
    menu_container[2,1] = empty_layout
    hidden_layout[1,1] = color_option_grid

    populate_dropdown(fig,
                      color_option_grid, 
                      cmap, 
                      current_color, 
                      is_colorgrid_visible; 
                      btn_height = color_btn_height,
                      num_color_cols,
                      btn_width = 0.7*(sidebar_width / num_color_cols),
                      )

    

    return fig
end



function populate_dropdown(fig::Figure, grid::GridLayout, 
                            colormap_entries, 
                            current_color::Observable, 
                            is_open:: Observable;
                            btn_height = 30,
                            num_color_cols = 4,
                            btn_width = 30,
                            )
    

    num_colors = length(colormap_entries)
    num_rows = ceil(Int, num_colors / num_color_cols)
    num_matrix = num_rows * num_color_cols
    entry_matrix = reshape(1:num_matrix, num_rows, num_color_cols)

    R = CartesianIndices(entry_matrix)
    for i in 1:num_colors
        j, k = Tuple(R[i])
        entry = colormap_entries[i]
        # Create a Button for each entry
        btn = grid[j, k] = Button(fig, 
            label = "", #no label
            # Customize the appearance with a colored Box
            buttoncolor = entry, 
            height = btn_height,
            width = btn_width,
        )
        
        # When a button is clicked, update the selected color and close the dropdown
        on(btn.clicks) do _
            current_color[] = entry
            is_open[] = false
        end
    end
    
    # Ensure the grid is positioned correctly over the main figure
    rowgap!(grid, 1) # Reduce gap between color rows
    
    return
end


# function create_color_menu_entries(cmap_name=:viridis::Symbol, num_entries = 10)
    
#     cmap = cgrad(cmap_name, num_entries; categorical = true)

#     entries = Vector{Tuple{String, eltype(cmap)}}()

#     for (i, color) in enumerate(cmap)
        
#         label = "Color $i"

#         push!(entries, (label, color))
#     end
#     return entries
# end


# function draw_color_entry(label, color)
#     # The function returns a vector of drawables:
#     return [
#         # 1. A colored rectangle on the left side
#         Rect(0.05, 0.45, 0.9, 0.6, color),
#         # 2. The text label centered on the right side
#         Text(label, 0.5, 0.5) 
#     ]
# end


# function menu_filter_function(menu_entry, i)
#     label, color = menu_entry
#     return [
#         Rect(0.05, 0.45, 0.9, 0.6, color)
#     ]

# end



end # module YetAnotherPlotDigitizer
