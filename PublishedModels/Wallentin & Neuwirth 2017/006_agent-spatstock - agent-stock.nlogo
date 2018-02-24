extensions [gis]

breed [fish a-fish]

fish-own [
  age
  sex
  flockmates
  nearest-neighbor
  E-ingested
  E-survive
  E-growth
  E-repro
]

patches-own [
  lake                 ; values of lake raster (attersee.asc dataset): 0 = no lake; 1 = lake
  plankton-bio         ; plankton stock
  plankton-eaten       ; plankton consumed by fish agents and school SDs
]

globals [
  cohesion-flag        ; helper variable to tag schools
  counter              ; = integer of ticks (ticks have small rounding errors if governed by advance-dt)
  fish-stock
  sd-setup-count

;; plankton stock variables
  plankton-bio-sd
  plankton-eaten-sd

;; spatial variables
  scale-factor         ; conversion factor between metre NetLogo distance units
  attersee-dataset     ; GIS shapefile of lake
  lake-patches         ; all patches inside the lake
  coast-patches        ; all patches adjacent to land

;; flocking parameters
  vision
  minimum-separation
  max-align-turn
  max-cohere-turn
  max-separate-turn

;; SD import
  ;; constants
  carrying-capacity
  growth-rate
  plankton-growth-rate
  exponent-offspring
  exponent-mortality

  ;; size of each step, see SYSTEM-DYNAMICS-GO
  dt
  ]



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; SETUP PROCEDURES ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; system-dynamics-setup, and system-dynamics-go are automatically
;; generated by the System Dynamics Modeler.  The code can be viewed in the
;; Code Tab of the System Dynamics Modeler.

to setup
  ca
  reset-ticks
  reset-timer
  set cohesion-flag true
  ; time counter needed in ABM, because of rounding errors in "ticks" when incrementally advanced by SD
  set counter 0

  ;; load GIS data
  ; loads Attersse.shp into the global variable “Attersee-dataset”
  set attersee-dataset gis:load-dataset "/netlogodata/Attersee.asc"

  ; defines the extent of the ‘World’ by the bounding box of a dataset
  gis:set-world-envelope (gis:envelope-of attersee-dataset)

  ; calculate scale conversion factor
  let envelope gis:envelope-of attersee-dataset
  let y-extent item 3 envelope - item 2 envelope
  ; scale-factor = 200 (with a world setting of 45 x 90 cells) -> 1 patch is 200m x 200m
  set scale-factor y-extent / (max-pycor + 1)

  ; copy values from Attersee-dataset into an lake patch variable (lake)
  gis:apply-raster attersee-dataset lake

  ; color lake patches blue and coast patches green
  ask patches [ifelse lake = 1 [set pcolor blue][set pcolor 68]]
  set lake-patches patches with [pcolor = blue]
  ask lake-patches [if count neighbors with [pcolor = 68] > 0 [set pcolor 97]]
  set coast-patches lake-patches with [pcolor = 97]

  ; set flocking parameters in metre and degree
  set vision 700
  set minimum-separation 10
  set max-align-turn 2
  set max-cohere-turn 8.5
  set max-separate-turn 3

  ; create ABM fish
  create-fish initial-number-of-fish [
    let a one-of lake-patches
    set shape "fish"
    set color orange
    set size 1
    setxy [pxcor] of a [pycor] of a
    set age random-float 6
    set sex random 2  ;female = 0, male = 1
    set E-repro 0
  ]

  ;set fish-stock count fish
  ask fish [ find-flockmates ]
  set sd-setup-count 0

  ;; setup SD model part
  sd-setup

end


;; Initializes the system dynamics model.
;; Call this in your model's SETUP procedure.
to sd-setup
  reset-ticks
  set dt 1 ; should be 0.01!
  ;; initialize constant values
  set carrying-capacity 2300
  set growth-rate 0
  set plankton-growth-rate 0.01
  set exponent-offspring 1
  set exponent-mortality 0.033

  ;; initialize plankton biomass in patches stochastically
  ask lake-patches [ set plankton-bio ((2000 + random 300) / count lake-patches) ]
  ;; initialize plankton biomass homogeneously to see switch operation
  ;ask lake-patches [ set plankton-bio ((2150) / count lake-patches) ]
  display-plankton
