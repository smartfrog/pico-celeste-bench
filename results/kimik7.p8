pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
-- design notes
-- emulating celeste classic: tight run, single jump, 8-dir dash,
-- spike death, collectible strawberries, and a single-screen room.
-- constants: run 1.4, jump -2.8, gravity 0.25, max fall 3.0,
-- dash 5.0 for 10f, freeze 2f. hitbox 6x6.
-- forced obstacle: a 5-tile (40px) pit; max run-jump ~33px,
-- so a straight jump falls short but a dash crosses easily.

-- controls:
--  left/right: move
--  up/down: aim dash
--  z/c (btnp 4): jump
--  x/v (btnp 5): dash

run_spd=1.4
jump_v=-2.8
grav=0.25
max_fall=3.0
dash_spd=5.0
dash_dur=10
frz_dur=2

function _init()
 p={x=16,y=89,vx=0,vy=0,face=1,can_dash=true,dash=0,freeze=0,dead=0}
 berries={
  {x=3,y=6,got=false},
  {x=11,y=7,got=false}
 }
 goal={x=12,y=8}
 score=0
 win=false
 fr=0
 parts={}
 trail={}
 -- 16x16 tile grid. 1=solid, 2=spike(up)
 -- 5-tile pit (x=5..9) between start (x=0..4) and right side (x=10..15).
 map_d={
  {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1},
  {1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1},
  {1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1},
  {1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1},
  {1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1},
  {1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1},
  {1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1},
  {1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1},
  {1,0,0,0,0,0,0,0,0,0,0,1,1,1,0,1},
  {1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1},
  {1,0,1,0,0,0,0,0,0,0,0,0,0,0,0,1},
  {1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1},
  {1,1,1,1,1,0,0,0,0,0,1,1,1,1,1,1},
  {1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1},
  {1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1},
  {1,1,1,1,1,0,0,0,0,0,1,1,1,1,1,1}
 }
 -- spikes in the pit floor
 map_d[16][6]=2
 map_d[16][7]=2
 map_d[16][8]=2
 map_d[16][9]=2
end

function solid(tx,ty)
 if tx<0 or tx>15 or ty<0 or ty>15 then return true end
 return map_d[ty+1][tx+1]==1
end

function _update()
 if win then return end
 fr+=1

 if p.freeze>0 then
  p.freeze-=1
  return
 end

 if p.dead>0 then
  p.dead-=1
  if p.dead==0 then
   p.x=16; p.y=89
   p.vx=0; p.vy=0
   p.dash=0; p.freeze=0
   p.can_dash=true
   for b in all(berries) do b.got=false end
   score=0
  end
  return
 end

 -- dash
 if btnp(5) and p.can_dash then
  start_dash()
 end

 if p.dash>0 then
  p.dash-=1
  add(trail,{x=p.x+3,y=p.y+3,life=10})

  -- move during dash, no gravity, no run accel
  p.x+=p.vx
  if p.vx>0 then
   if solid_tile(p.x+6,p.y+1) or solid_tile(p.x+6,p.y+4) then
    p.x=flr((p.x+6)/8)*8-7
    p.vx=0
   end
  elseif p.vx<0 then
   if solid_tile(p.x,p.y+1) or solid_tile(p.x,p.y+4) then
    p.x=flr((p.x)/8)*8+8
    p.vx=0
   end
  end

  p.y+=p.vy
   if p.vy>=0 then
    if solid_tile(p.x+2,p.y+7) or solid_tile(p.x+5,p.y+7) then
     p.y=flr((p.y+7)/8)*8-7
     p.vy=0
     p.can_dash=true
    end
   elseif p.vy<0 then
   if solid_tile(p.x+2,p.y) or solid_tile(p.x+5,p.y) then
    p.y=flr(p.y/8)*8+8
    p.vy=0
   end
  end

  if p.dash==0 then
   -- dash ends; retain a little momentum
   p.vx*=0.2
   p.vy*=0.2
  end

  if p.y>128 or p.x<0 or p.x>122 then die() end
  return
 end

 -- run / aim
 local mx=0
 if btn(0) then mx=-1; p.face=-1 end
 if btn(1) then mx=1; p.face=1 end
 p.vx=mx*run_spd

 -- gravity
 p.vy+=grav
 if p.vy>max_fall then p.vy=max_fall end

 -- jump
 if btnp(4) and on_ground() then
  p.vy=jump_v
 end

 -- move x
 p.x+=p.vx
  if p.vx>0 then
   if solid_tile(p.x+6,p.y+1) or solid_tile(p.x+6,p.y+4) then
    p.x=flr((p.x+6)/8)*8-7
    p.vx=0
   end
  elseif p.vx<0 then
   if solid_tile(p.x,p.y+1) or solid_tile(p.x,p.y+4) then
    p.x=flr((p.x)/8)*8+8
    p.vx=0
   end
  end

  -- move y
 p.y+=p.vy
  if p.vy>=0 then
   if solid_tile(p.x+2,p.y+7) or solid_tile(p.x+5,p.y+7) then
    p.y=flr((p.y+7)/8)*8-7
    p.vy=0
    p.can_dash=true
   end
  elseif p.vy<0 then
  if solid_tile(p.x+2,p.y) or solid_tile(p.x+5,p.y) then
   p.y=flr(p.y/8)*8+8
   p.vy=0
  end
 end

 -- bounds / pit
 if p.y>128 or p.x<0 or p.x>122 then die() end

 -- spikes (only when falling and spike is under feet)
 for ox=0,1 do
  local tx=flr((p.x+2+ox*3)/8)
  local ty=flr((p.y+7)/8)
  if tx>=0 and tx<16 and ty>=0 and ty<16 then
   if map_d[ty+1][tx+1]==2 and p.vy>=0 then
    die()
   end
  end
 end

 -- strawberries
 for b in all(berries) do
  if not b.got and near(b.x*8+4,b.y*8+4,8) then
   b.got=true
   score+=1
  end
 end

 -- goal
 if near(goal.x*8+4,goal.y*8+4,10) then
  win=true
 end

 -- ambient particles (snow)
 if rnd()<0.15 then
  add(parts,{x=rnd(128),y=0,vx=rnd(0.4)-0.2,vy=rnd(0.4)+0.2,life=60+rnd(60),col=7})
 end
 for e in all(parts) do
  e.x+=e.vx; e.y+=e.vy; e.life-=1
  if e.life<=0 then del(parts,e) end
 end
 for t in all(trail) do
  t.life-=1
  if t.life<=0 then del(trail,t) end
 end
