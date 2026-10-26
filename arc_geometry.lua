-- ArcUI: independent geometry and resource math. No game dependencies.
local M = {}
function M.clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function M.lowHP(previous,current)
    return previous~=nil and previous>=.25 and current<.25
end
function M.tp(v)
    v = M.clamp(tonumber(v) or 0, 0, 3000)
    return {M.clamp(v / 1000, 0, 1), M.clamp((v - 1000) / 1000, 0, 1), M.clamp((v - 2000) / 1000, 0, 1)}
end
-- Circular centerlines with arc-length fills and tapered ribbon widths.
function M.circle(cx,cy,r,startAngle,endAngle,width,count)
    local out={length=r*math.abs(endAngle-startAngle),circle={x=cx,y=cy,r=r,startAngle=startAngle,endAngle=endAngle}}
    for i=0,count do
        local t=i/count
        local angle=startAngle+(endAngle-startAngle)*t
        local nx,ny=math.cos(angle),math.sin(angle)
        out[#out+1]={x=cx+r*nx,y=cy+r*ny,nx=nx,ny=ny,
            w=width*math.max(0,math.sin(math.pi*t))^0.55,distance=out.length*t}
    end
    return out
end
function M.paths(scale)
    -- Same overall height and reach; mirrored HP keeps the main arcs balanced.
    local r=(70*70+170*170)/140
    local cx=280-r
    local angle=math.asin(170/r)
    local count=math.max(120,math.ceil(r*angle*2*(scale or 1)/2))
    local tp=M.circle(cx,0,r,angle,-angle,11,count)
    local hp=M.circle(-cx,0,r,math.pi-angle,math.pi+angle,11,count)
    -- Concentric circular arcs: fixed radial separation, centered shorter spans.
    -- Arc length is exactly 80% / 60% of the primary, despite larger radii.
    local gap=4 -- Smaller than the primary's maximum width (11).
    local function parallel(parentRadius,width,fraction)
        local radius=parentRadius
        local halfAngle=angle*r*fraction/radius
        return M.circle(cx,0,radius,halfAngle,-halfAngle,width,count)
    end
    local secondRadius=r+11/2+gap+7/2
    local thirdRadius=secondRadius+7/2+gap+4.5/2
    local second=parallel(secondRadius,7,.8)
    local third=parallel(thirdRadius,4.5,.6)
    return {hp=hp,tp=tp,second=second,third=third}
