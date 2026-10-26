-- Menu names/exclusions informed by XIUI core/gamestate.lua (MIT).
-- Copyright (c) 2023 tirem [github.com/tirem]. See licenses/XIUI-MIT.txt.
-- Resource evidence and limitations: MENU-EVIDENCE.json and MENU-HIDING.md.
local M={}
M.categories={
    {'equipment','Equipment / check'}, {'inventory','Inventory / storage'},
    {'trade','Player / NPC trade'}, {'auction','Auction house'},
    {'delivery','Delivery / send boxes'}, {'map','Map'},
}
function M.normalize(raw)
    if type(raw)~='string' then return '' end
    local name=(raw:match('^[^%z]*') or ''):lower():gsub('^%s+',''):gsub('%s+$','')
    return (name:gsub('^menu%s+',''):gsub('%s+$',''))
end
local combat={}
for name in ('inline playermo chatctrl magselec magic abiselec ability mount '
    ..'mcr1pall mcr2pall mcr1long mcr2long targetwi targetlo attackmo battlemo normalmo '
    ..'abimenu mgcmenu cmbmenu mp_mnabi mp_abisc mp_mncst mp_cstm mp_kncst '
    ..'magiconw magico2w magicon mgcsortw abisortw'):gmatch('%S+') do combat[name]=true end
for i=1,9 do combat['actionm'..i]=true end
combat.actiom10=true
local categories={}
local function add(category,names)
    for name in names:gmatch('%S+') do categories[name]=category end
end
-- Exact client resource headers, not broad substring tests.
add('equipment','equip inspect pupequip')
add('inventory','inventor storage storage2 itmstora mnstorag bank bankmenu mogcont')
add('trade','trade trddummy handover evitem evitem01')
add('auction','auc1 auc2 auc3 auc4 aucammo aucarmor aucfood auchisto aucitem auclist aucmagic aucmater aucmeals aucweapo aucyn')
add('delivery','delivery post1 post2 mogpost rmpost')
add('map','map0 mapframe maplist mapscan mapv1 mapv2 mapv3 mapat maphp mapsg')
-- These generic panels only inherit an already observed obstructing category.
local shared={}
for name in ('ok yesno query numctrl money moneyctr sortyn itmsortw itmsort2 '
    ..'itemctrl iteminfo itemxinf itemyinf itemxinfo item4inf item5inf item6inf '
    ..'item7inf item8inf item9inf item10in item11in item12in itemx4in itemx5in '
    ..'itemx6in itemx7in itemx8in itemx9in itemx10i itemx11i itemx12i'):gmatch('%S+') do shared[name]=true end
function M.classify(raw)
    local name=M.normalize(raw)
    if name=='' then return 'none',nil,name end
    if combat[name] then return 'combat',nil,name end
    if categories[name] then return 'selected',categories[name],name end
    if shared[name] then return 'shared',nil,name end
    return 'other',nil,name
end
function M.new() return {untilTime=0} end
local function enabled(cfg,category)
    return cfg.menuCategories==nil or cfg.menuCategories[category]~=false
end
-- Hide immediately; bridge up to 150 ms of an empty menu during submenu swaps.
-- Combat menus and detector failures ALWAYS restore immediately.
function M.update(state,raw,available,now,cfg,override)
    state=state or M.new()
    local kind,category,name=M.classify(raw)
    local active=false
    if available and not override and cfg.menuAutoHideParty~=false and kind~='combat' then
        if cfg.menuHideMode=='all' then
            active=kind~='none'
        elseif category then active=enabled(cfg,category)
        elseif kind=='shared' and state.category then
            category=state.category;active=enabled(cfg,category)
        end
        if active then
            state.untilTime=now+.15;state.category=category
        elseif kind=='none' and now<state.untilTime and
            (cfg.menuHideMode=='all' or (state.category and enabled(cfg,state.category))) then
            active=true
        end
    end
    if not active then state.untilTime=0;state.category=nil end
    return state,active,active and cfg.menuHidePersonalTP==true,{
        name=name,kind=kind,category=category,available=available==true,
    }
end
return M
