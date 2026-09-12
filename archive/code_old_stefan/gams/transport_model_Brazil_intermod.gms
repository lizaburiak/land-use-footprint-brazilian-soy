$title Transport Optimization of Soy Products between Brazilian Municipalities

$onText
The model allocates supply of three different soy products (soybean, oil and cake) to demand
across all municipalities under cost minimization and a fixed modal split between transport modes truck, train and ship.
$offtext

* enable end-of line comments
$onEolCom
$eolcom ##


* load already prepared gdx data
$GDXIN %INPUT%
*##.\GAMS_data.gdx 

Sets product 'type of soy product' 
$loaddc product = product 

Sets a 'municpalities'
$loaddc a = a 

* Alias b is used to refer to demanding MUs while a will represent supplying MUs
Alias (a,b);

Sets r1 'origin rail stations'
$loaddc r1 = r1 

Sets r2 'destination rail stations'
$loaddc r2 = r2 

Sets w1 'origin ports'
$loaddc w1 = w1 

Sets w2 'destination ports'
$loaddc w2 = w2


Parameter C_a_b(a,b) matrix of road transport cost for each MU pair and mode in $ per ton
$loaddc C_a_b = C_a_b

Parameter C_a_r1(a,r1) matrix of road transport cost from each MU to each origin rail terminal in $ per ton
$loaddc C_a_r1 = C_a_r1

Parameter C_a_w1(a,w1) matrix of road transport cost from each MU to each origin port terminal in $ per ton
$loaddc C_a_w1 = C_a_w1

Parameter C_r2_b(r2,b) matrix of road transport cost from each destination rail terminal to each MU in $ per ton
$loaddc C_r2_b = C_r2_b

Parameter C_w2_b(w2,b) matrix of road transport cost from each destination port terminal to each MU in $ per ton
$loaddc C_w2_b = C_w2_b

Parameter C_r1_r2(r1,r2) matrix of road transport cost from each origin rail terminal to each destination rail terminal in $ per ton
$loaddc C_r1_r2 = C_r1_r2

Parameter C_w1_w2(w1,w2) matrix of road transport cost from each origin port terminal to each destination port terminal in $ per ton
$loaddc C_w1_w2 = C_w1_w2

Parameter  supply(a,product) 'supply of each soy product in each MU (t)'
$loaddc supply = supply

Parameter  demand(b,product) 'demand for each soy product in each MU (t)'
$loaddc demand = demand

Parameter exp_proc(b,product) 'export and processing use of each soy product in each MU (t)'
$loaddc exp_proc = exp_proc

Parameter cap_r(r1, r2, product) 'capacity of each rail route (t)'
$loaddc cap_r = cap_r

Parameter cap_w(w1, w2, product) 'capacity of each water route (t)'
$loaddc cap_w = cap_w

* close GDX file
$GDXIN

*$exit

Parameter report1(product,*) 'report sheet to summarize results for each product'
*         report2(*,*,*) 'report sheet to summarize transport amounts between MUs across all transport modes'

;

* define variables

Free variable
    xtotalcost 'total transport cost' 
    xtotalsoytransport(product) 'total amount of ton-kilometers transported'
    xtotalinflow(b, product)
;

Positive variable
    X_a_b(a,b,product) 'transport from a to b in tons by mode'
    X_a_r1(a,r1,product)
    X_a_w1(a,w1,product)
    X_r1_r2(r1,r2,product)
    X_w1_w2(w1,w2,product)
    X_w2_b(w2,b,product)
    X_r2_b(r2,b,product)
;

* define equations

Equation
    cost 'objective function to be minimized'
    supply_const(a, product) 'constraint to ensure that transport from all municipalities does not exceed their supply'
    demand_const(b, product) 'constraint to ensure demand of all municipalities is met'
    totaltransport(product) 'total amount of ton-kilometers transported'
    hub_const_r1(r1, product) 'contraint ensuring everthing transported to hubs is brought to destination hub'
    hub_const_w1(w1, product)
    hub_const_r2(r2, product) 'contraint ensuring everthing transported to destination hub is transported to destination MU'
    hub_const_w2(w2, product)
    cap_const_r(r1, r2, product) 'capacity constraints on ship/train routes'
    cap_const_w(w1, w2, product)
    intermod_const(b, product) 'constraint ensuring that intermodal transport is only used for export or processing use'