end


;; set SD parameters after spatial stock --> stock switch
to sd-setup-parametrization
  show timer
  show ticks
  ;show "switched to stock"

  set plankton-bio-sd sum [plankton-bio] of lake-patches
  ask lake-patches [set plankton-bio 0]
end



;; reset simulation environment after stock --> spatial stock switch
to spatial-stock-reset
  set-current-plot "Fish Stock"
  set-plot-pen-color black
  set-current-plot "performance"
  set-plot-pen-color black

  set sd-setup-count 0

  ask lake-patches [set plankton-bio (plankton-bio-sd / count lake-patches)]
  set plankton-bio-sd 0
  set plankton-eaten-sd 0
end




;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; GO PROCEDURE ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to go

  if counter = 0 [reset-timer]
  if counter mod (365 / dt) = 0 [show timer]

  ; execute ABM actions daily
  if counter mod (1 / dt) = 0 [

    ;; execute ABM fish behaviour
    ask fish [
      ; fish turn to flock with others
      flock

      ; move 20m
      move ( 20 )

      ; calculate energy budget
      update-energy

      ;; reproduce, if eligible
      if sex = 0 [reproduce]

      ; grow older
      set age age + 1 / 365  ;one day (=1/365)

      ; die of age or if the fish has no more energy reserves (starvation)
      if age > 6 or E-repro < 0 [ die ]
    ]
  ]

  ;; execute actions in spatial stock mode
  if plankton-spatial? = TRUE  [

    ; if just switched back from stock mode
    if sum [plankton-bio] of lake-patches = 0 [spatial-stock-reset]

    spatial-sd-go

    ;; diffuse plankton: 10% per month (30 days)
    diffuse plankton-bio (0.1 / 30)

    ; return plankton from non-lake patches back to the lake
    ask patches with [lake != 1 and plankton-bio > 0] [
      ask min-one-of neighbors with [lake = 1] [plankton-bio] [set plankton-bio (plankton-bio + [plankton-bio] of myself)]
      set plankton-bio 0
      ]

    ;fish eat 2.7g per day
    ask lake-patches [set plankton-eaten (count fish-here * 0.0000027)]
    display-plankton
  ]

  ; stop, if no fish are left
  if count fish = 0 [stop]

  ;; execute actions in aggregate plankton stock mode
  if plankton-spatial? = FALSE [
    ;switch, if spatial stocks are homogeneous
    if sd-setup-count = 0 [
      sd-setup-parametrization
      set sd-setup-count 1
      set-current-plot "Fish Stock"
      set-plot-pen-color red
      set-current-plot "performance"
      set-plot-pen-color red
    ]
    sd-go
    set plankton-eaten-sd count fish * 0.0000027
    display-plankton-sd
  ]

  set fish-stock count fish
  update-plots

  ; stop conditions
  if scenario = "100 years" [
    if ticks >= (365 * 100) [ show timer show ticks stop ]
  ]

  if scenario = "fishing" [
    if fish-stock > 500 [fishing 25]
  ]


  ; count helper to calculate ABM time steps
  set counter counter + 1
end



;; Step through the system dynamics model by performing next iteration of Euler's method.
;; Call this in your model's GO procedure.
to spatial-sd-go
  ask lake-patches [
    ;; compute variable and flow values once per step
    let local-biomass-growth biomass-growth
    let local-biomass-removed biomass-removed
    ;; update stock values
    ;; use temporary variables so order of computation doesn't affect result.

    let new-plankton-bio ( plankton-bio + local-biomass-growth - local-biomass-removed )
    set plankton-bio new-plankton-bio
  ]

  tick-advance dt
end


;; Step through the system dynamics model by performing next iteration of Euler's method.
;; Call this in your model's GO procedure.
to sd-go
  ;; compute variable and flow values once per step
  let local-biomass-growth biomass-growth-sd
  let local-biomass-removed biomass-removed-sd
  ;; update stock values
  ;; use temporary variables so order of computation doesn't affect result.
  let new-plankton-bio ( plankton-bio-sd + local-biomass-growth - local-biomass-removed )
  set plankton-bio-sd new-plankton-bio

  tick-advance dt
end

