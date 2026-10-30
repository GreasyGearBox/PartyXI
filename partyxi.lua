addon.name='partyxi'
addon.author='Mr.Bear'
addon.version='1.0.5'
addon.desc='Party frames, target and subtarget HUD, and personal TP arc for Ashita v4.'
require('common')
local imgui=require('imgui')
local ui=require('ui_compat')
local targetCast=require('target_cast')
local settings=require('settings')
local ffi=require('ffi')
local d3d=require('d3d8')
local model=require('model')
local targeting=require('targeting')
local targetBar=require('target_bar')
local subtargetBar=require('subtarget_bar')
local targetTracker=require('target_tracker')
local targetDrags={}
local data=require('data')
local view=require('view')
local visibility=require('visibility')
local menuPolicy=require('menu_policy')
local drain=require('arc_drain')
local protection=require('protection')
local defaults=T{subtargetX=550+(567.327-198)*1.159,subtargetY=120+16*1.159,subtargetScale=1.159,subtargetLocked=false,showTarget=true,targetX=550,targetY=120,targetScale=1.159,targetWidth=567.327,targetLocked=false,
    targetTimers=true,targetTimerSize=16.609,targetBuffs=true,targetNameSize=30.802,targetHPSize=27.426,targetInfoSize=18.386,targetLevel=true,targetAggro=true,targetLink=true,targetDetection=true,targetDistance=true,
    x=60,y=160,scale=1.081,nameTextSize=26.601,jobTextSize=21.456,distanceTextSize=21.051,hpTextSize=20.081,mpTextSize=19.129,locked=true,autoHide=true,showParty=true,
    menuAutoHideParty=true,menuHidePersonalTP=true,menuHideMode='selected',
    menuCategories=T{equipment=true,inventory=true,trade=true,auction=true,delivery=true,map=true},showGauge=true,
    gaugeX=650,gaugeY=220,gaugeScale=1.87,gaugeTextSize=26,gaugeAlways=false,
    partyTP=true,tpPulse=true,tpPulseSeconds=1.2,tpPulseStrength=2.607,
    gaugePulse=true,gaugePulseSeconds=1.8,gaugePulseStrength=2,drainEnabled=true,drainSeconds=1,highDrainSeconds=2,
    riseTime=0.3,riseTravel=70,effectStaleSeconds=13.189,effectOverrides=T{},showSAHats=true,
    protectionEnabled=true,shadowLossText=true,shadowAlertTextSize=30.647,shadowAlertX=500,shadowAlertY=250,protectionMembers=T{},protectionBlue=50,protectionRed=80,protectionRedSeconds=1.5}
local cfg=settings.load(defaults)
local configOpen=false
local menuState=menuPolicy.new()
local menuDebug=false
local menuDebugKey
local menuDetection={menu='',menuAvailable=false,status='Not sampled yet'}
local menuInfo={name='',kind='none'}
local function reportMenu(force)
    local key=menuInfo.name..'|'..menuDetection.status..'|'..menuInfo.kind
    if force or (menuDebug and key~=menuDebugKey) then
        print(string.format('[PartyXI menu] %s | %s | %s%s',
            menuInfo.name~='' and menuInfo.name or '<none>',menuInfo.kind,
            menuDetection.status,menuInfo.category and (' | '..menuInfo.category) or ''))
        menuDebugKey=key
    end
