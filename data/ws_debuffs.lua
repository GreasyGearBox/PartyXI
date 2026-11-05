-- Phoenix live 9a4494d5056429d0e75922dc9fa47d419142cf68, scripts/actions/weaponskills/.
-- Non-relic era WS only. Durations are unresisted estimates; TP-dependent
-- entries use 1000 TP because the result packet does not provide TP spent.
-- Mapping/inferred-hit approach informed by XIUI handlers/database/debuff_retail.lua
-- and handlers/debuffhandler.lua (GPL; https://github.com/tirem/XIUI).
return {
    [2]={name='Shoulder Tackle',effects={10},duration=2,tpDependent=true},
    [16]={name='Wasp Sting',effects={3},duration=90,tpDependent=true},
    [17]={name='Viper Bite',effects={3},duration=90,tpDependent=true},
    [18]={name='Shadowstitch',effects={11},duration=10,tpDependent=true},
    [35]={name='Flat Blade',effects={10},duration=4,tpDependent=false},
    [52]={name='Shockwave',effects={2},duration=60,tpDependent=true},
    [65]={name='Smash Axe',effects={10},duration=2,tpDependent=true},
    [66]={name='Gale Axe',effects={130},duration=60,tpDependent=false},
    [80]={name='Shield Break',effects={148},duration=180,tpDependent=true},
    [83]={name='Armor Break',effects={149},duration=180,tpDependent=true},
    [85]={name='Weapon Break',effects={147},duration=180,tpDependent=true},
    [87]={name='Full Break',effects={147,149,146,148},duration=90,tpDependent=true},
    [99]={name='Nightmare Scythe',effects={5},duration=60,tpDependent=true},
    [102]={name='Guillotine',effects={6},duration=60,tpDependent=true},
    [115]={name='Leg Sweep',effects={10},duration=4,tpDependent=false},
    [129]={name='Blade: Retsu',effects={4},duration=30,tpDependent=true},
    [145]={name='Tachi: Hobaku',effects={10},duration=3,tpDependent=false},
    [150]={name='Tachi: Yukikaze',effects={5},duration=60,tpDependent=false},
    [151]={name='Tachi: Gekko',effects={6},duration=45,tpDependent=false},
    [152]={name='Tachi: Kasha',effects={4},duration=60,tpDependent=false},
    [162]={name='Brainshaker',effects={10},duration=2,tpDependent=true},
    [165]={name='Skullbreaker',effects={140},duration=140,tpDependent=false},
    [181]={name='Shell Crusher',effects={149},duration=180,tpDependent=true},
    [210]={name='Sniper Shot',effects={140},duration=140,tpDependent=false},
}
