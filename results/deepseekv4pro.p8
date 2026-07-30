pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
-- visual: dark navy cavern, gray-brown rock, pale snow caps,
--   cyan ice accents, red player, green-stemmed strawberries
-- constants: max run 1, accel 0.6, decel 0.15, grav 0.21,
--   max fall 2, jump -2, dash speed 5, diag 0.7071,
--   hitstop 2, dash frames 4, 6x6 hitbox
-- forced gap row 4 cols 6-11: run right to edge, jump+dash up-right
-- route: intro jump right, reversal jump left+dash up-left,
--   climax dash across 4-col gap, final jump to goal
-- demo: state-based phases from oracle move list, collects 1 berry
-- controls: arrows move, z/x jump/dash (btns 4/5), up/down aim
--
-- ................
-- ..............g.
-- ...............#
-- ................
-- ....###....#####
-- ................
-- ................
-- .s###....###....
-- ###.....##..##..
-- ^#....b.^#..b...
-- #.......##....#.
-- ............#...
-- ............#...
-- ............#...
-- ............#...
-- ............#...

-- constants
max_run=1 accel=0.6 decel=0.15
grav=0.21 max_fall=2 jump_v=-2
dash_speed=5 dash_diag=0.7071
dash_hitstop=2 dash_frames=4
hitbox=6

-- level grid
grid={
"................",
"..............g.",
"...............#",
"................",
"....###....#####",
"................",
"................",
".s###....###....",
"###.....##..##..",
"^#....b.^#..b...",
"#.......##....#.",
"............#...",
"............#...",
"............#...",
"............#...",
"............#..."
}

-- player state
p={}
trail={}
snow={}
demo_phase=0 dem_framecount=0
deaths=0 win_timer=-1
gif_saved=false demo_active=true
dead_timer=0

function t_solid(c,r)
 if c<0 or c>15 or r<0 or r>15 then return c<0 or c>15 end
 local ch=sub(grid[r+1],c+1,c+1)
 return ch=="#"
end

function t_spike(c,r)
 if c<0 or c>15 or r<0 or r>15 then return false end
 return sub(grid[r+1],c+1,c+1)=="^"
end

function t_goal(c,r)
 if c<0 or c>15 or r<0 or r>15 then return false end
 return sub(grid[r+1],c+1,c+1)=="g"
end

function t_berry(c,r)
 if c<0 or c>15 or r<0 or r>15 then return false end
 return sub(grid[r+1],c+1,c+1)=="b"
end

function box_solid(x,y)
 local l=flr(x/8) local r=flr((x+hitbox-1)/8)
 local t=flr(y/8) local b=flr((y+hitbox-1)/8)
 if l<0 or r>15 then return true end
 for row=t,b do
  for col=l,r do
   if t_solid(col,row) then return true end
  end
 end
 return false
end

function spawn_player()
 local sx,sy
 for r=0,15 do
  for c=0,15 do
   if sub(grid[r+1],c+1,c+1)=="s" then sx,sy=c,r end
  end
 end
 p.x=sx*8+1 p.y=sy*8+2
 p.vx=0 p.vy=0 p.grounded=false p.can_dash=true
 p.hitstop=0 p.dash_left=0 p.dash_vx=0 p.dash_vy=0
 p.facing=1 p.dead=false p.won=false p.score=0
 p.has={}
 for _=1,40 do step_player(0,0,false,false) end
 trail={}
end

function respawn()
 spawn_player()
 demo_phase=0 dem_framecount=0
 deaths+=1
end

function handle_death()
 if p.y>200 then p.dead=true end
end

function hit_spike(p)
 if p.vy<0 then return false end
 local l=flr(p.x/8)
 local r=flr((p.x+hitbox-1)/8)
 local t=flr(p.y/8)
 local b=flr((p.y+hitbox-1)/8)
 for row=max(t,0),min(b,15) do
  for col=max(l,0),min(r,15) do
   if t_spike(col,row) then return true end
  end
 end
 return false
