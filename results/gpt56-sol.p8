pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
-- reference look: black/navy cavern, chunky gray rock, pale snow, cyan ice, bright focal sprites.
-- motion: run 1, accel .6, decel .15; gravity .21/fall 2/jump -2; dash 5 at .7071, 2 stop + 4 move.
-- climax: a same-height four-column void ends on a safe two-tile snowy landing beside spikes.
-- route: an easy right jump introduces motion, then a left-right switchback rises to the gap.
-- demo: normal logical inputs take the lower strawberry detour, cross the gap, and raise the flag.
-- controls: arrows move/aim, o jumps, x dashes.

--[[level grid
................
................
................
................
................
................
................
................
b.............g.
^.........^.####
####....####....
.......b........
......###.......
..###...........
.s....####......
######......####
]]

level={
 "................",
 "................",
 "................",
 "................",
 "................",
 "................",
 "................",
 "................",
 "b.............g.",
 "^.........^.####",
 "####....####....",
 ".......b........",
 "......###.......",
 "..###...........",
 ".s....####......",
 "######......####"
}

max_run=1
accel=.6
decel=.15
gravity=.21
max_fall=2
jump_v=-2
dash_speed=5
dash_diag=.7071

function approach(v,target,step)
 if v>target then return max(v-step,target) end
 return min(v+step,target)
end

function tile(tx,ty)
 if tx<0 or tx>15 then return "#" end
 if ty<0 or ty>15 then return "." end
 return sub(level[ty+1],tx+1,tx+1)
end

function solid_at(px,py)
 return tile(flr(px/8),flr(py/8))=="#"
end

function box_solid(nx,ny)
 local l=flr(nx/8)
 local r=flr((nx+5)/8)
 local u=flr(ny/8)
 local d=flr((ny+5)/8)
 for yy=u,d do
  for xx=l,r do
   if tile(xx,yy)=="#" then return true end
  end
 end
 return false
end

function move_axis(amount,horizontal)
 local left=amount
 while abs(left)>.001 do
  local step=mid(-1,left,1)
  local nx=x
  local ny=y
  if horizontal then nx+=step else ny+=step end
  if box_solid(nx,ny) then return true end
  x=nx y=ny left-=step
 end
 return false
end

function overlap(tx,ty)
 local px=tx*8
 local py=ty*8
 return x<px+8 and x+5>=px and y<py+8 and y+5>=py
end

function make_entities()
 berries={}
 spikes={}
 goalx=0 goaly=0
 for ty=0,15 do
  for tx=0,15 do
   local c=tile(tx,ty)
   if c=="b" then add(berries,{x=tx,y=ty,got=false}) end
   if c=="^" then add(spikes,{x=tx,y=ty}) end
   if c=="g" then goalx=tx goaly=ty end
  end
 end
end

function respawn(count_death)
 if count_death then deaths+=1 end
 if count_death and demo then
  phase=0 phase_time=0 score=0
  for b in all(berries) do b.got=false end
 end
 x=9 y=114
 vx=0 vy=0
 grounded=false
 can_dash=true
 hitstop=0 dash_left=0
 dash_vx=0 dash_vy=0
 dashing=false facing=1
 dead=0
 was_grounded=false
end

function kill()
 if dead==0 and not win then
  dead=18
  vx=0 vy=0
 end
end

function touch_entities(effective_vy)
 if y>128 then kill() return end
 local falling=(effective_vy==nil and vy or effective_vy)>=0
 if falling then
  for s in all(spikes) do
   if overlap(s.x,s.y) then kill() return end
  end
 end
 for b in all(berries) do
  if not b.got and overlap(b.x,b.y) then
   b.got=true
   score+=1
  end
 end
 if overlap(goalx,goaly) then
  win=true
  win_timer=0
  vx=0 vy=0
  dashing=false
 end
end

function physical_pressed()
 for i=0,5 do
  if btn(i) then return true end
 end
 return false
end

function platform_row()
 if not grounded then return -1 end
 return flr((y+6)/8)
end

function clear_demo_input()
 il=false ir=false iu=false id=false
 ij=false ix=false
end

