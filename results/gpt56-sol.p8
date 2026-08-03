pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
--[[ reference look: navy/black void, gray-brown rock, white snow, cyan ice, and pink focal sprites.
movement: run 1, accel .6, decel .15, gravity .21, fall 2, jump -2, dash 5 at .7071.
the climax crosses four empty columns by run, jump, and horizontal dash to a safe four-tile ledge.
the route introduces a safe rise, reverses through spike-constrained ledges, then climbs to the flag.
the demo detours left for one berry before the gap; the high-right berry remains optional. ]]
-- controls: arrows move/aim, o jumps, x dashes

max_run=1
run_accel=.6
run_decel=.15
gravity=.21
max_fall=2
jump_speed=-2
dash_speed=5
dash_diag=.7071

level={
 "................",
 "................",
 "................",
 "................",
 "................",
 "................",
 "..............g.",
 ".b...........###",
 "####....####....",
 "......###.^...b.",
 "..........####..",
 "###.....^.......",
 "...s..####......",
 "#####...........",
 "................",
 "................"
}

function _init()
 extcmd("set_filename","gpt56-sol.gif")
 extcmd("rec_frames")
 score=0
 deaths=0
 win=false
 victory_timer=0
 gif_saved=false
 demo_active=true
 demo_cancelled=false
 demo_failed=false
 demo_updates=0
 phase=0
 phase_timer=0
 berry_taken={false,false}
 berry_cells={{1,7},{14,9}}
 trails={}
 particles={}
 for i=1,12 do
  add(particles,{x=(i*37)%124+2,y=(i*23)%116+10,s=.05+(i%3)*.04})
 end
 spawn_player()
end

function cell(cx,cy)
 if cx<0 or cx>15 or cy<0 then return "#" end
 if cy>15 then return "." end
 return sub(level[cy+1],cx+1,cx+1)
end

function solid_at(px,py)
 return cell(flr(px/8),flr(py/8))=="#"
end

function spawn_player()
 x=25
 y=98
 vx=0
 vy=0
 grounded=true
 facing=1
 can_dash=true
 dashing=false
 dash_frames=0
 dash_vx=0
 dash_vy=0
 hitstop=0
end

function restart_world()
 score=0
 berry_taken={false,false}
 win=false
 victory_timer=0
 phase=0
 phase_timer=0
 spawn_player()
end

function approach(value,target,amount)
 if value<target then return min(value+amount,target) end
 if value>target then return max(value-amount,target) end
 return value
end

function box_solid(px,py)
 return solid_at(px,py) or solid_at(px+5,py) or
        solid_at(px,py+5) or solid_at(px+5,py+5)
end

function move_x(amount)
 local remaining=abs(amount)
 local direction=sgn(amount)
 while remaining>0 do
  local step=min(1,remaining)*direction
  if box_solid(x+step,y) then return true end
  x+=step
  remaining-=abs(step)
 end
 return false
end

function move_y(amount)
 local remaining=abs(amount)
 local direction=sgn(amount)
 while remaining>0 do
  local step=min(1,remaining)*direction
  if box_solid(x,y+step) then return true end
  y+=step
  remaining-=abs(step)
 end
 return false
end

function overlaps_tile(cx,cy)
 local tx=cx*8
 local ty=cy*8
 return x+5>=tx and x<=tx+7 and y+5>=ty and y<=ty+7
end

function touch_entities()
 if y>=128 then
  die()
  return
 end
 if vy>=0 then
  for cy=max(0,flr(y/8)),min(15,flr((y+5)/8)) do
   for cx=max(0,flr(x/8)),min(15,flr((x+5)/8)) do
    if cell(cx,cy)=="^" then
     die()
     return
    end
   end
  end
 end
 for i=1,2 do
  local berry=berry_cells[i]
  if not berry_taken[i] and overlaps_tile(berry[1],berry[2]) then
   berry_taken[i]=true
   score+=1
  end
 end
 for cy=max(0,flr(y/8)),min(15,flr((y+5)/8)) do
  for cx=max(0,flr(x/8)),min(15,flr((x+5)/8)) do
   if cell(cx,cy)=="g" then
    win=true
    victory_timer=0
    return
   end
  end
 end
end

function die()
 deaths+=1
 if demo_active then
  demo_active=false
  demo_failed=true
  score=0
  berry_taken={false,false}
  phase=0
  phase_timer=0
 end
 spawn_player()
 death_flash=6
end

function start_dash(input)
 local dx=(input.r and 1 or 0)-(input.l and 1 or 0)
 local dy=(input.d and 1 or 0)-(input.u and 1 or 0)
 if dx==0 and dy==0 then dx=facing end
 if dx!=0 and dy!=0 then
  dash_vx=dx*dash_speed*dash_diag
  dash_vy=dy*dash_speed*dash_diag
 else
  dash_vx=dx*dash_speed
  dash_vy=dy*dash_speed
 end
 can_dash=false
 dashing=true
 dash_frames=4
 hitstop=1
 vx=0
 vy=0