end

function collect_berries()
 local l=flr(p.x/8)
 local r=flr((p.x+hitbox-1)/8)
 local t=flr(p.y/8)
 local b=flr((p.y+hitbox-1)/8)
 for row=max(t,0),min(b,15) do
  for col=max(l,0),min(r,15) do
   if t_berry(col,row) then
    local key=col..","..row
    if not p.has[key] then
     p.has[key]=true
     p.score+=1
    end
   end
   if t_goal(col,row) then p.won=true end
  end
 end
end

function aim(dx,dy,facing)
 if dx==0 and dy==0 then return facing,0 end
 return dx,dy
end

function step_player(dx,dy,jump,dash)
 if p.hitstop>0 then
  p.hitstop-=1
  return
 end
 if p.dash_left>0 then
  local ox=p.x
  p.x+=p.dash_vx
  if box_solid(p.x,p.y) then p.x=ox end
  p.y+=p.dash_vy
  p.dash_left-=1
  if p.dash_left==0 then
   p.vx=mid(-max_run,p.dash_vx,max_run)
   p.vy=p.dash_vy<=0 and 0 or mid(0,p.dash_vy,max_fall)
   -- nudge up from any solid after dash ends
   while box_solid(p.x,p.y) do p.y-=1 end
  end
  p.grounded=box_solid(p.x,p.y+1)
  if p.grounded then p.can_dash=true end
  collect_berries()
  return
 end

 if dash and p.can_dash then
  local adx,ady=aim(dx,dy,p.facing)
  local svx,svy=adx*dash_speed,ady*dash_speed
  if adx~=0 and ady~=0 then svx*=dash_diag svy*=dash_diag end
  p.dash_vx,p.dash_vy=svx,svy
  p.can_dash=false p.hitstop=dash_hitstop-1
  p.dash_left=dash_frames p.vx=0 p.vy=0
  for i=1,4 do add(trail,{x=p.x+3,y=p.y+3,t=4}) end
  return
 end

 if dx~=0 then p.facing=dx
  if p.vx<max_run*dx then p.vx=min(p.vx+accel,max_run) end
  if p.vx>max_run*dx then p.vx=max(p.vx-accel,-max_run) end
 else
  if p.vx>0 then p.vx=max(p.vx-decel,0) end
  if p.vx<0 then p.vx=min(p.vx+decel,0) end
 end

 p.vy=min(p.vy+grav,max_fall)
 if jump and p.grounded then p.vy=jump_v end

  local ox=p.x+0
  p.x+=p.vx
  if box_solid(p.x,p.y) then p.x=ox p.vx=0 end
  -- step y pixel by pixel
  local sy=p.vy
  local grounded_y=false
  while abs(sy)>0.001 do
   local step=mid(-1,sy,1)
   local ny=p.y+step
   if box_solid(p.x,ny) then
    if p.vy>0 then grounded_y=true end
    p.vy=0 break
   end
   p.y=ny sy-=step
  end
  p.grounded=grounded_y or box_solid(p.x,p.y+1)
  if p.grounded then p.can_dash=true end
 if hit_spike(p) then p.dead=true end
 collect_berries()
end

function handle_input()
 -- read physical input first
 local phy=btn(0) or btn(1) or btn(2) or btn(3) or btn(4) or btn(5)
 if demo_active and phy then
  demo_active=false gif_saved=true
 end
 if not demo_active then return phy end
 return false
end

-- demo controller state
dem_sub=0
dem_framecount=0