;;;;;;;;;;;;;;;;;;;;;;; FLOCKING Behaviour (from the NetLogo Library) ;;;;;;;;;;;;;;;;;;;;;;;

to flock  ;; a-fish procedure
  find-flockmates
  if any? flockmates
    [ find-nearest-neighbor
      ifelse distance nearest-neighbor < (minimum-separation / scale-factor)
        [ separate ]
        [ align
          cohere ] ]
end

to find-flockmates  ;; a-fish procedure
  set flockmates other fish in-radius (vision / scale-factor)
end

to find-nearest-neighbor ;; a-fish procedure
  set nearest-neighbor min-one-of flockmates [distance myself]
end

;;; SEPARATE

to separate  ;; a-fish procedure
  turn-away ([heading] of nearest-neighbor) max-separate-turn
end

;;; ALIGN

to align  ;; a-fish procedure
  turn-towards average-flockmate-heading max-align-turn
end

to-report average-flockmate-heading  ;; a-fish procedure
  ;; We can't just average the heading variables here.
  ;; For example, the average of 1 and 359 should be 0,
  ;; not 180.  So we have to use trigonometry.
  let x-component sum [dx] of flockmates
  let y-component sum [dy] of flockmates
  ifelse x-component = 0 and y-component = 0
    [ report heading ]
    [ report atan x-component y-component ]
end

;;; COHERE

to cohere  ;; a-fish procedure
  turn-towards average-heading-towards-flockmates max-cohere-turn
end

to-report average-heading-towards-flockmates  ;; a-fish procedure
  ;; "towards myself" gives us the heading from the other a-fish
  ;; to me, but we want the heading from me to the other a-fish,
  ;; so we add 180
  let x-component mean [sin (towards myself + 180)] of flockmates
  let y-component mean [cos (towards myself + 180)] of flockmates
  ifelse x-component = 0 and y-component = 0
    [ report heading ]
    [ report atan x-component y-component ]
end

;;; HELPER PROCEDURES

to turn-towards [new-heading max-turn]  ;; a-fish procedure
  turn-at-most (subtract-headings new-heading heading) max-turn
end

to turn-away [new-heading max-turn]  ;; a-fish procedure
  turn-at-most (subtract-headings heading new-heading) max-turn
end

;; turn right by "turn" degrees (or left if "turn" is negative),
;; but never turn more than "max-turn" degrees
to turn-at-most [turn max-turn]  ;; a-fish procedure
  ifelse abs turn > max-turn
    [ ifelse turn > 0
        [ rt max-turn ]
        [ lt max-turn ] ]
    [ rt turn ]
end



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; HELPER PROCEDURES ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;; update energy budget of fish agents
; plankton controls the energy budget of fish in the following order: maintenance, growth and reproduction (Sibly et al., 2013)
to update-energy
  set E-ingested 2.7 * ((plankton-bio + plankton-bio-sd) / (carrying-capacity / count lake-patches) ) / ((plankton-bio + plankton-bio-sd) / (carrying-capacity / count lake-patches) + 2)  ;; after Sibly 2013
  ; the normalisation constant is set to 0.005; body mass is estimated to be 100g * age
  set E-survive 0.005 * (age * 100)^ 0.75                                                    ;; after Sibly 2013
  ; under opimal conditions, after survival costs: 50% of the available energy goes into growth and 50% into reproduction
  set E-growth 0.5 * (0.9 - E-survive)                                                      ;; maximum E-ingest = 0.9
  ; The reproduction energy includes maturation and reproduction; it is cumulative over the lifespan of a fish.
  if age > 4 [ set E-repro E-repro + E-ingested - E-survive - E-growth ]

end

;; agent reproduction
to reproduce
  ; probability of reproduction for an annual offspring of 5 (= 5 fish per 365 days)
  ; school membership, age >= 4, female gender and a optimum plunkton intake of >= 2.7g (0.0000027 tons)
  ; is prerequisite for reproduction
  if (random-float 1 < (5 / 365)) and (count flockmates > 5) and (age >= 4) and (sex = 0) and (E-repro > 15)[
    set E-repro E-repro - 15
    hatch-fish 1 [
      let a one-of coast-patches
      set sex random 2
      set age 0
      setxy [pxcor] of a [pycor] of a
      set E-repro 0
      ]
    ]
end