end
-- Interpolate an exact fill cut within its sampled centerline segment.
function M.sample(path,t)
    t=M.clamp(t,0,1)
    local u=t*(#path-1)
    local i=math.min(#path-1,math.floor(u)+1)
    local f=u-(i-1)
    local a,b=path[i],path[i+1]
    local function lerp(k)return a[k]+(b[k]-a[k])*f end
    return {x=lerp('x'),y=lerp('y'),nx=lerp('nx'),ny=lerp('ny'),w=(t==0 or t==1) and 0 or lerp('w'),t=t}
end
local function unit(x,y)
    local length=math.sqrt(x*x+y*y)
    if length<1e-12 then return 0,0 end
    return x/length,y/length
end
local function alpha(c)return math.floor(c/16777216)%256 end
local function withAlpha(c,a)return c%16777216+math.floor(a)*16777216 end
-- Composite pulse into the core color before drawing: no overlapping pulse triangles.
local function over(base,front)
    local a=alpha(front)/255;local b=alpha(base)/255
    local out=a+b*(1-a)
    if out==0 then return 0 end
    local color=math.floor(out*255+.5)*16777216
    for channel=0,2 do
        local divisor=256^channel
        local f=math.floor(front/divisor)%256;local v=math.floor(base/divisor)%256
        color=color+math.floor((f*a+v*b*(1-a))/out+.5)*divisor
    end
    return color
end
-- One indexed strip, partitioned only at exact color cuts. Each longitudinal row
-- has six vertices: transparent halo, feather, core L/R, feather, transparent halo.
-- No edge fringe at internal color boundaries; adjacent runs share positions there.
function M.ribbon(path,x,y,scale,fill,trail,pulse)
    fill=M.clamp(fill,0,1);trail=math.max(fill,M.clamp(trail,0,1))
    pulse=pulse or {alpha=0,haloAlpha=0,spread=0}
    local cuts={0,1,fill,trail}
    for i=1,#path-2 do cuts[#cuts+1]=i/(#path-1) end
    table.sort(cuts)
    local rows={}
    for _,t in ipairs(cuts) do
        if not rows[#rows] or math.abs(t-rows[#rows].t)>1e-12 then
            local a=M.sample(path,t)
            a.cx=x+(a.x-204)*scale;a.cy=y+(a.y+170)*scale
            local nx,ny=unit(a.nx,a.ny)
            a.lx=a.cx+nx*a.w*scale*.5;a.ly=a.cy+ny*a.w*scale*.5
            a.rx=a.cx-nx*a.w*scale*.5;a.ry=a.cy-ny*a.w*scale*.5
            rows[#rows+1]=a
        end
    end
    for i,a in ipairs(rows) do
        -- Normals depend on the curve, not on where TP/trail cuts were inserted.
        local prev=M.sample(path,math.max(0,a.t-1/(#path-1)))
        local next=M.sample(path,math.min(1,a.t+1/(#path-1)))
        for _,point in ipairs{prev,next} do
            point.cx=x+(point.x-204)*scale;point.cy=y+(point.y+170)*scale
            local nx,ny=unit(point.nx,point.ny)
            point.lx=point.cx+nx*point.w*scale*.5;point.ly=point.cy+ny*point.w*scale*.5
            point.rx=point.cx-nx*point.w*scale*.5;point.ry=point.cy-ny*point.w*scale*.5
        end
        if i==1 or i==#rows then
            local nx,ny=unit(next.cx-prev.cx,next.cy-prev.cy)
            local sign=i==1 and -1 or 1
            a.lnx=nx*sign;a.lny=ny*sign;a.rnx=a.lnx;a.rny=a.lny
        else
            local tx,ty=next.lx-prev.lx,next.ly-prev.ly
            local nx,ny=unit(-ty,tx)
            if nx*a.nx+ny*a.ny<0 then nx=-nx;ny=-ny end
            a.lnx=nx;a.lny=ny
            tx,ty=next.rx-prev.rx,next.ry-prev.ry
            nx,ny=unit(-ty,tx)
            if nx*a.nx+ny*a.ny>0 then nx=-nx;ny=-ny end
            a.rnx=nx;a.rny=ny
        end
    end
    local mesh={vertices={},indices={},rows=rows,fill=fill,trail=trail}
    local function vertex(px,py,col)
        mesh.vertices[#mesh.vertices+1]={x=px,y=py,col=col}
        return #mesh.vertices-1
    end
    local function triangle(a,b,c)
        local va,vb,vc=mesh.vertices[a+1],mesh.vertices[b+1],mesh.vertices[c+1]
        local area=(vb.x-va.x)*(vc.y-va.y)-(vb.y-va.y)*(vc.x-va.x)
        if math.abs(area)<1e-12 then return end
        if area<0 then b,c=c,b end -- One positive winding, including the tip fans.
        local idx=mesh.indices;idx[#idx+1]=a;idx[#idx+1]=b;idx[#idx+1]=c
    end
    local function row(a,kind)
        local core=kind==1 and 0xFFF0CF78 or kind==2 and 0xFF999999 or 0xB04B443B
        if kind==1 then core=over(core,(pulse.alpha or 0)*16777216+0x00FFF5D8) end
        local halo=kind==1 and (pulse.haloAlpha or 0) or 0
        local feather=withAlpha(halo>0 and 0x00FFF5D8 or core,halo)
        local outer=.75+(pulse.spread or 0)*scale*.5
        return {
            vertex(a.lx+a.lnx*outer,a.ly+a.lny*outer,withAlpha(feather,0)),
            vertex(a.lx+a.lnx*.75,a.ly+a.lny*.75,feather),
            vertex(a.lx,a.ly,core),vertex(a.rx,a.ry,core),
            vertex(a.rx+a.rnx*.75,a.ry+a.rny*.75,feather),
            vertex(a.rx+a.rnx*outer,a.ry+a.rny*outer,withAlpha(feather,0))}
    end
    local previous,previousKind
    for i=1,#rows-1 do
        local midpoint=(rows[i].t+rows[i+1].t)*.5
        local kind=midpoint<fill and 1 or midpoint<trail and 2 or 3
        local a=kind==previousKind and previous or row(rows[i],kind)
        local b=row(rows[i+1],kind)
        for lane=1,5 do
            triangle(a[lane],b[lane],a[lane+1])
            triangle(a[lane+1],b[lane],b[lane+1])
        end
        previous=b;previousKind=kind
    end
    return mesh
end
return M