*    totalinflow(b, product)
;

cost.. 
    SUM((a,b,product),   C_a_b(a,b)   *  X_a_b(a,b,product)$(supply(a,product) and demand(b,product))) +
    SUM((a,r1,product),  C_a_r1(a,r1) *  X_a_r1(a,r1,product)$(supply(a,product))) + ##and SUM(r2,cap_r(r1,r2, product))
    SUM((r1,r2,product), C_r1_r2(r1,r2)$(cap_r(r1,r2, product)) *  X_r1_r2(r1,r2,product)$(cap_r(r1,r2, product))) +
    SUM((r2,b,product),  C_r2_b(r2,b) *  X_r2_b(r2,b,product)$(demand(b,product) and exp_proc(b,product)))+
    SUM((a,w1,product),  C_a_w1(a,w1) *  X_a_w1(a,w1,product)$(supply(a,product))) + ## and SUM(w2,cap_w(w1,w2, product))
    SUM((w1,w2,product), C_w1_w2(w1,w2)$(cap_w(w1,w2, product)) *  X_w1_w2(w1,w2,product)$(cap_w(w1,w2, product))) +
    SUM((w2,b,product),  C_w2_b(w2,b) *  X_w2_b(w2,b,product)$(demand(b,product) and exp_proc(b,product)))
    =E= xtotalcost  ;

*supply_const(a, product)..
*    SUM(b, X_a_b(a,b,product)$(supply(a,product) and demand(b,product)))+  ## 
*    SUM(r1, X_a_r1(a,r1,product)$(supply(a,product)))+ ## 
*    SUM(w1, X_a_w1(a,w1,product)$(supply(a,product))) ##
*    =L= supply(a,product) ;

supply_const(a, product)..
    SUM((b),  X_a_b(a,b,product)$(supply(a,product) and demand(b,product)))+ 
    SUM((r1), X_a_r1(a,r1,product)$(supply(a,product)))+ 
    SUM((w1), X_a_w1(a,w1,product)$(supply(a,product))) 
    =L= supply(a,product) ;

demand_const(b, product)..
    SUM((a), X_a_b(a,b,product)$(supply(a,product) and demand(b,product)))+ ##
    SUM((r2), X_r2_b(r2,b,product)$(demand(b,product) and exp_proc(b,product)))+ ##
    SUM((w2), X_w2_b(w2,b,product)$(demand(b,product) and exp_proc(b,product))) ##
    =G= demand(b,product) ;
 
totaltransport(product)..
    SUM((a,b), X_a_b(a,b,product)$(supply(a,product) and demand(b,product)))+
    SUM((a,r1), X_a_r1(a,r1,product)$(supply(a,product)))+
    SUM((a,w1), X_a_w1(a,w1,product)$(supply(a,product)))
    =E= xtotalsoytransport(product) ;

* capacity constraint per hub

* contraint ensuring everthing transported to rail/water hubs is brought to destination hub
hub_const_r1(r1, product)..
    SUM(r2, X_r1_r2(r1,r2,product)$(cap_r(r1,r2, product))) - SUM(a, X_a_r1(a,r1,product)$(supply(a,product)))
    =E= 0;
    
hub_const_w1(w1, product)..
    SUM(w2, X_w1_w2(w1,w2,product)$(cap_w(w1,w2, product))) - SUM(a, X_a_w1(a,w1,product)$(supply(a,product)))
    =E= 0;

* contraint ensuring everthing transported to destination hub is transported to destination MU
hub_const_r2(r2, product)..
    SUM(r1, X_r1_r2(r1,r2,product)$(cap_r(r1,r2, product))) - SUM(b, X_r2_b(r2,b,product)$(demand(b,product)))
    =E= 0;
    