;; fish move forward and turn at coast
to move [dist]
  ; move [dist] metres per day
  ifelse [lake] of patch-ahead ((2 * dist) / scale-factor) != 1
    [set heading heading + 180 ]
    [fd dist / scale-factor]
end



;; remove fish
to fishing [remaining-fish]
  while [count fish > remaining-fish][
    ask one-of fish [die]
  ]
end


;; report 180° turn true, if fish approaches the coast
to-report turn-180
  ifelse [lake] of patch-ahead (20 / scale-factor) != 1 [report true] [report false]
end


;; check for mode switch criteria
to-report plankton-spatial?
  ; switch criteria
  ; stock -> spat stock: fish feed more than 0.00005% of total max. plankton per day (=0.001 tons / 1kg plankton ~ daily consumption of 370 fish); extremely low value chosen to see effect before fishing treshold
  ; spat stock  -> stock: homogeneous biomass: the standard deviation of plankton biomass in lake patches is below 0.5%
  ifelse standard-deviation [plankton-bio] of lake-patches > 0.005 or (sum [biomass-removed] of lake-patches + biomass-removed-sd) > 0.001
    [report TRUE]
    [report FALSE]
end


;; Helper procedures
;; Report value of flow in spatial stock
to-report biomass-growth
  report ( plankton-bio * plankton-growth-rate * ( 1 - plankton-bio / (carrying-capacity / count lake-patches) )
  ) * dt
end

;; Report value of flow
to-report biomass-growth-sd
  report ( plankton-bio-sd * plankton-growth-rate * ( 1 - plankton-bio-sd / carrying-capacity )
  ) * dt
end

;; Report value of flow
to-report biomass-removed
  report ( plankton-eaten
  ) * dt
end

;; Report value of flow
to-report biomass-removed-sd
  report ( plankton-eaten-sd
  ) * dt
end



;;;;;;;;;;;;;;;;;;;;;;;;;;; DISPLAY ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to display-plankton
  let min-biomass 1500 / count lake-patches
  let max-biomass 2300 / count lake-patches

  ask lake-patches [ set pcolor scale-color blue plankton-bio min-biomass max-biomass ]
end

to display-plankton-sd
  let min-biomass 1500
  let max-biomass 2300

  ask lake-patches [ set pcolor scale-color blue plankton-bio-sd min-biomass max-biomass ]
end

; Written by: Gudrun Wallentin and Christian Neuwirth
; Please refer to the following publication to cite the model:
;    Wallentin, G., and Neuwirth, C. (2016) "Dynamic hybrid modelling: switching between AB and SD designs of a predator-prey model". Ecological Modelling (under review)
; This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike 3.0 License
; https://creativecommons.org/licenses/by/3.0/
@#$#@#$#@
GRAPHICS-WINDOW
433
24
883
955
-1
-1
10.0
1
10
1
1
1
0
1
1
1
0
43
0
89
1
1
1
ticks
30.0

BUTTON
12
10
75
43
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
12
50
75
83
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
11
96
74
129
step
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

PLOT
897
379
1271
531
Number of adult fish which do not belong to a school
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -7500403 true "" "plot count fish with[(age >= 4) and (count flockmates <= school-threshold)]"

SLIDER
7
154
199
187
initial-number-of-fish
initial-number-of-fish
0
5000
25
5
1
NIL
HORIZONTAL

PLOT
7
319
374
510
Fish Stock
years
number of fish
0.0
1.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "if ticks > 0 [plotxy ticks / 365 (count fish)]"

SLIDER
7
200
179
233
school-threshold
school-threshold
0
100
50
1
1
NIL
HORIZONTAL

PLOT
5
516
374
676
Plankton
years
biomass [tons]
0.0
1.0
1800.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "if ticks > 0 [plotxy ticks / 365 sum [plankton-bio] of lake-patches + plankton-bio-sd]"

TEXTBOX
452
66
602
126
blue scale: biomass in lake\n1500t (black)\n2300t (light blue)
11
0.0
1

MONITOR
1275
433
1342
478
NIL
count fish
17
1
11

MONITOR
448
164
505
209
years
floor (ticks / 365)
0
1
11

PLOT
6
682
374
832
performance
years
elapsed time
0.0
1.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "if ticks > 0 [plotxy ticks / 365 timer]"