function demo_control()
 clear_demo_input()
 local p=platform_row()
 phase_time+=1

 -- make the safe introductory jump onto the first shelf
 if phase==0 then
  ir=true
  if p==15 and x>=40 then ij=true phase=2 phase_time=0 end

 -- land on the right shelf, then reverse to the higher left shelf
 elseif phase==2 then
  ir=true
  if p==14 then phase=3 phase_time=0 end
 elseif phase==3 then
  il=true
  if p==14 and x<=44 then ij=true phase=4 phase_time=0 end
 elseif phase==4 then
  il=true
  if p==13 then
   il=false ir=true ij=true
   phase=6 phase_time=0
  end

 -- reverse again and collect the lower detour berry
 elseif phase==5 then
  ir=true
  if p==13 and x>=33 then ij=true phase=6 phase_time=0 end
 elseif phase==6 then
  ir=true
  if p==12 then phase=7 phase_time=0 end

 -- climb up-left to the gap takeoff
 elseif phase==7 then
  il=true
  if p==12 and x<=44 then ij=true phase=8 phase_time=0 end
 elseif phase==8 then
  il=true iu=true ix=true
  phase=9 phase_time=0
 elseif phase==9 then
  il=true
  if p==10 and x<40 then phase=10 phase_time=0 end

 -- run, jump, and spend a horizontal dash over four empty columns
 elseif phase==10 then
  ir=true
  if p==10 and x>=25 then ij=true phase=11 phase_time=0 end
 elseif phase==11 then
  ir=true
  if phase_time>=4 then
   ix=true phase=12 phase_time=0
  end
 elseif phase==12 then
  ir=true
  if p==10 and x>55 then phase=13 phase_time=0 end

 -- one last rising jump reaches the real goal flag
 elseif phase==13 then
  ir=true
  if p==10 and x>=73 then ij=true phase=14 phase_time=0 end
 elseif phase==14 then
  ir=true
  if p==10 and x>=89 then ij=true phase=15 phase_time=0 end
 elseif phase==15 then
  ir=true
 end
end

function read_controls()
 if demo then
  if dead==0 then demo_control() else clear_demo_input() end
  return
 end
 il=btn(0) ir=btn(1)
 iu=btn(2) id=btn(3)
 ij=btnp(4) ix=btnp(5)
end

function age_trails()
 for i=#trail,1,-1 do
  trail[i].life-=1
  if trail[i].life<=0 then deli(trail,i) end
 end
end

function player_step()
 if hitstop>0 then
  hitstop-=1
  dashing=dash_left>0
  return
 end

 if dash_left>0 then
  add(trail,{x=x,y=y,life=4})
  move_axis(dash_vx,true)
  move_axis(dash_vy,false)
  dash_left-=1
  dashing=dash_left>0
  if dash_left==0 then
   vx=mid(-max_run,dash_vx,max_run)
   if dash_vy<=0 then vy=0 else vy=mid(0,dash_vy,max_fall) end
  end
  grounded=box_solid(x,y+1)
  if grounded then can_dash=true end
  touch_entities(dash_vy)
  return
 end

 local dx=(ir and 1 or 0)-(il and 1 or 0)
 local dy=(id and 1 or 0)-(iu and 1 or 0)
 if ix and can_dash then
  if dx==0 and dy==0 then dx=facing end
  dash_vx=dx*dash_speed
  dash_vy=dy*dash_speed
  if dx!=0 and dy!=0 then
   dash_vx*=dash_diag
   dash_vy*=dash_diag
  end
  can_dash=false
  hitstop=1
  dash_left=4
  vx=0 vy=0
  dashing=true
  return
 end

 if dx!=0 then
  facing=dx
  vx=approach(vx,max_run*dx,accel)
 else
  vx=approach(vx,0,decel)
 end
 vy=approach(vy,max_fall,gravity)
 if ij and grounded then vy=jump_v end

 if move_axis(vx,true) then vx=0 end
 if move_axis(vy,false) then vy=0 end
 grounded=box_solid(x,y+1)
 if grounded then can_dash=true end
 dashing=false
 touch_entities()
end

function _init()
 extcmd("set_filename","gpt56-sol.gif")
 extcmd("rec_frames")
 make_entities()
 score=0 deaths=0
 win=false win_timer=0
 video_saved=false gif_ok=true
 demo=true demo_updates=0
 phase=0 phase_time=0
 landings=0
 trail={}
 t=0
 respawn(false)
end

function _update()
 -- physical input can cancel even during dash hitstop or the clear hold
 if demo and physical_pressed() then
  demo=false gif_ok=false win=false
  score=0 deaths=0 landings=0 trail={}
  for b in all(berries) do b.got=false end
  respawn(false)
 end
 if demo then
  demo_updates+=1
  if demo_updates>2700 and not win then
   demo=false gif_ok=false
  end
 end

 if win then
  t+=1 age_trails()
  if demo and gif_ok and not video_saved then
   win_timer+=1
   if win_timer==45 then
    video_saved=true
    extcmd("video",4,1)
   end
  end
  return
 end

 if dead>0 then
  t+=1 age_trails()
  dead-=1
  if dead==0 then respawn(true) end
  return
 end

 -- the update after the dash press is the second frozen update
 if hitstop>0 then
  hitstop-=1
  dashing=dash_left>0
  return
 end

 read_controls()

 was_grounded=grounded
 player_step()
 -- the dash-press update is the first frozen update
 if hitstop==0 then
  t+=1
  age_trails()
 end
 if grounded and not was_grounded then landings+=1 end
