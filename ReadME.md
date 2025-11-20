# Overview
Yep, it's yet another plot digitizer.
This one's different from the others.

On the plus side we're not clicking like cavemen anymore, no, we are fitting piecewise cubic Bezier curves on the raster plots. Hooray!

To install:
Navigate to a new (empty) folder and start Julia there.
Go into package mode via ]

```
activate .
add https://github.com/barabule/YetAnotherPlotDigitizer.git
```

Then, after it finishes installing, exit package more (Backspace) and type:

```
using YetAnotherPlotDigitizer
main()
```

This will start a GUI.
Drop an image onto the window to load it.

Position the X1, X2, Y1, Y2 markers over the image features.For X only the X coordinate is meaningfull, for the Y only the Y coordinate, they don't need to be vertical / horizontal!
Set the values for the Xs and Ys in their corresponding textbox. Press Enter for the changes to 'stick'.
You can do this whenever before exporting so don't worry about it, but don't forget about it.
All this tool does is take points in image space (pixels) and transform them into another space (plot).

By default a 1 segment cubic Bezier curve is created. You can drag the vertices to fit a curve over the image. Add more segments with 'a', delete segments with 'd'.
You can change the name of the curve and its color.
Add 1 more curve with the 'Add' button.
There's a menu to select  existing curves.

After you're done, export the curves with the 'Export' button. You can set how many points are exported.
All curves are sampled uniformly in arclength.
Each curve is exported separately.

Not all features are implemented yet: log spacing, better curve management.