BUTTON
1026
148
1119
181
makemovie
;; make a 20-step movie of the current view\nsetup\nmovie-start \"typ3.mov\"\nrepeat 36500 [\n  if ticks mod 100 = 0 [movie-grab-interface]\n  go\n]\nmovie-close
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
954
307
1108
340
display plankton-stock
ask lake-patches [ set pcolor scale-color blue plankton-bio (1500 / count lake-patches) (2300 / count lake-patches)]
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
97
274
164
319
NIL
count fish
17
1
11

PLOT
898
543
1274
693
plot 1
NIL
NIL
0.0
10.0
0.0
0.005
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "if ticks > 0 [plot standard-deviation [plankton-bio] of lake-patches]"

CHOOSER
113
28
251
73
scenario
scenario
"100 years" "fishing"
1

@#$#@#$#@
## PURPOSE
The fish-plankton model represented the dynamics of a fish population in a lake in response to plankton abundance. The purpose of the model was to represent spatio-temporal population dynamics of plankton-feeding fish. The model specifically aimed to capture the dynamics of a small fish population that is governed by stochastic events of local interactions as well as the dynamics of large a population that is limited by the abundance of plankton biomass for feeding. For its specification the model partly borrowed from literature on Alpine whitefish (Coregonus laveretus) in the lake Attersee in Austria, complemented with fictitious parameter values.

## ENTITIES, STATE VARIABLES AND SCALES
The entities in the model were fish and plankton. Depending on the design, fish were represented as agents, school-agents, spatial stocks or stocks. The plankton was represented either by a stock of a SD model or by spatial stocks in a cellular automaton. State variables were the number of fish and the amount of plankton biomass in tons.
The temporal scale of the model had a resolution of one day and extended over a simulation period of one century. The lake was roughly rectangular with dimensions of about 20 km by 2 km amounting to 46 km2 surface area in total. In spatial variants of the model, the plankton was distributed over a cellular automaton grid with a cell size of 200m by 200m. Fish movement was represented in continuous vector space.

## PROCESS OVERVIEW AND SCHEDULING
A single fish agent moved straight ahead until it sensed other fish, to which it adapted its movements according to the three rules of the boids model (Reynolds, 1987). From this behaviour fish schools emerged and grew over time. School membership was a prerequisite to successful reproduction in the ABM. Under optimal conditions, an annual offspring of five fish per mature female survived the first year. Female fish laid the eggs close to the shoreline out of which young fish developed independently from any fish school. The fish matured at the age of four and reached a maximum age of six years, but may have died of starvation earlier. A fish agent consumed 2.7 g plankton per day under maximum plankton availability. Lower plankton availability controlled the energy budget of fish in the order of maintenance, growth and reproduction (Sibly et al., 2013).
Plankton biomass exhibited a logistic growth. The carrying capacity of plankton in the lake was assumed to be 2,300 tons. In spatial variants of the model, plankton diffused 10% of its biomass per month into neighbouring cells.
The fish population was initialised with 25 individual fish agents, which is a situation close to extinction. Fish age and sex were attributed randomly from a uniform distribution. The individual locations in the lake were also assigned randomly. Plankton was set to 2150 tons, which is a value close to the carrying capacity of the lake.
As the fish population grew to a viable population size that had organised itself into schools of fish, a trigger caused the agents to switch to a more aggregate representation: school-agents, spatial stocks or stocks. If the fish population fell below 50 fish, the model switched back to its initial configuration.

## HYBRID MODEL DESIGN AND PARADIGM SWITCHES
please refer to the below reference for details.

## RELATED MODELS

This is Design 6 of a series of six hybrid model designs.
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
true
0
Polygon -16777216 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -16777216 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -16777216 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270

@#$#@#$#@
NetLogo 5.3.1
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="experiment" repetitions="10" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="12000"/>
    <metric>count turtles</metric>
    <enumeratedValueSet variable="vision">
      <value value="700"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-number-of-fish">
      <value value="5000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="swarm-threshold">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-align-turn">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-separate-turn">
      <value value="3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="minimum-separation">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-cohere-turn">
      <value value="8.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flocking-priority">
      <value value="1"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180

@#$#@#$#@
0
@#$#@#$#@
