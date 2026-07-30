pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
-- snowy navy caverns use gray-brown rock, white caps, cyan ice, and pink focal sprites from the references.
-- movement: run 1/0.6/0.15, gravity .21 to 2, jump -2, and 5px dashes with .7071 diagonals.
-- the row-9 cliff has four empty columns and a three-tile safe landing on the far side.
-- route: rightward introduction, a leftward rising reversal and berry detour, then the dash-gap climax.
-- demo takes one berry, lands three times, reaches the flag, holds CLEAR! for 45 updates, and records.
-- ................
-- ................
-- ................
-- ................
-- ................
-- ................
-- ................
-- ..............g.
-- ..............##
-- ..#######....###
-- b...............
-- ........b^......
-- ..s..###.###....
-- #####^..........
-- .....#..........
-- ................
-- controls: left/right run, up/down aim, o jump, x dash; any input cancels the opening demo.

level={
 "................",
 "................",
 "................",
 "................",
 "................",
 "................",
 "................",
 "..............g.",
 "..............##",
 "..#######....###",
 "b...............",
 "........b^......",
 "..s..###.###....",
 "#####^..........",
 ".....#..........",
 "................"
}

function _init()
 extcmd("set_filename","gpt56-terra.gif")
 extcmd("rec_frames")
 bx={8,0}
 by={11,10}
 berry={false,false}
 score=0
 particles={
  {15,20,7},{28,48,12},{42,27,6},{57,67,7},{75,25,12},{91,57,6},
  {111,31,7},{121,70,12},{19,98,6},{66,105,7},{101,111,12},{46,84,6}
 }
 reset_player()
 demo=true
 gif_ok=true
 phase=0
 phase_time=0
 demo_time=0
 win=false
 win_timer=0
 saved=false
 deaths=0
 trail={}
 t=0
end

function reset_player()
 px=17
 py=98
 vx=0
 vy=0
 grounded=true
 can_dash=true
 facing=1
 hitstop=0
 dash_left=0
 dashing=false
 dead=0
end

function tile(c,r)
 if c<0 or c>15 or r<0 or r>15 then return "." end
 return sub(level[r+1],c+1,c+1)
end

function solid(c,r)
 if c<0 or c>15 then return true end
 return tile(c,r)=="#"
end

function hitsolid(x,y)
 local l=flr(x/8)
 local rr=flr((x+5)/8)
 local top=max(0,flr(y/8))
 local bot=min(15,flr((y+5)/8))
 for r=top,bot do
  for c=l,rr do
   if solid(c,r) then return true end
  end
 end
 return false
end

function move_x(amount)
 while abs(amount)>.001 do
  local step=mid(-1,amount,1)
  if hitsolid(px+step,py) then
   vx=0
   return true
  end
  px+=step
  amount-=step
 end
 return false
end

function move_y(amount)
 while abs(amount)>.001 do
  local step=mid(-1,amount,1)
  if hitsolid(px,py+step) then
   if step>0 then grounded=true end
   vy=0
   return true
  end
  py+=step
  amount-=step
 end
 return false
end

function approach(n,target,amount)
 if n<target then return min(n+amount,target) end
 return max(n-amount,target)
end

function physical_input()
 return btn(0) or btn(1) or btn(2) or btn(3) or btn(4) or btn(5)
end

function normal_input()
 dx=(btn(1) and 1 or 0)-(btn(0) and 1 or 0)
 dy=(btn(3) and 1 or 0)-(btn(2) and 1 or 0)
 jump=btnp(4)
 dash=btnp(5)
end