function demo_control()
 if p.won or p.dead or not demo_active then return 0,0,false,false end
 dem_framecount+=1
 local f=dem_framecount
 
 if demo_phase==0 then
  -- 1. jump right [23f]
  if f==1 then return 1,0,true,false end
  if f<=23 then return 1,0,false,false end
  demo_phase=1 dem_framecount=0
  return 0,0,false,false
 
 elseif demo_phase==1 then
  -- 2. walk 5f, jump, air 4f, dash right [37f]
  if f<=5 then return 1,0,false,false end
  if f==6 then return 1,0,true,false end
  if f>=7 and f<=10 then return 1,0,false,false end
  if f==11 then return 1,0,false,true end
  if f<=37 then return 1,0,false,false end
  demo_phase=2 dem_framecount=0
  return 0,0,false,false
 
 elseif demo_phase==2 then
  -- 3. walk right 7f (to x~86), jump, immediate up-right dash
  --    player passes through berry (12,9) during fall -> score=1
  if f<=7 then return 1,0,false,false end
  if f==8 then return 1,0,true,false end
  if f==9 then return 1,-1,false,true end
  if p.grounded and p.y<35 then demo_phase=3 dem_framecount=0 end
  return 1,0,false,false
 
 elseif demo_phase==3 then
  -- 4. jump, dash up-right to goal
  if f==1 then return 1,0,true,false end
  if f==2 then return 1,-1,false,true end
  return 1,0,false,false
 end
 return 0,0,false,false
end

function _init()
 extcmd("set_filename","deepseekv4pro.gif")
 extcmd("rec_frames")
 spawn_player()
 demo_active=true demo_phase=0 dem_framecount=0
 gif_saved=false win_timer=-1 deaths=0
 -- init snow particles
 for i=1,12 do
  add(snow,{x=rnd(128),y=rnd(128),vx=rnd(0.4)-0.2,vy=rnd(0.3)+0.1,c=rnd(2)})
 end
end

function _update()
 if win_timer>0 then
  win_timer-=1
  if win_timer==0 then
    if demo_active and not gif_saved then
    extcmd("video",4,1)
    gif_saved=true
   end
  end
  -- update snow during win
  for s in all(snow) do
   s.x=(s.x+s.vx)%128 s.y=(s.y+s.vy)%128
  end
  return
 end

 if p.dead then
  dead_timer+=1
  if dead_timer>15 then
   deaths+=1 respawn()
  end
  return
 end

 if p.won then
  win_timer=45
  return
 end

 local dx,dy=0,0
 local jump,dash=false,false
 if not demo_active then
  if btn(0) then dx=-1 end
  if btn(1) then dx=1 end
  if btn(2) then dy=-1 end
  if btn(3) then dy=1 end
  -- cancel opposite
  if btn(0) and btn(1) then dx=0 end
  if btn(2) and btn(3) then dy=0 end
  jump=btnp(4)
  dash=btnp(5)
 else
  -- cancel demo on physical input
  if btn(0) or btn(1) or btn(2) or btn(3) or btnp(4) or btnp(5) then
   demo_active=false gif_saved=true
  else
   dx,dy,jump,dash=demo_control()
  end
 end

 step_player(dx,dy,jump,dash)
 handle_death()

 -- trail decay
 for i=#trail,1,-1 do
  trail[i].t-=1
  if trail[i].t<=0 then del(trail,trail[i]) end
 end

 -- update snow
 for s in all(snow) do
  s.x=(s.x+s.vx)%128 s.y=(s.y+s.vy)%128
 end
end

function draw_terrain()
 for r=0,15 do
  for c=0,15 do
   if t_solid(c,r) then
    local x,y=c*8,r*8
    -- main rock body
    rectfill(x,y,x+7,y+7,5)
    -- texture specks
    if rnd()<0.3 then
     pset(x+flr(rnd(6))+1,y+flr(rnd(6))+1,6)
    end
    -- snow cap on top if exposed
    if r>0 and not t_solid(c,r-1) then
     rectfill(x,y,x+7,y+1,7)
     pset(x+2,y,6) pset(x+5,y,6)
    end
    -- ice accent
    if t_solid(c,r+1) and rnd()<0.1 then
     rectfill(x+1,y+3,x+2,y+5,12)
    end
   end
  end
 end
