# YetAnotherPlotDigitizer

## Overview
Yep, it's yet another plot digitizer, but with bezier curves instead of just a list of coordinates.
The purpose of this tool does is to take points (curves) in image space (pixels) and transform them into another more useful space (plot space).

## Installation
For this tool to work you need to have a working Julia installation. I recommend installing via [Juliaup](https://github.com/JuliaLang/juliaup).
Navigate to a new (empty) folder and start Julia there.
Go into package mode via ']'
* Activate a new environment and add the package
```
activate . 
add https://github.com/barabule/YetAnotherPlotDigitizer.git
```

* Then, after it finishes installing, exit package more (Backspace) and use the package and call the _main_ function:

```
using YetAnotherPlotDigitizer
main()
```

* This will start a GUI.
  
# First steps
Drop an image onto the window to load and display it. This will reset most setting. If you want to digitize more plots just drop a new image and go from there, no need to restart the application.

## Scale Markers
* There are 4 draggable scale markers positioned on the image (red for X1 & X2 direction, green for Y1 & Y2).
* Position them over the image features where you can infer a value, usually axis ticks with numbers.
* For X only the X coordinate is meaningfull, the same goes for Y.  The scale markers don't need to be vertical / horizontal.
* You can even put them in reverse order (you'll get reversed curves when exporting).
* The scale markers need only to be separated by some distance to work.
* They don't need to be 'outside' the curves, you can put curves outside the bounding box of the markers.
* Set the values for the Xs and Ys in their corresponding textbox. Press Enter for the changes to 'stick', look for the status label on top to reflect the change.
* You can change this whenever you need before exporting, so don't worry about it too much.
* For logarithmic scales keep in mind to have strictly positive (non zero) values for both scale markers (i.e. X1 & X2 or Y1 & Y2). If this is not the case, you won't be able to export anything.

## Curve Editing

* By default a 1 segment cubic Bezier curve is created. The curve is modified by dragging its control cage.
* You can also add ('a' key) and delete ('d' key) control points.
* The control points of the curve come in 2 flavors: main (interpolating) and handle points.
* Each main control point can be smooth or sharp (toggled by the 's' key).
* 'Sharp' means that the associated handle points can be moved independently from each other.
* For smooth control points the 2 handle points are always collinear with the main point. This is very similar to how a vector editor works.
* You can't delete the last 2 remaining control points.

## Other Controls

* On the right you can find a few controls with settings for the currently edited curve.
* A textbox to change the curve name (used in export). Press 'Enter' to confirm the new name.
* Button to add or delete curves. You can't delete the last remaining curve.
* A button to choose the displayed color from a predefined selection. This is purely for usability purposes, to be able see keep the curves apart.
* A menu to select the currently edited curve.
* You can always come back and edit a curve by selecting it from here.
* The control cages will be remembered and restored when re-editing.

## Export

After you're done, export the curves with the 'Export' button. You can set how many points are exported and the delimiter (for now). All curves will be exported as delimited text files with separate names in the same folder as the image file.
