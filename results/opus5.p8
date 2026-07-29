pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
-- opus 5 -- frostbite hollow
-- draft notes (wip)
-- level grid 16x16, legend:
-- . empty  # solid  ^ spike  s spawn  b berry  g goal
-- lvl={
-- "................",
-- "................",
-- "................",
-- "................",
-- "....b...........",
-- "................",
-- "..###...........",
-- "................",
-- "s.....##...b....",
-- "####............",
-- "................",
-- "........####..#g",
-- "................",
-- "..............##",
-- "................",
-- "################"}

-- controls: arrows move / aim, o jump, x dash

lvl={
 "................",
 "................",
 "................",
 "................",
 "....b...........",
 "................",
 "..###...........",
 "................",
 "s.....##...b....",
 "####............",
 "................",
 "........####..#g",
 "................",
 "..............##",
 "................",
 "################"}

-- movement constants (exact)
maxrun=1
accel=0.6
decel=0.15
grav=0.21
maxfall=2
jumpv=-2
dashspd=5
diagf=0.7071
hitstop_len=2
dashtime=4

solid={}
spawnx=8
spawny=64

function is_solid(c,r)
 if c<0 or c>15 or r>15 then return true end
 if r<0 then return false end
 return solid[r*16+c]==true
end

function box_hit(x,y)
 -- 6x6 hitbox with top-left at x,y
 for dx=0,1 do
  for dy=0,1 do
   local px=x+dx*5
   local py=y+dy*5
   if is_solid(flr(px/8),flr(py/8)) then return true end
  end
 end
 return false
end

function build_level()
 solid={}
 for r=0,15 do
  local s=lvl[r+1]
  for c=0,15 do
   local ch=sub(s,c+1,c+1)
   if ch=="#" then solid[r*16+c]=true end
   if ch=="s" then spawnx=c*8+1 spawny=r*8+2 end
  end
 end
end

function _init()
 build_level()
 p={x=spawnx,y=spawny,vx=0,vy=0,grounded=false}
end

function _update()
 local ix=0
 if btn(0) then ix-=1 end
 if btn(1) then ix+=1 end

 if ix~=0 then
  p.vx=mid(-maxrun,p.vx+ix*accel,maxrun)
 else
  if p.vx>0 then p.vx=max(0,p.vx-decel) end
  if p.vx<0 then p.vx=min(0,p.vx+decel) end
 end

 if btnp(4) and p.grounded then p.vy=jumpv end

 p.vy=min(p.vy+grav,maxfall)

 -- x move
 local nx=p.x+p.vx
 if box_hit(nx,p.y) then
  local step=sgn(p.vx)
  while not box_hit(p.x+step,p.y) do p.x+=step end
  p.vx=0
 else
  p.x=nx
 end

 -- y move
 local ny=p.y+p.vy
 p.grounded=false
 if box_hit(p.x,ny) then
  local step=sgn(p.vy)
  while not box_hit(p.x,p.y+step) do p.y+=step end
  if p.vy>0 then p.grounded=true end
  p.vy=0
 else
  p.y=ny
 end
end

function _draw()
 cls(1)
 for r=0,15 do
  for c=0,15 do
   if is_solid(c,r) then
    rectfill(c*8,r*8,c*8+7,r*8+7,5)
   end
  end
 end
 rectfill(p.x,p.y,p.x+5,p.y+5,8)
 print("opus 5",2,1,7)
end