end
local font,assetsReady=nil,false
local boldFont
local textures={}
local drainState,previousTime,lastIdentity=nil,nil,nil
local progress=0
local partyTPStates={}
local personalTPStates={}
local protectionStates={}
local currentRoster={}
local dirty=false
local status='Waiting for character data'
local function save() settings.save();dirty=false end
local function sanitize()
    for _,key in ipairs{'targetTimers','targetBuffs','showTarget','targetLocked','targetLevel','targetAggro','targetLink','targetDetection','targetDistance'}do
        if cfg[key]==nil then cfg[key]=defaults[key]end
    end
    for _,entry in ipairs{{'targetX',0,20000},{'targetY',0,20000},{'targetScale',.35,2},
        {'targetWidth',300,800},{'targetNameSize',10,32},{'targetHPSize',10,32},{'targetInfoSize',10,24},{'targetTimerSize',10,20}}do
        local key=entry[1];cfg[key]=model.clamp(tonumber(cfg[key])or defaults[key],entry[2],entry[3])
    end
    if cfg.subtargetPositionVersion~=1 then
        cfg.subtargetX,cfg.subtargetY,cfg.subtargetScale=subtargetBar.initialPlacement(cfg)
        cfg.subtargetPositionVersion=1
    end
    for _,entry in ipairs{{'subtargetX',0,20000},{'subtargetY',0,20000},{'subtargetScale',.35,2}}do
        local key=entry[1];cfg[key]=model.clamp(tonumber(cfg[key])or defaults[key],entry[2],entry[3])
    end
    if cfg.subtargetLocked==nil then cfg.subtargetLocked=defaults.subtargetLocked end
    if cfg.targetLayoutVersion~=2 then
        cfg.targetNameSize=math.max(20,cfg.targetNameSize)
        cfg.targetInfoSize=math.max(16,cfg.targetInfoSize)
        cfg.targetLayoutVersion=2
    end
    -- One-time migration from releases whose factory setting was always-on.
    -- Subsequent user choices remain authoritative and are saved normally.
    if cfg.gaugeVisibilityDefaultVersion~=1 then
        cfg.gaugeAlways=false
        cfg.gaugeVisibilityDefaultVersion=1
    end
    if cfg.autoHide==nil then cfg.autoHide=true end
    if cfg.menuAutoHideParty==nil then cfg.menuAutoHideParty=true end
    if cfg.menuHidePersonalTP==nil then cfg.menuHidePersonalTP=defaults.menuHidePersonalTP end
    if cfg.menuHideMode~='all' then cfg.menuHideMode='selected' end
    cfg.menuCategories=type(cfg.menuCategories)=='table' and cfg.menuCategories or T{}
    for _,category in ipairs(menuPolicy.categories) do
        if cfg.menuCategories[category[1]]==nil then cfg.menuCategories[category[1]]=true end
    end
    cfg.scale=model.clamp(cfg.scale,.35,2)
    if cfg.castEnabled==nil then cfg.castEnabled=true end
    cfg.castDetached=cfg.castDetached==true
    cfg.castWidthPercent=model.clamp(cfg.castWidthPercent or 50,20,100)
    cfg.castWidth=model.clamp(cfg.castWidth or 240,100,800)
    cfg.castHeight=model.clamp(cfg.castHeight or 24,12,60)
    cfg.castTextSize=model.clamp(cfg.castTextSize or 14,10,36)
    cfg.castScale=model.clamp(cfg.castScale or 1,.35,3)
    cfg.castX=model.clamp(cfg.castX or cfg.targetX or 500,0,20000)
    cfg.castY=model.clamp(cfg.castY or ((cfg.targetY or 200)+150),0,20000)
    if cfg.playerCastEnabled==nil then cfg.playerCastEnabled=true end
    cfg.playerCastX=model.clamp(cfg.playerCastX or 600,0,20000)
    cfg.playerCastY=model.clamp(cfg.playerCastY or 650,0,20000)
    cfg.playerCastWidth=model.clamp(cfg.playerCastWidth or 300,100,800)
    cfg.playerCastHeight=model.clamp(cfg.playerCastHeight or 24,12,60)
    cfg.playerCastTextSize=model.clamp(cfg.playerCastTextSize or 14,10,36)
    cfg.playerCastScale=model.clamp(cfg.playerCastScale or 1,.35,3)
    cfg.detachSelf=cfg.detachSelf==true
    cfg.selfX=model.clamp(cfg.selfX or cfg.x,0,20000)
    cfg.selfY=model.clamp(cfg.selfY or (cfg.y+160),0,20000)
    cfg.selfScale=model.clamp(cfg.selfScale or cfg.scale,.35,2)
    cfg.jobTextSize=model.clamp(cfg.jobTextSize or defaults.jobTextSize,10,32)
    cfg.distanceTextSize=model.clamp(cfg.distanceTextSize or defaults.distanceTextSize,10,32)
    cfg.nameTextSize=model.clamp(cfg.nameTextSize or defaults.nameTextSize,10,32)
    cfg.hpTextSize=model.clamp(cfg.hpTextSize or defaults.hpTextSize,10,24)
    cfg.mpTextSize=model.clamp(cfg.mpTextSize or defaults.mpTextSize,10,24)
    cfg.gaugeScale=model.clamp(cfg.gaugeScale,.25,3)
    cfg.tpPulseSeconds=model.clamp(cfg.tpPulseSeconds,.3,3)
    cfg.tpPulseStrength=model.clamp(cfg.tpPulseStrength or defaults.tpPulseStrength,0,5)
    cfg.gaugePulseSeconds=model.clamp(cfg.gaugePulseSeconds or 1.8,.3,5)
    cfg.gaugePulseStrength=model.clamp(cfg.gaugePulseStrength or 2,0,5)
    cfg.gaugeTextSize=model.clamp(cfg.gaugeTextSize,14,48)
    cfg.drainSeconds=model.clamp(cfg.drainSeconds,0,5)
    cfg.highDrainSeconds=model.clamp(cfg.highDrainSeconds,0,5)
    cfg.riseTime=model.clamp(cfg.riseTime,.1,2)
    cfg.riseTravel=model.clamp(cfg.riseTravel,0,150)
    cfg.effectStaleSeconds=model.clamp(cfg.effectStaleSeconds,10,600)
    cfg.effectOverrides=cfg.effectOverrides or T{}
    cfg.showSAHats=cfg.showSAHats==true
    cfg.saOpacity=nil -- retired: countdown is always fully opaque
    cfg.emphasizeOwnHP=nil -- retired; discard saved preference
    cfg.protectionEnabled=cfg.protectionEnabled==true
    cfg.shadowLossText=cfg.shadowLossText==true
    cfg.shadowAlertTextSize=model.clamp(cfg.shadowAlertTextSize or 30.647,14,64)
    cfg.shadowAlertX=model.clamp(cfg.shadowAlertX or 500,0,20000)
    cfg.shadowAlertY=model.clamp(cfg.shadowAlertY or 250,0,20000)
    cfg.protectionMembers=cfg.protectionMembers or T{}
    cfg.protectionBlue=model.clamp(cfg.protectionBlue or defaults.protectionBlue,0,300)
    cfg.protectionRed=model.clamp(cfg.protectionRed or 80,0,300)
    cfg.protectionShellOpacity=model.clamp(cfg.protectionShellOpacity or 14,0,100)
    cfg.protectionShellGlow=model.clamp(cfg.protectionShellGlow or 100,0,500)
    cfg.protectionRedSeconds=model.clamp(cfg.protectionRedSeconds or 1.5,.3,4)
    for _,key in ipairs{'x','y','gaugeX','gaugeY'} do cfg[key]=model.clamp(cfg[key],0,20000) end