end

function update_player(input)
 if hitstop>0 then
  hitstop-=1
  return
 end
 if dashing then
  add(trails,{x=x,y=y,t=5})
  if move_x(dash_vx) then dash_vx=0 end
  if move_y(dash_vy) then dash_vy=0 end
  dash_frames-=1
  grounded=box_solid(x,y+1)
  if grounded then can_dash=true end
  if dash_frames==0 then
   dashing=false
   vx=mid(-max_run,dash_vx,max_run)
   if dash_vy<=0 then vy=0 else vy=min(dash_vy,max_fall) end
  end
  touch_entities()
  return
 end
 if input.dash and can_dash then
  start_dash(input)
  return
 end
 local move=(input.r and 1 or 0)-(input.l and 1 or 0)
 if move!=0 then
  facing=move
  vx=approach(vx,max_run*move,run_accel)
 else
  vx=approach(vx,0,run_decel)
 end
 vy=approach(vy,max_fall,gravity)
 if input.jump and grounded then vy=jump_speed end
 if move_x(vx) then vx=0 end
 if move_y(vy) then vy=0 end
 grounded=box_solid(x,y+1)
 if grounded then can_dash=true end
 touch_entities()
end

function blank_input()
 return {l=false,r=false,u=false,d=false,jump=false,dash=false}
end

function human_input()
 return {
  l=btn(0),r=btn(1),u=btn(2),d=btn(3),
  jump=btnp(4),dash=btnp(5)
 }
end

function demo_input()
 local input=blank_input()
 phase_timer+=1

 if phase==0 then
  input.r=true
  if x>=31 then
   phase=1
   phase_timer=0
  end
 elseif phase==1 then
  if abs(vx)<.01 then
   input.r=true
   input.jump=true
   phase=2
   phase_timer=0
  end
 elseif phase==2 then
  input.r=true
  if grounded and flr((y+6)/8)==12 then
   phase=3
   phase_timer=0
   return blank_input()
  end
 elseif phase==3 then
  if abs(vx)<.01 then
   phase=4
   phase_timer=0
  end
 elseif phase==4 then
  input.l=true
  if grounded and not box_solid(x-1,y+1) then
   input.jump=true
   phase=5
   phase_timer=0
  end
 elseif phase==5 then
  input.l=true
  if phase_timer==9 then
   input.l=false
   input.r=true
   input.u=true
   input.dash=true
  elseif phase_timer>9 then
   input.l=false
   input.r=true
  end
  if grounded and flr((y+6)/8)==9 and x>43 then
   phase=6
   phase_timer=0
   return blank_input()
  end
 elseif phase==6 then
  if abs(vx)<.01 then
   phase=7
   phase_timer=0
  end
 elseif phase==7 then
  input.l=true
  if grounded and not box_solid(x-1,y+1) then
   input.jump=true
   phase=8
   phase_timer=0
  end
 elseif phase==8 then
  input.l=true
  if grounded and flr((y+6)/8)==8 and x<32 then
   phase=9
   phase_timer=0
   return blank_input()
  end
 elseif phase==9 then
  input.l=true
  if score==1 then
   phase=10
   phase_timer=0
   return blank_input()
  end
 elseif phase==10 then
  if abs(vx)<.01 then
   phase=11
   phase_timer=0
  end
 elseif phase==11 then
  input.r=true
  if x>=26 then
   input.jump=true
   phase=12
   phase_timer=0
  end
 elseif phase==12 then
  input.r=true
  if phase_timer==5 then input.dash=true end
  if grounded and flr((y+6)/8)==8 and x>55 then
   phase=13
   phase_timer=0
   return blank_input()
  end
 elseif phase==13 then
  if abs(vx)<.01 then
   phase=14
   phase_timer=0
  end
 elseif phase==14 then
  input.r=true
  if grounded and not box_solid(x+1,y+1) then
   input.jump=true
   phase=15
   phase_timer=0
  end
 elseif phase==15 then
  input.r=true
 end
 return input
end

function update_effects()
 for particle in all(particles) do
  particle.y+=particle.s
  if particle.y>127 then particle.y=9 end
 end
 for i=#trails,1,-1 do
  trails[i].t-=1
  if trails[i].t<=0 then del(trails,trails[i]) end
 end
 if death_flash and death_flash>0 then death_flash-=1 end
end

function physical_input()
 for i=0,5 do
  if btn(i) then return true end
 end
 return false
end