function demo_input()
 dx=0
 dy=0
 jump=false
 dash=false
 phase_time+=1
 demo_time+=1
 -- The phases mirror the oracle route and wait for each landing to fully settle.
 if phase==0 then
  dx=1
  if phase_time>=10 then phase=1 phase_time=0 end
 elseif phase==1 then
  dx=1
  if grounded then jump=true phase=2 phase_time=0 end
 elseif phase==2 then
  dx=1
  if grounded and py<96 then phase=3 phase_time=0 end
 elseif phase==3 then
  if grounded and abs(vx)<.01 then phase=4 phase_time=0 end
 elseif phase==4 then
  dx=1
  if phase_time>=10 then phase=5 phase_time=0 end
 elseif phase==5 then
  dx=1
  if grounded then jump=true phase=6 phase_time=0 end
 elseif phase==6 then
  dx=1
  if not grounded and phase_time>=5 then
   dash=true phase=7 phase_time=0
  end
 elseif phase==7 then
  dx=1
  if grounded and py>90 then phase=8 phase_time=0 end
 elseif phase==8 then
  if grounded and abs(vx)<.01 then phase=9 phase_time=0 end
 elseif phase==9 then
  dx=-1
  if grounded then jump=true phase=10 phase_time=0 end
 elseif phase==10 then
  dx=-1
  if not grounded and phase_time>=9 then
   dy=-1 dash=true phase=11 phase_time=0
  end
 elseif phase==11 then
  if grounded and py<72 and abs(vx)<.01 then phase=12 phase_time=0 end
 elseif phase==12 then
  dx=1
  if grounded and not hitsolid(px+1,py+1) then
   jump=true phase=13 phase_time=0
  end
 elseif phase==13 then
  dx=1
  if not grounded and phase_time>=1 then
   dy=-1 dash=true phase=14 phase_time=0
  end
 elseif phase==14 then
  dx=1
  if grounded and px>100 and py<72 then phase=15 phase_time=0 end
 elseif phase==15 then
  if grounded and abs(vx)<.01 then phase=16 phase_time=0 end
 elseif phase==16 then
  dx=1
  if grounded then jump=true phase=17 phase_time=0 end
 elseif phase==17 then
  dx=1
 end
end

function start_dash()
 local ax=dx
 local ay=dy
 if ax==0 and ay==0 then ax=facing end
 dash_vx=ax*5
 dash_vy=ay*5
 if ax~=0 and ay~=0 then
  dash_vx*=.7071
  dash_vy*=.7071
 end
 can_dash=false
 hitstop=1
 dash_left=4
 dashing=true
 vx=0
 vy=0
end

function add_trail()
 add(trail,{px+3,py+3,6})
 if #trail>8 then deli(trail,1) end
end

function touch_world()
 if py>=128 then kill() return end
 local l=max(0,flr(px/8))
 local rr=min(15,flr((px+5)/8))
 local top=max(0,flr(py/8))
 local bot=min(15,flr((py+5)/8))
 for r=top,bot do
  for c=l,rr do
   local q=tile(c,r)
   if q=="^" and vy>=0 then kill() return end
   if q=="g" then
    win=true
    win_timer=0
    return
   end
   if q=="b" then
    for i=1,2 do
     if bx[i]==c and by[i]==r and not berry[i] then
      berry[i]=true
      score+=1
     end
    end
   end
  end
 end
end

function kill()
 if dead==0 then
  dead=18
  deaths+=1
  dashing=false
 end
end

function update_player()
 if dead>0 then
  dead-=1
  if dead==0 then
   reset_player()
   if demo then
    demo=false
    gif_ok=false
   end
  end
  return
 end
 if hitstop>0 then
  hitstop-=1
  return
 end
 if dash_left>0 then
  move_x(dash_vx)
  move_y(dash_vy)
  dash_left-=1
  add_trail()
  if dash_left==0 then
   dashing=false
   vx=mid(-1,dash_vx,1)
   vy=dash_vy<=0 and 0 or min(dash_vy,2)
  end
  grounded=hitsolid(px,py+1)
  if grounded then can_dash=true end
  touch_world()
  return
 end
 if dash and can_dash then
  start_dash()
  return
 end
 if dx~=0 then
  facing=dx
  vx=approach(vx,dx,0.6)
 else
  vx=approach(vx,0,0.15)
 end
 vy=min(vy+.21,2)
 if jump and grounded then
  vy=-2
  grounded=false
 end
 grounded=false
 move_x(vx)
 move_y(vy)
 grounded=hitsolid(px,py+1)
 if grounded then can_dash=true end
 touch_world()
end

function _update()
 t+=1
 for q in all(trail) do q[3]-=.5 end
 for i=#trail,1,-1 do if trail[i][3]<=0 then deli(trail,i) end end
 if demo and physical_input() then
  demo=false
  gif_ok=false
  win=false
  reset_player()
  return
 end
 if win then
  if demo and gif_ok then
   win_timer+=1
   if win_timer==45 and not saved then
    extcmd("video",4,1)
    saved=true
   end
  end
  return
 end
 if demo then
  demo_input()
  if demo_time>2600 then
   demo=false
   gif_ok=false
  end
 else
  normal_input()
 end
 update_player()