end

function draw_player()
 if p.dead then return end
 local x,y=flr(p.x),flr(p.y)
 local hc=p.can_dash and 8 or 7 -- red hair when can dash, white when not
 -- body
 rectfill(x+1,y+2,x+4,y+5,14)
 -- hair
 if p.facing>0 then
  rectfill(x+2,y,x+4,y+1,hc)
  pset(x+5,y+1,hc)
 else
  rectfill(x+1,y,x+3,y+1,hc)
  pset(x,y+1,hc)
 end
 -- eyes
 pset(x+(p.facing>0 and 3 or 2),y+3,0)
 -- feet
 pset(x+1,y+5,1) pset(x+4,y+5,1)
 -- dash glow
 if p.dash_left>0 then
  circfill(x+2,y+3,3,7)
  rectfill(x+1,y+2,x+4,y+5,14)
  -- redraw hair over glow
  if p.facing>0 then
   rectfill(x+2,y,x+4,y+1,hc)
   pset(x+5,y+1,hc)
  else
   rectfill(x+1,y,x+3,y+1,hc)
   pset(x,y+1,hc)
  end
  pset(x+(p.facing>0 and 3 or 2),y+3,0)
 end
end

function draw_trail()
 for t in all(trail) do
  circfill(t.x,t.y,1,7)
 end
end

function draw_berries()
 for r=0,15 do
  for c=0,15 do
   if t_berry(c,r) then
    local key=c..","..r
    if not p.has[key] then
     local x,y=c*8+4,r*8+4
     circfill(x,y,3,8)
     circfill(x-1,y-2,1,7)
     line(x,y-4,x,y-2,11)
     pset(x,y-5,11)
    end
   end
  end
 end
end

function draw_spikes()
 for r=0,15 do
  for c=0,15 do
   if t_spike(c,r) then
    local x,y=c*8,r*8
    line(x,y+7,x+3,y,7)
    line(x+3,y,x+7,y+7,7)
    line(x+1,y+4,x+5,y+4,6)
    pset(x+3,y+1,6)
   end
  end
 end
end

function draw_goal()
 for r=0,15 do
  for c=0,15 do
   if t_goal(c,r) then
    local x,y=c*8,r*8
    -- pole
    rectfill(x+3,y,x+4,y+7,4)
    -- flag
    line(x+5,y,x+5,y+5,8)
    line(x+5,y,x+7,y+2,8)
    line(x+7,y+2,x+5,y+4,8)
    -- highlight
    pset(x+6,y+1,7)
   end
  end
 end
end

function draw_snow()
 for s in all(snow) do
  pset(s.x,s.y,s.c==0 and 7 or 6)
 end
end

function draw_bg()
 -- top 8px title zone with shadow
 rectfill(0,0,127,7,1)
 print("deepseek v4 pro",2,1,7)
 print("deepseek v4 pro",1,0,12)
 -- cavern framing
 rectfill(0,8,127,127,0)
 -- distant silhouettes
 for i=0,15 do
  local h=8+sin(i*0.3+t())*3
  rectfill(i*8,120-h,i*8+3,127,2)
 end
end

function _draw()
 draw_bg()
 draw_snow()
 draw_terrain()
 draw_spikes()
 draw_goal()
 draw_berries()
 draw_trail()
 draw_player()

 -- hud
 if p.score>0 then
  for i=1,p.score do
   local sx=110+i*8
   circfill(sx,4,3,8)
   circfill(sx-1,2,1,7)
  end
 end
 rectfill(0,120,127,127,0)
 print("x"..deaths,2,122,7)
 print("deepseek v4 pro",30,122,6)

 if p.dead then
  print("dead",50,60,8)
 elseif p.won and win_timer>0 then
  print("clear!",44,56,8)
  print("deepseek v4 pro",18,68,6)
 end
end