hub_const_w2(w2, product)..
    SUM(w1, X_w1_w2(w1,w2,product)$(cap_w(w1,w2, product))) - SUM(b, X_w2_b(w2,b,product)$(demand(b,product)))
    =E= 0;

* impose capacity constraints on ship/train routes
cap_const_r(r1,r2,product)..
    X_r1_r2(r1,r2,product)  =L= cap_r(r1,r2,product) ;
    
cap_const_w(w1,w2,product)..
    X_w1_w2(w1,w2,product)  =L= cap_w(w1,w2,product) ;
 
* constraint ensuring that intermodal transport is only used for export or processing use
intermod_const(b, product)..
    SUM(r2, X_r2_b(r2,b,product)) + SUM(w2, X_w2_b(w2,b,product))
    =L= exp_proc(b,product) ;

* just a varibale detecting total inflow in each MU    
*totalinflow(b, product)..
*    SUM(a, X_a_b(a,b,product)$(demand(b,product)) +
*    SUM(r2, X_r2_b(r2,b,product)$(demand(b,product)) +
*    SUM(w2, X_w2_b(w2,b,product)$(demand(b,product))
*    =E= xtotalinflow(b, product)

model transport_model / all /;

*use CPLEX and define some options for it (see bottom of script)
option LP=cplex;
transport_model.optfile=1;

* some options to save memory according to https://support.gams.com/solver:error_1001_out_of_memory and https://yetanothermathprogrammingconsultant.blogspot.com/2009/06/large-easy-lps-are-modeling-systems.html
option limrow=0;
option limcol=0;
option iterlim=1000000;
option solvelink = 0;
transport_model.solprint=0;
transport_model.dictfile=0; 

solve transport_model using lp minimizing xtotalcost; 

* compile report of main results for each product 
report1(product, "total cost") =
    SUM((a,b),   C_a_b(a,b) *    X_a_b.l(a,b,product)$(supply(a,product) and demand(b,product))) +
    SUM((a,r1),  C_a_r1(a,r1) *  X_a_r1.l(a,r1,product)$(supply(a,product))) +
    SUM((r1,r2), C_r1_r2(r1,r2)$(cap_r(r1,r2, product)) *  X_r1_r2.l(r1,r2,product)$(cap_r(r1,r2, product))) +
    SUM((r2,b),  C_r2_b(r2,b) *  X_r2_b.l(r2,b,product)$(demand(b,product) and exp_proc(b,product)))+
    SUM((a,w1),  C_a_w1(a,w1) *  X_a_w1.l(a,w1,product)$(supply(a,product))) +
    SUM((w1,w2), C_w1_w2(w1,w2)$(cap_w(w1,w2, product)) *  X_w1_w2.l(w1,w2,product)$(cap_w(w1,w2, product))) +
    SUM((w2,b),  C_w2_b(w2,b) *  X_w2_b.l(w2,b,product)$(demand(b,product) and exp_proc(b,product)))
;
    
report1(product, "tons") = xtotalsoytransport.l(product);

report1(product, "tons_direct") = SUM((a,b), X_a_b.l(a,b,product));
report1(product, "tons_train") = SUM((r1,r2), X_r1_r2.l(r1,r2,product));
report1(product, "tons_ship")  = SUM((w1,w2), X_w1_w2.l(w1,w2,product));

* compile matrix of transport volumes across all modes
*--> here we see the bottleneck issus
*report2(product,a,b) =  SUM(road, xrm.l(road,a,b,product)) + SUM(road, xrh.l(road,a,h,product))



display report1 ; 
*display report2


execute_unload '%OUTPUT%',
    xtotalcost.l,
    X_a_b.l,
    X_a_w1.l,
    X_a_r1.l,
    X_w1_w2.l,
    X_r1_r2.l,
    X_w2_b.l,
    X_r2_b.l;



* options for cplex solver
$onecho > cplex.opt
lpmethod 0
threads 1
memoryemphasis 1
baralg 0
names no
$offecho