end

function snowcap(x,y,w)
 rectfill(x,y,x+w-1,y+1,7)
 if w>3 then
  pset(x+2,y+2,6)
  pset(x+w-2,y+2,12)
 end
end

function draw_rock(c,r)
 local x=c*8
 local y=r*8
 rectfill(x,y,x+7,y+7,5)
 rectfill(x+1,y+3,x+6,y+7,5)
 if tile(c,r-1)~="#" then snowcap(x,y,8) end
 if (c+r)%3==0 then pset(x+2,y+5,6) end
 if (c*2+r)%5==0 then pset(x+6,y+6,1) end
 if tile(c-1,r)~="#" then line(x,y+3,x,y+7,6) end
end

function draw_spike(x,y)
 line(x,y+7,x+3,y+1,7)
 line(x+3,y+1,x+7,y+7,7)
 line(x+1,y+7,x+6,y+7,6)
end

function draw_berry(x,y,i)
 if berry[i] then return end
 pset(x+4,y,11)
 pset(x+3,y+1,3)
 pset(x+5,y+1,3)
 rectfill(x+2,y+2,x+6,y+5,8)
 pset(x+1,y+3,14)
 pset(x+7,y+3,14)
 pset(x+3,y+2,14)
 pset(x+3,y+3,7)
 pset(x+5,y+5,2)
 line(x+4,y+1,x+6,y-1,11)
end

function draw_flag(x,y)
 line(x+2,y+7,x+2,y+1,6)
 pset(x+2,y,7)
 rectfill(x+3,y+1,x+7,y+4,8)
 pset(x+6,y+2,14)
 pset(x+3,y+5,5)
end

function draw_player()
 if dead>0 and dead%3==0 then return end
 local x=flr(px)
 local y=flr(py)
 local hair=can_dash and 14 or 5
 rectfill(x+1,y,x+4,y+1,hair)
 pset(x+5,y+1,hair)
 rectfill(x,y+2,x+5,y+5,8)
 pset(x+1,y+2,14)
 pset(x+4,y+3,7)
 pset(x+2,y+5,5)
 if facing<0 then pset(x+1,y+3,7) end
end

function draw_background()
 cls(1)
 rectfill(0,8,127,127,0)
 -- distant linked cavern masses frame the playable void.
 rectfill(0,12,12,108,5)
 rectfill(5,8,37,20,5)
 rectfill(0,101,42,127,5)
 rectfill(91,8,127,30,5)
 rectfill(112,24,127,108,5)
 rectfill(82,108,127,127,5)
 rectfill(36,114,99,127,1)
 rectfill(16,24,27,31,1)
 rectfill(72,18,89,24,1)
 for p in all(particles) do
  if (t+p[1])%23<2 then pset(p[1],p[2],p[3]) end
 end
 -- icy frame highlights break the silhouettes without making a HUD bar.
 line(0,13,12,13,12)
 line(5,21,35,21,6)
 line(0,110,39,110,6)
 line(92,31,127,31,6)
 line(113,109,127,109,12)
end

function _draw()
 draw_background()
 for r=0,15 do
  for c=0,15 do
   local q=tile(c,r)
   if q=="#" then draw_rock(c,r) end
  end
 end
 for r=0,15 do
  for c=0,15 do
   local q=tile(c,r)
   local x=c*8
   local y=r*8
   if q=="^" then draw_spike(x,y)
   elseif q=="g" then draw_flag(x,y)
   elseif q=="b" then
    for i=1,2 do if bx[i]==c and by[i]==r then draw_berry(x,y,i) end end
   end
  end
 end
 for q in all(trail) do
  circfill(q[1],q[2],max(0,q[3]/3),7)
 end
 draw_player()
 print("GPT-5.6 Terra",39,1,1)
 print("GPT-5.6 Terra",38,0,7)
 print("berries:"..score.."/2",2,9,6)
 if demo and not win then print("attract",92,9,5) end
 if win then
  print("clear!",50,45,1)
  print("clear!",49,44,7)
  print("summit reached",35,57,14)
 end
end