end
sanitize()
settings.register('settings','partyxi_settings',function(s) cfg=s;sanitize();data.clear();drainState=nil;partyTPStates={};personalTPStates={};protectionStates={} end)
local function assets()
    if assetsReady then return true end
    -- Use Windows' installed UI font without redistributing it; bundled OFL font is fallback.
    local path=os.getenv('WINDIR') or 'C:/Windows'
    local ok,f=pcall(imgui.AddFontFromFileTTF,path..'/Fonts/segoeui.ttf',24)
    if not ok or not f then ok,f=pcall(imgui.AddFontFromFileTTF,addon.path..'assets/Rajdhani-Bold.ttf',24) end
    if ok and f then font=f else font=imgui.GetFont() end
    local boldOK,bold=pcall(imgui.AddFontFromFileTTF,path..'/Fonts/segoeuib.ttf',24)
    if not boldOK or not bold then boldOK,bold=pcall(imgui.AddFontFromFileTTF,addon.path..'assets/Rajdhani-Bold.ttf',24) end
    boldFont=boldOK and bold or font
    assetsReady=true
    return true
end
local function texture(relative,effectId)
    -- PNG names are native DAT icon indices. Resolve effect IDs via the client's resource map.
    if effectId then
        local r=data.call(AshitaCore:GetResourceManager(),'GetStatusIconById',effectId)
        if r and r.Index then relative='status/'..tonumber(r.Index)..'.png' end
    end
    local cached=textures[relative]
    if cached~=nil then return cached.id end
    local file=io.open(addon.path..'assets/'..relative,'rb')
    if not file then textures[relative]={};return nil end
    file:close()
    local device=d3d.get_device()
    if not device then return nil end
    local ptr=ffi.new('IDirect3DTexture8*[1]')
    local rc=ffi.C.D3DXCreateTextureFromFileExA(device,addon.path..'assets/'..relative,
        0xFFFFFFFF,0xFFFFFFFF,1,0,ffi.C.D3DFMT_A8R8G8B8,ffi.C.D3DPOOL_MANAGED,1,1,0,nil,nil,ptr)
    local entry={}
    if rc==ffi.C.S_OK and ptr[0]~=nil then
        entry.owner=ffi.cast('IDirect3DTexture8*',ptr[0])
        entry.id=tonumber(ffi.cast('uint32_t',entry.owner))
    end
    textures[relative]=entry
    return entry.id
end
local flags=bit.bor(ImGuiWindowFlags_NoDecoration,ImGuiWindowFlags_NoBackground,
    ImGuiWindowFlags_NoSavedSettings,ImGuiWindowFlags_NoMove,
    ImGuiWindowFlags_NoScrollWithMouse,ImGuiWindowFlags_NoScrollbar)
local function beginWindow(id,x,y,w,h,allowConfigInput,passThrough)
    imgui.SetNextWindowPos({x,y},ImGuiCond_Always)
    imgui.SetNextWindowSize({w,h},ImGuiCond_Always)
    local windowFlags=flags
    if passThrough or (configOpen and not allowConfigInput) then windowFlags=bit.bor(windowFlags,ImGuiWindowFlags_NoInputs) end
    local visible=imgui.Begin(id,{true},windowFlags)
    return visible
end
local function moveActive(keyX,keyY,locked)
    if locked==nil then locked=cfg.locked end
    if not locked and imgui.IsItemActive() and imgui.IsMouseDragging(0) then
        local delta=imgui.GetIO().MouseDelta
        cfg[keyX]=math.max(0,cfg[keyX]+(delta.x or delta[1]))
        cfg[keyY]=math.max(0,cfg[keyY]+(delta.y or delta[2]))
        dirty=true
    end
    if dirty and not imgui.IsMouseDown(0) then save() end
end
local function drag(id,x,y,w,h,keyX,keyY,locked)
    imgui.SetCursorScreenPos({x,y});imgui.InvisibleButton(id,{w,h})
    moveActive(keyX,keyY,locked)