end

function draw_background()
 cls(0)

 -- distant blue cavern lobes leave a large black central void
 rectfill(0,8,6,127,1)
 rectfill(0,70,22,127,1)
 rectfill(7,92,42,127,1)
 rectfill(121,8,127,127,1)
 rectfill(104,48,127,127,1)
 rectfill(82,98,127,127,1)
 rectfill(18,111,58,127,2)
 rectfill(70,112,108,127,2)

 -- irregular gray-brown framing and cyan ice seams
 rectfill(0,9,3,62,5)
 rectfill(0,82,10,101,5)
 rectfill(124,9,127,72,5)
 rectfill(118,18,127,36,5)
 line(4,25,4,57,13)
 line(122,43,122,68,12)
 rectfill(1,9,5,10,7)
 rectfill(122,9,126,10,7)

 -- sparse deterministic snow behind the playfield
 for i=1,10 do
  local sx=(i*37)%118+5
  local sy=(i*53+flr(t/6))%111+10
  pset(sx,sy,i%3==0 and 7 or 6)
 end
end

function draw_rock(tx,ty)
 local px=tx*8
 local py=ty*8
 rectfill(px,py,px+7,py+7,5)
 if tile(tx+1,ty)!="#" then line(px+7,py+2,px+7,py+7,1) end
 line(px,py+7,px+7,py+7,1)
 pset(px+2+(ty%3),py+4,13)
 if (tx+ty)%5==0 then pset(px+6,py+5,12) end
 if tile(tx,ty-1)!="#" then
  line(px,py,px+7,py,7)
  line(px+1,py+1,px+3,py+1,7)
  pset(px+6,py+1,6)
 end
end

function draw_spike(s)
 local px=s.x*8
 local py=s.y*8
 for i=0,1 do
  local q=px+i*4
  pset(q+2,py+1,7)
  line(q+1,py+3,q+2,py+2,7)
  line(q+1,py+4,q+3,py+4,6)
  line(q,py+6,q+3,py+6,6)
  line(q,py+7,q+3,py+7,5)
 end
end

function draw_berry(b)
 if b.got then return end
 local px=b.x*8
 local py=b.y*8+flr(sin((t+b.x*9)/25))
 pset(px+4,py,11)
 line(px+2,py+1,px+4,py+2,11)
 pset(px+5,py+1,3)
 line(px+1,py+3,px+6,py+3,8)
 rectfill(px+1,py+4,px+6,py+5,8)
 line(px+2,py+6,px+5,py+6,14)
 line(px+3,py+7,px+4,py+7,8)
 pset(px+2,py+3,7)
end

function draw_goal()
 local px=goalx*8
 local py=goaly*8
 line(px+1,py,px+1,py+8,6)
 pset(px+1,py,7)
 line(px+2,py+1,px+7,py+1,8)
 line(px+2,py+2,px+6,py+2,14)
 line(px+2,py+3,px+5,py+3,8)
 line(px+2,py+4,px+4,py+4,8)
end

function draw_player_at(px,py,ghost)
 px=flr(px)-1 py=flr(py)-1
 if ghost then
  rectfill(px+1,py+2,px+5,py+6,7)
  return
 end
 local hair=can_dash and 8 or 12
 pset(px+(facing<0 and 6 or 0),py+2,hair)
 line(px+1,py+1,px+5,py+1,hair)
 rectfill(px+1,py+2,px+5,py+3,hair)
 rectfill(px+2,py+2,px+5,py+4,15)
 pset(px+(facing>0 and 5 or 2),py+3,0)
 rectfill(px+2,py+5,px+5,py+7,2)
 pset(px+1,py+7,1)
 pset(px+6,py+7,1)
 if can_dash then pset(px+2,py+1,14) end
end

function draw_hud()
 print("GPT-5.6 Sol",43,3,0)
 print("GPT-5.6 Sol",42,2,7)
 draw_berry({x=0,y=1,got=false})
 print("x"..score,9,11,7)
 if demo and not win then print("demo",108,11,6) end
end

function _draw()
 draw_background()

 for ty=0,15 do
  for tx=0,15 do
   if tile(tx,ty)=="#" then draw_rock(tx,ty) end
  end
 end
 for s in all(spikes) do draw_spike(s) end
 for b in all(berries) do draw_berry(b) end
 draw_goal()

 for q in all(trail) do draw_player_at(q.x,q.y,true) end
 if dead==0 or dead%3==0 then draw_player_at(x,y,false) end
 draw_hud()

 if win then
  rectfill(35,48,92,67,0)
  rect(35,48,92,67,7)
  print("CLEAR!",52,52,7)
  print("berry "..score.."/2",46,60,14)
 end
end