function _update()
 update_effects()
 if demo_active and physical_input() then
  demo_active=false
  demo_cancelled=true
  restart_world()
  return
 end
 if win then
  if demo_active then
   victory_timer+=1
   if victory_timer>=45 and not gif_saved then
    gif_saved=true
    extcmd("video",4,1)
   end
  end
  return
 end
 local input
 if demo_active then
  demo_updates+=1
  if demo_updates>2700 then
   demo_active=false
   return
  end
  input=demo_input()
 else
  input=human_input()
 end
 update_player(input)
end

function draw_background()
 cls(1)
 rectfill(0,8,15,127,12)
 rectfill(116,8,127,127,12)
 rectfill(16,10,115,117,0)
 for py=18,62 do
  line(16,py,57-flr((py-18)/2),py,5)
 end
 for py=12,76 do
  line(92+flr((py-12)/3),py,115,py,5)
 end
 for py=88,117 do
  line(16+flr((py-88)/2),py,82,py,2)
 end
 rectfill(74,91,115,117,1)
 rectfill(0,72,7,89,7)
 rectfill(120,26,127,45,7)
 rectfill(0,104,5,127,7)
 rectfill(122,94,127,127,7)
 for particle in all(particles) do
  pset(particle.x,particle.y,particle.s>.1 and 7 or 6)
 end
end

function draw_tile(cx,cy)
 local px=cx*8
 local py=cy*8
 rectfill(px,py+2,px+7,py+7,5)
 if cell(cx,cy-1)!="#" then
  rectfill(px,py,px+7,py+1,7)
  pset(px+1,py+2,6)
  pset(px+6,py+2,12)
 end
 if cell(cx-1,cy)!="#" then line(px,py+3,px,py+7,2) end
 pset(px+2+(cx+cy)%4,py+4+(cx*3+cy)%3,6)
 pset(px+6,py+6,2)
end

function draw_spike(cx,cy)
 local px=cx*8
 local py=cy*8
 for offset=0,4,4 do
  line(px+offset,py+7,px+offset+2,py+1,6)
  line(px+offset+2,py+1,px+offset+3,py+7,7)
  pset(px+offset+2,py+5,7)
 end
end

function draw_berry(cx,cy)
 local px=cx*8
 local py=cy*8
 pset(px+3,py,11)
 line(px+1,py+1,px+3,py+2,3)
 line(px+5,py+1,px+3,py+2,11)
 rectfill(px+1,py+3,px+6,py+5,8)
 rectfill(px+2,py+6,px+5,py+7,8)
 pset(px+1,py+4,14)
 pset(px+6,py+4,14)
 pset(px+3,py+3,7)
 pset(px+4,py+6,14)
end

function draw_goal(cx,cy)
 local px=cx*8
 local py=cy*8
 line(px+1,py,px+1,py+7,7)
 line(px+2,py,px+2,py+7,6)
 rectfill(px+3,py,px+6,py+3,8)
 pset(px+7,py+2,14)
 pset(px+4,py+1,7)
 pset(px,py+7,12)
 pset(px+3,py+7,12)
end

function draw_player()
 local px=flr(x)-1
 local py=flr(y)-2
 local hair=can_dash and 8 or 12
 rectfill(px+1,py,px+5,py+2,hair)
 pset(px,py+1,hair)
 pset(px+(facing>0 and 0 or 6),py+3,hair)
 rectfill(px+2,py+2,px+5,py+4,15)
 pset(px+(facing>0 and 5 or 2),py+3,0)
 rectfill(px+1,py+5,px+5,py+7,3)
 rectfill(px+2,py+5,px+4,py+6,11)
 pset(px+1,py+7,0)
 pset(px+5,py+7,0)
end

function draw_hud()
 print("GPT-5.6 Sol",43,2,0)
 print("GPT-5.6 Sol",42,1,7)
 rectfill(2,118,24,126,0)
 pset(5,119,11)
 rectfill(3,121,7,124,8)
 pset(4,121,14)
 print("x"..score,10,120,7)
 if win then
  rectfill(43,58,85,69,0)
  print("CLEAR!",53,61,8)
  print("CLEAR!",52,60,7)
 end
end

function _draw()
 draw_background()
 for cy=0,15 do
  for cx=0,15 do
   local c=cell(cx,cy)
   if c=="#" then draw_tile(cx,cy) end
  end
 end
 for cy=0,15 do
  for cx=0,15 do
   local c=cell(cx,cy)
   if c=="^" then draw_spike(cx,cy) end
   if c=="g" then draw_goal(cx,cy) end
  end
 end
 for i=1,2 do
  if not berry_taken[i] then draw_berry(berry_cells[i][1],berry_cells[i][2]) end
 end
 for trail in all(trails) do
  local color=trail.t>2 and 7 or 12
  rectfill(flr(trail.x),flr(trail.y)+1,flr(trail.x)+3,flr(trail.y)+4,color)
 end
 draw_player()
 draw_hud()
 if death_flash and death_flash>0 then
  rect(0,0,127,127,8)
 end
end