end
-- Settings UI: native ImGui layout only. No screen-space cursor or clip changes.
local function controls()
    if not configOpen then return end
    imgui.SetNextWindowSize({700,760},ImGuiCond_FirstUseEver)
    imgui.SetNextWindowPos({80,80},ImGuiCond_FirstUseEver)
    -- Explicit padding keeps widgets inside the clip rectangle even when the
    -- host theme uses zero window padding. Use a fresh ID to retire old geometry.
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding,{16,12})
    local open={true}
    if imgui.Begin('PartyXI settings###partyxi_settings_043',open,ImGuiWindowFlags_NoSavedSettings) then
        -- Keep the cursor inside the legacy host's left clip boundary.
        -- Unlike WindowPadding, Indent moves items without moving that boundary.
        imgui.Indent(24)
        local function toggle(label,key)
            local value={cfg[key]}
            if imgui.Checkbox(label,value) then cfg[key]=value[1];save() end
        end
        local function slider(label,key,lo,hi)
            imgui.TextWrapped(label)
            local value={cfg[key]}
            if imgui.SliderFloat('##'..key,value,lo,hi) then cfg[key]=value[1];save() end
        end
        local function pageControls(configPage)
            if configPage=='Player cast' then
                toggle('Show player cast bar','playerCastEnabled')
                slider('Player cast bar width','playerCastWidth',100,800)
                slider('Player cast bar height','playerCastHeight',12,60)
                slider('Player cast bar text size','playerCastTextSize',10,36)
                slider('Player cast bar scale','playerCastScale',.35,3)
                imgui.TextWrapped('Drag the player cast bar while settings are open to position it independently.')
                if imgui.Button('Reset player cast bar')then
                    cfg.playerCastX=600;cfg.playerCastY=650;cfg.playerCastWidth=300
                    cfg.playerCastHeight=24;cfg.playerCastTextSize=14;cfg.playerCastScale=1;save()
                end
            end
            if configPage=='Target' then
                toggle('Show target bar','showTarget')
                toggle('Show target cast bar','castEnabled')
                toggle('Detach target cast bar','castDetached')
                if cfg.castDetached then
                    slider('Cast bar width','castWidth',100,800)
                    slider('Cast bar scale','castScale',.35,3)
                else slider('Cast bar width (% of HP bar)','castWidthPercent',20,100)end
                slider('Cast bar height','castHeight',12,60)
                slider('Cast bar text size','castTextSize',10,36)
                if imgui.Button('Reset cast bar')then
                    cfg.castDetached=false;cfg.castWidthPercent=50;cfg.castWidth=240
                    cfg.castHeight=24;cfg.castTextSize=14;cfg.castScale=1
                    cfg.castX=cfg.targetX;cfg.castY=cfg.targetY+150;save()
                end
                toggle('Lock target position','targetLocked')
                slider('Target scale (portrait: 72 px at 100%)','targetScale',.35,2)
                slider('Target bar width','targetWidth',300,800)
                slider('Target name size','targetNameSize',10,32)
                slider('Target HP text size','targetHPSize',10,32)
                slider('Target information text size','targetInfoSize',10,24)
                toggle('Show mob level range','targetLevel')
                toggle('Show aggro / passive','targetAggro')
                toggle('Show linking','targetLink')
                toggle('Show detection methods','targetDetection')
                toggle('Show target distance','targetDistance')
                toggle('Show target buffs / debuffs','targetBuffs')
                toggle('Show estimated effect timers','targetTimers')
                slider('Effect timer text size','targetTimerSize',10,20)
                imgui.TextWrapped('Only observed effects are tracked. Timers show estimated remaining time; unknown durations stay blank. Effects applied before observation may be missing.')
                imgui.TextWrapped('Mob details use the existing ArcXI Phoenix snapshot. Not verified for CatsEye. Unknown values display ?. Hover the bar for full details.')
                imgui.TextWrapped('Drag the target name or HP pane to move it while unlocked.')
                if imgui.Button('Reset target position and scale')then cfg.targetX=defaults.targetX;cfg.targetY=defaults.targetY;cfg.targetScale=defaults.targetScale;save()end
                imgui.Separator()
                imgui.Text('Subtarget')
                toggle('Lock subtarget position','subtargetLocked')
                slider('Subtarget scale','subtargetScale',.35,2)
                slider('Subtarget position X','subtargetX',0,20000)
                slider('Subtarget position Y','subtargetY',0,20000)
                imgui.TextWrapped('Unlock and drag the subtarget name or HP bar to move it independently.')
                if imgui.Button('Reset subtarget position and scale')then
                    cfg.subtargetX,cfg.subtargetY,cfg.subtargetScale=subtargetBar.initialPlacement(cfg);save()
                end
            end
            if configPage=='Party' then
                toggle('Show party','showParty')
                toggle('Hide during cutscenes / native UI hidden','autoHide')
                toggle('Lock positions','locked')
                slider('Party scale','scale',.35,2)
                toggle('Detach own player frame','detachSelf')
                if cfg.detachSelf then
                    slider('Own frame scale','selfScale',.35,2)
                    imgui.TextWrapped('Drag your own name while settings are open to move your frame independently.')
                    if imgui.Button('Reset own frame position')then
                        cfg.selfX=cfg.x;cfg.selfY=cfg.y+160;cfg.selfScale=cfg.scale;save()
                    end
                end
                slider('Player name size','nameTextSize',10,32)
                slider('Job text size','jobTextSize',10,32)
                slider('Distance text size','distanceTextSize',10,32)
                slider('HP text size','hpTextSize',10,24)
                slider('MP text size','mpTextSize',10,24)
                imgui.Separator()
                toggle('Three TP bars on each party frame','partyTP')
                toggle('Pulse gold while party TP is ready','tpPulse')
                slider('Party TP repeating pulse period (seconds)','tpPulseSeconds',.3,3)
                slider('Party TP pulse strength (0-5x)','tpPulseStrength',0,5)
            end
            if configPage=='Personal TP' then
                toggle('Large detachable TP arc','showGauge')
                toggle('Always show personal TP arc','gaugeAlways')
                slider('Large TP scale','gaugeScale',.25,3)
                slider('TP text size','gaugeTextSize',14,48)
                imgui.Separator()
                toggle('Large TP arc pulse at 1000','gaugePulse')
                slider('Large TP pulse strength (0-5x)','gaugePulseStrength',0,5)
                slider('Large TP pulse seconds','gaugePulseSeconds',.3,5)
                imgui.Separator()
                toggle('Drain animation','drainEnabled')
                slider('Drain seconds','drainSeconds',0,5)
                slider('Drain above 2000 TP','highDrainSeconds',0,5)
                slider('Appear seconds','riseTime',.1,2)
                slider('Appear travel','riseTravel',0,150)
            end
            if configPage=='Effects' then
                slider('Discard old party effects after seconds','effectStaleSeconds',10,600)
                toggle('Show SA cooldown on hats','showSAHats')
                imgui.Separator()
                toggle('Shadow Tracking (Utsusemi / Third Eye)','protectionEnabled')
                if cfg.protectionEnabled then
                    toggle('Separate red -PLAYERNAME shadow-loss alert','shadowLossText')
                    if cfg.shadowLossText then
                        slider('Shadow-loss text size','shadowAlertTextSize',14,64)
                    end
                    slider('Blue shield intensity (%)','protectionBlue',0,300)
                    slider('Red shield intensity (%)','protectionRed',0,300)
                    slider('Shield shell opacity (%)','protectionShellOpacity',0,100)
                    slider('Shield glow strength (%)','protectionShellGlow',0,500)
                    imgui.TextWrapped('Automatically tracks observed Utsusemi and Third Eye for all party members.')
                end
            end
            if configPage=='Menus' then
                toggle('Auto-hide party frames during menus','menuAutoHideParty')
                toggle('Also hide personal TP arc','menuHidePersonalTP')
                imgui.Text('Mode: '..(cfg.menuHideMode=='all' and 'All noncombat menus' or 'Selected obstructing menus'))
                if imgui.Button('Selected obstructing menus') then cfg.menuHideMode='selected';save() end
                if imgui.Button('All noncombat menus') then cfg.menuHideMode='all';save() end
                if cfg.menuHideMode=='selected' then
                    for _,category in ipairs(menuPolicy.categories) do
                        local value={cfg.menuCategories[category[1]]}
                        if imgui.Checkbox(category[2],value) then cfg.menuCategories[category[1]]=value[1];save() end
                    end
                end
                imgui.Separator()
                imgui.TextWrapped(menuDetection.status)
                imgui.Text('Menu: '..(menuInfo.name~='' and menuInfo.name or '<none>'))
                imgui.Text('Classification: '..menuInfo.kind)
                imgui.Text('/partyxi menudebug: report menu changes')
            end
        end
        -- Native tabs and a scrolling child follow the installed Points and
        -- LuAshitacast settings menus. No manual cursor or clip manipulation.
        if imgui.BeginTabBar('##partyxi_settings_tabs',ImGuiTabBarFlags_NoCloseWithMiddleMouseButton) then
            for _,page in ipairs{'Party','Target','Player cast','Personal TP','Effects','Menus'} do
                if imgui.BeginTabItem(page..'##config_page') then
                    ui.beginChild(imgui,'##partyxi_settings_content_'..page,{0,-40})
                    imgui.Indent(24)
                    pageControls(page)
                    imgui.Unindent(24)
                    imgui.EndChild()
                    imgui.EndTabItem()
                end
            end
            imgui.EndTabBar()
        end
        if imgui.Button('Reset positions and scale') then
            cfg.x=defaults.x;cfg.y=defaults.y;cfg.scale=defaults.scale;cfg.gaugeX=defaults.gaugeX;cfg.gaugeY=defaults.gaugeY;cfg.gaugeScale=defaults.gaugeScale;save()
        end
        imgui.SameLine()
        if imgui.Button('Close') then open[1]=false end
        imgui.Unindent(24)
    end
    imgui.End()
    imgui.PopStyleVar()
    configOpen=open[1]