end

function solid_tile(cx,cy)
 return solid(flr(cx/8),flr(cy/8))
end

function on_ground()
 return solid(flr((p.x+3)/8),flr((p.y+8)/8))
end

function near(tx,ty,d)
 local dx=(p.x+3)-tx
 local dy=(p.y+3)-ty
 return dx*dx+dy*dy<d*d
end

function start_dash()
 local dx=0; local dy=0
 if btn(0) then dx=-1 end
 if btn(1) then dx=1 end
 if btn(2) then dy=-1 end
 if btn(3) then dy=1 end
 if dx==0 and dy==0 then dx=p.face end
 if dx!=0 and dy!=0 then
  dx*=0.707
  dy*=0.707
 end
 p.vx=dx*dash_spd
 p.vy=dy*dash_spd
 p.dash=dash_dur
 p.freeze=frz_dur
 p.can_dash=false
end

function die()
 p.dead=20
 p.vx=0; p.vy=0
 p.dash=0
 p.can_dash=true
end

function _draw()
 cls(12)

 -- map
 for ty=0,15 do
  for tx=0,15 do
   local t=map_d[ty+1][tx+1]
   if t==1 then
    rectfill(tx*8,ty*8,tx*8+7,ty*8+7,5)
    rectfill(tx*8,ty*8,tx*8+7,ty*8+2,7)
    pset(tx*8+1,ty*8+1,6)
   elseif t==2 then
    -- up spike
    local x=tx*8; local y=ty*8+7
    line(x,y,x+4,y-6,7)
    line(x+4,y-6,x+7,y,7)
    line(x+1,y,x+3,y-4,6)
    line(x+3,y-4,x+6,y,6)
    line(x,y,x+7,y,5)
   end
  end
 end

 -- berries
 for b in all(berries) do
  if not b.got then
   local x=b.x*8; local y=b.y*8
   circfill(x+4,y+5,3,8)
   rectfill(x+3,y+1,x+4,y+3,11)
   pset(x+5,y+2,3)
  end
 end

 -- goal flag
 local gx=goal.x*8; local gy=goal.y*8
 rectfill(gx+2,gy+5,gx+5,gy+7,4)
 rectfill(gx+3,gy+1,gx+6,gy+4,9)
 rectfill(gx+6,gy+1,gx+6,gy+4,10)

 -- dash trail
 for t in all(trail) do
  circfill(t.x,t.y,flr(t.life/4)+1,7)
 end

 -- player
 if p.dead==0 then
  local pc=12
  local hair=p.can_dash and 8 or 2
  rectfill(p.x+1,p.y+3,p.x+5,p.y+6,pc)
  rectfill(p.x+2,p.y+1,p.x+4,p.y+3,15)
  rectfill(p.x+1,p.y,p.x+5,p.y+1,hair)
  pset(p.x+2,p.y+7,5)
  pset(p.x+4,p.y+7,5)
 end

 -- particles
 for e in all(parts) do
  pset(e.x,e.y,e.col)
 end

 -- ui
 print("berries:"..score,2,2,7)
 if win then
  rectfill(36,56,92,72,0)
  print("clear!",50,62,10)
 end
end

__gfx__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