end
-- Font atlas changes must happen outside a render frame on Phoenix Ashita.
ashita.events.register('load','partyxi_load',assets)
ashita.events.register('d3d_present','partyxi_present',function()
    if not assetsReady then return end
    local now=imgui.GetTime()
    local dt=math.min(.1,math.max(0,now-(previousTime or now)));previousTime=now
    local identity=data.call(AshitaCore:GetMemoryManager():GetParty(),'GetMemberServerId',0)
    if identity~=lastIdentity then data.clear();drainState=nil;partyTPStates={};personalTPStates={};protectionStates={};progress=0;lastIdentity=identity end
    local roster=data.sample(now,cfg)
    protectionStates=protection.update(protectionStates,roster,now,cfg)
    currentRoster=roster
    protection.ready(roster,now,cfg.tpPulseSeconds,cfg.tpPulse)
    status=(#roster>0 and 'Live party data' or 'Waiting for character data / zoning')
    menuDetection=visibility.sample()
    local menuPartyHidden,menuArcHidden
    menuState,menuPartyHidden,menuArcHidden,menuInfo=menuPolicy.update(
        menuState,menuDetection.menu,menuDetection.menuAvailable,now,cfg,false)
    reportMenu(false)
    local systemHidden=cfg.autoHide and (menuDetection.event or menuDetection.interface or (#roster==0))
    local me=roster[1]
    local personal=me and {id=me.id,tp=me.tp,available=me.available} or nil
    personalTPStates=model.partyTP(personalTPStates,personal and {personal} or {},now,cfg.gaugePulseSeconds,cfg.gaugePulse)
    local arcTrail
    if me and me.available and me.tp~=nil then
        local entity=GetPlayerEntity()
        local shown=configOpen or cfg.gaugeAlways or (entity and entity.Status==1)
        progress=model.clamp(progress+(shown and 1 or -1)*dt/cfg.riseTime,0,1)
        arcTrail,drainState=drain.value(drainState,me.tp,now,cfg.drainSeconds,cfg.drainEnabled,cfg.highDrainSeconds)
    else drainState=nil;progress=0 end
    ui.pushFont(imgui,font,24)
    local showHeader=false
    local groups={}
    local stacked={}
    for _,member in ipairs(roster)do
        if cfg.detachSelf and member.slot==0 then
            groups[#groups+1]={members={member},own=true}
        else stacked[#stacked+1]=member end
    end
    if #stacked>0 then groups[#groups+1]={members=stacked,own=false}end
    for _,group in ipairs(groups)do
    local frameRoster=group.members
    local h=view.height(frameRoster,showHeader,cfg)
    if cfg.showParty and not systemHidden and not menuPartyHidden then
        local s,x,y=cfg.scale,cfg.x,cfg.y
        local keyX,keyY='x','y'
        if group.own then s=cfg.selfScale;x=cfg.selfX;y=cfg.selfY;keyX='selfX';keyY='selfY'end
        local margin=(cfg.protectionEnabled or (cfg.partyTP and cfg.tpPulse))and view.glowMargin*s or 0
        local windowId=group.own and 'Own player###partyxi_self' or 'PartyXI###partyxi_frame'
        if beginWindow(windowId,x-margin,y-margin,model.partyWidth(frameRoster)*s+2*margin,h*s+2*margin,true) then
            local function hit(id,a,b,w,hh,member)
                imgui.SetCursorScreenPos({x+a*s,y+b*s})
                local clicked=imgui.InvisibleButton(id,{w*s,hh*s})
                if member then
                    if imgui.IsItemActive() and imgui.IsMouseDragging(0) then targetDrags[id]=true end
                    if clicked and not configOpen and not targetDrags[id] then targeting.select(member,AshitaCore) end
                    if not imgui.IsMouseDown(0) then targetDrags[id]=nil end
                end
                if id=='name'..frameRoster[1].id then moveActive(keyX,keyY,not configOpen and cfg.locked) end
                return imgui.IsItemHovered()
            end
            view.party(imgui,imgui.GetWindowDrawList(),x,y,s,frameRoster,font,texture,hit,false,cfg.partyTP,showHeader,cfg.tpPulseStrength,cfg,boldFont)
            -- Small padlock in the unused area immediately left of the name.
            local lx,ly=x+52*s,y
            local dl=imgui.GetWindowDrawList()
            local color=cfg.locked and 0xFFBBBBBB or 0xFF78CFF0
            dl:AddRect({lx,ly},{lx+20*s,ly+20*s},0x99504030,3*s,0,s)
            dl:AddRect({lx+5*s,ly+9*s},{lx+15*s,ly+17*s},color,1*s,0,s)
            local offset=cfg.locked and 0 or 3*s
            dl:AddLine({lx+7*s+offset,ly+9*s},{lx+7*s+offset,ly+4*s},color,1.5*s)
            dl:AddLine({lx+7*s+offset,ly+4*s},{lx+13*s+offset,ly+4*s},color,1.5*s)
            dl:AddLine({lx+13*s+offset,ly+4*s},{lx+13*s+offset,ly+(cfg.locked and 9 or 6)*s},color,1.5*s)
            imgui.SetCursorScreenPos({lx,ly})
            imgui.InvisibleButton(group.own and 'self_lock' or 'party_lock',{20*s,20*s})
            if imgui.IsItemClicked(0) then cfg.locked=not cfg.locked;save() end
            if imgui.IsItemHovered() then imgui.SetTooltip(cfg.locked and 'Locked: click to unlock' or 'Unlocked: drag your name to move; click to lock') end
        end
        imgui.End()
    end
    end
    if arcTrail and cfg.showGauge and progress>0 and not systemHidden and not menuArcHidden then
        local s=cfg.gaugeScale
        -- Keep the drawing anchor unchanged while moving native padding and
        -- its clip boundary outside the artwork and TP number.
        local margin=math.max(32,32*s)
        local height=math.max(370,346+cfg.gaugeTextSize+8)*s
        if beginWindow('TP###partyxi_tp',cfg.gaugeX-margin,cfg.gaugeY-margin,130*s+2*margin,height+2*margin,true) then
            view.gauge(imgui.GetWindowDrawList(),cfg.gaugeX,cfg.gaugeY,s,me.tp,arcTrail,progress,cfg.riseTravel,boldFont or font,cfg.gaugeTextSize,personal.tpPulse,cfg.gaugePulseStrength)
            drag('tp_drag',cfg.gaugeX,cfg.gaugeY,130*s,370*s,'gaugeX','gaugeY',not configOpen and cfg.locked)
        end
        imgui.End()
    end
    if cfg.protectionEnabled and cfg.shadowLossText and not systemHidden and not menuPartyHidden then
        local labels={}
        for _,m in ipairs(roster) do
            if m.protection and m.protection.shadowLost then labels[#labels+1]='-'..m.name end
        end
        if #labels==0 and (configOpen) then
            labels[1]='-PLAYERNAME (positioning)'
        end
        if #labels>0 then
            local width=80
            for _,label in ipairs(labels) do
                local measured=imgui.CalcTextSize(label)
                if type(measured)~='number' then measured=measured.x or measured[1] end
                width=math.max(width,measured*cfg.shadowAlertTextSize/24+8)
            end
            local x,y=cfg.shadowAlertX,cfg.shadowAlertY
            local height=#labels*(cfg.shadowAlertTextSize+6)
            local positioning=configOpen
            -- Draw inside the actual native content area. Drawing at the
            -- requested window origin clips against padding, and ignores any
            -- ImGui repositioning when the window approaches a screen edge.
            if beginWindow('Shadow loss###partyxi_shadow_loss',x,y,width+32,height+32,true,not positioning) then
                local drawX,drawY=imgui.GetCursorScreenPos()
                if type(drawX)=='table' or type(drawX)=='userdata' then
                    local pos=drawX;drawX=pos.x or pos[1];drawY=pos.y or pos[2]
                end
                if type(drawX)~='number' or type(drawY)~='number' then drawX=x+16;drawY=y+16 end
                view.shadowAlerts(imgui.GetWindowDrawList(),labels,drawX,drawY,font,cfg.shadowAlertTextSize)
                if positioning then drag('shadow_alert_drag',drawX,drawY,width,height,'shadowAlertX','shadowAlertY',false) end
            end
            imgui.End()
        end
    end
    local target=cfg.showTarget and not systemHidden and not menuPartyHidden and targetBar.sample(AshitaCore) or nil
    if target then
        targetTracker.prune(now)
        if not target.subtarget then target.subtarget=targetBar.actionTarget(AshitaCore,target,targetTracker,now) end
        target.buffs=targetTracker.list(target.id,now)
        target.buffsKnown=false
        for _,member in ipairs(roster)do
            if member.id==target.id and member.effectsKnown then
                target.buffs={}
                for _,id in ipairs(member.good)do target.buffs[#target.buffs+1]=id end
                for _,id in ipairs(member.bad)do target.buffs[#target.buffs+1]=id end
                target.buffsKnown=true;break
            end
        end
        target.remaining={}
        for _,id in ipairs(target.buffs)do
            local seconds=targetTracker.remaining(target.id,id,now)
            if seconds and seconds>0 then target.remaining[id]=seconds end
        end
        local s,x,y=cfg.targetScale,cfg.targetX,cfg.targetY
        local margin=math.max(32,32*s)
        local cast=cfg.castEnabled and (targetCast.get(target.id,now) or (configOpen and {name='Spell / Ability',kind=8,started=now})) or nil
        if (target.hpp or 0)<=0 then targetCast.clear(target.id);cast=nil end
        target.castExtra=0
        local height=targetBar.height(cfg,target.castExtra)
        if beginWindow('Target###partyxi_target',x-margin,y-margin,cfg.targetWidth*s+2*margin,height*s+2*margin,true)then
            local wx,wy=imgui.GetWindowPos()
            if type(wx)=='table' or type(wx)=='userdata' then local pos=wx;wx=pos.x or pos[1];wy=pos.y or pos[2]end
            if type(wx)=='number'and type(wy)=='number'then x=wx+margin;y=wy+margin end
            targetBar.draw(imgui,imgui.GetWindowDrawList(),x,y,target,font,cfg,texture,boldFont)
            drag('target_move',x+80*s,y,(cfg.targetWidth-80)*s,height*s,'targetX','targetY',cfg.targetLocked)
            if cast and not cfg.castDetached then
                local cx,cy,cw,ch,cs=targetCast.geometry(cfg,x,y)
                targetCast.draw(imgui,imgui.GetWindowDrawList(),cx,cy,cw,ch,cs,target and target.id==identity and targetCast.withNative(cast,AshitaCore:GetMemoryManager()) or cast,font,cfg,now)
            end
        end
        imgui.End()
    end
    local sub=target and target.subtarget
    if cfg.castEnabled and cfg.castDetached and not systemHidden and not menuPartyHidden then
        local cast=target and (target.hpp or 0)>0 and targetCast.get(target.id,now) or nil
        if not cast and configOpen then cast={name='Spell / Ability',kind=8,started=now}end
        if cast then
            local cx,cy,cw,ch,cs=targetCast.geometry(cfg,0,0)
            if beginWindow('Cast###partyxi_cast',cx-32,cy-32,cw*cs+64,ch*cs+64,true,not configOpen)then
                targetCast.draw(imgui,imgui.GetWindowDrawList(),cx,cy,cw,ch,cs,target and target.id==identity and targetCast.withNative(cast,AshitaCore:GetMemoryManager()) or cast,font,cfg,now)
                if configOpen then drag('cast_move',cx,cy,cw*cs,ch*cs,'castX','castY',false)end
            end
            imgui.End()
        end
    end
    if cfg.showTarget and not systemHidden and not menuPartyHidden and (sub or configOpen) then
        local display=sub or {name='Subtarget',hpp=100}
        local s,x,y=cfg.subtargetScale,cfg.subtargetX,cfg.subtargetY
        local margin=math.max(32,32*s)
        if beginWindow('Subtarget###partyxi_subtarget',x-margin,y-margin,subtargetBar.width*s+2*margin,subtargetBar.height*s+2*margin,true)then
            local wx,wy=imgui.GetWindowPos()
            if type(wx)=='table' or type(wx)=='userdata'then local pos=wx;wx=pos.x or pos[1];wy=pos.y or pos[2]end
            if type(wx)=='number' and type(wy)=='number'then x=wx+margin;y=wy+margin end
            subtargetBar.draw(imgui,imgui.GetWindowDrawList(),x,y,display,font,s)
            drag('subtarget_move',x,y,subtargetBar.width*s,subtargetBar.height*s,'subtargetX','subtargetY',cfg.subtargetLocked)
        end
        imgui.End()
    end
    if cfg.playerCastEnabled and not systemHidden and not menuPartyHidden then
        local cast=targetCast.withNative(targetCast.get(identity,now),AshitaCore:GetMemoryManager())
        if not cast and configOpen then cast={name='Your spell / ability',kind=8,started=now-1.5,duration=3}end
        if cast then
            local cx,cy=cfg.playerCastX,cfg.playerCastY
            local cw,ch,cs=cfg.playerCastWidth,cfg.playerCastHeight,cfg.playerCastScale
            if beginWindow('Player cast###partyxi_player_cast',cx-32,cy-32,cw*cs+64,ch*cs+64,true,not configOpen)then
                targetCast.draw(imgui,imgui.GetWindowDrawList(),cx,cy,cw,ch,cs,cast,font,{castTextSize=cfg.playerCastTextSize},now)
                if configOpen then drag('player_cast_move',cx,cy,cw*cs,ch*cs,'playerCastX','playerCastY',false)end
            end
            imgui.End()
        end
    end
    imgui.PopFont()
    -- Render settings after all custom draw-list work, with the normal UI font.
    controls()
end)
ashita.events.register('packet_in','partyxi_effects',function(e)
    if not e.injected then targetBar.observePlayer(e.id,e.data_modified or e.data) end
    if not e.injected and e.id==0x028 and e.data_raw and e.size then
        local ok,action=pcall(targetTracker.parse,e,ashita.bits.unpack_be)
        if ok then
            local now=imgui.GetTime()
            targetTracker.observe(action,now)
            local resourceOK,resources=pcall(function()return AshitaCore:GetResourceManager()end)
            targetCast.observe(action,now,resourceOK and resources or nil)
        end
    end
    if not e.injected and e.id==0x029 then
        local packet=e.data_modified or e.data
        if type(packet)=='string'and #packet>=26 then
            local function uint(at,n)local v=0;for i=0,n-1 do v=v+packet:byte(at+i)*256^i end;return v end
            local actor,message=uint(9,4),uint(25,2)%32768
            targetTracker.message(actor,uint(13,4),message)
            if message==6 or message==20 or message==97 or message==113 or message==406 or message==605 then targetCast.clear(actor)end
        end
    end
    if e.id==0x00A or e.id==0x00B then targetCast.reset();targetTracker.reset();data.clear();drainState=nil;progress=0;partyTPStates={};personalTPStates={};protectionStates={}
    elseif e.id==0x0DD then data.clearEffects() end
    if e.id==0x076 and not e.injected then data.packet(e.data_modified or e.data,imgui.GetTime()) end
    if e.id==0x028 and not e.injected and cfg.showSAHats then
        data.observeSA(e,imgui.GetTime(),cfg,ashita.bits.unpack_be)
    end
end)
ashita.events.register('command','partyxi_command',function(e)
    local args=e.command:args()
    local command=args[1] and args[1]:lower()
    if command~='/partyxi' and command~='/pxi' then return end
    e.blocked=true
    local cmd=(args[2] or 'config'):lower()
    if cmd=='config' then configOpen=not configOpen
    elseif cmd=='menudebug' then
        menuDebug=not menuDebug;menuDebugKey=nil
        menuDetection=visibility.sample()
        local kind,category,name=menuPolicy.classify(menuDetection.menu)
        menuInfo={kind=kind,category=category,name=name}
        print('[PartyXI menu] change reporting '..(menuDebug and 'ON' or 'OFF'))
        if menuDebug then reportMenu(true) end
    elseif cmd=='lock' or cmd=='unlock' then cfg.locked=cmd=='lock';save()
    elseif cmd=='scale' and tonumber(args[3]) then cfg.scale=model.clamp(tonumber(args[3])/100,.35,2);save()
    elseif cmd=='position' and tonumber(args[3]) and tonumber(args[4]) then cfg.x=tonumber(args[3]);cfg.y=tonumber(args[4]);sanitize();save()
    elseif cmd=='effect' and tonumber(args[3]) and ({buff=true,debuff=true,auto=true})[args[4]] then
        cfg.effectOverrides[tostring(tonumber(args[3]))]=args[4]~='auto' and args[4] or nil;save()
    else print('[PartyXI] /pxi (or /partyxi) [config|menudebug|lock|unlock|scale 68|position X Y|effect ID buff/debuff/auto]') end
end)
ashita.events.register('unload','partyxi_unload',function()
    save()
    for _,t in pairs(textures) do if t.owner then t.owner:Release();t.owner=nil end end
end)
