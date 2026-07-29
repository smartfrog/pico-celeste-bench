pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
-- qwen 3.8 max: snowy cavern celeste-like. palette 12 ice sky/river,5/6 grey-brown rock,4 warm speck,7 snow,1 navy ledge,0 cave void,8 red focal,3 green stem,15 skin
-- constants run1 accel.6 decel.15 grav.21 maxfall2 jump-2 dash5 diag.7071; 2 hitstop+4 move; 6x6 box; dash recharges only on ground
-- gap row12 cols5-8 (4 empty) crossed run-to-edge+jump+horizontal dash (4f delay) onto 4-wide ledge cols8-11; spikes constrain right descent
-- route: spawn left -> dash up-right intro ledge -> up-dash detour grabs left berry -> dash right across gap -> reversal climb -> goal
-- demo: state controller from oracle move list (7 phases), collects the detour berry only (score 1), saves qwen38.gif
-- controls btn0/1 move, btn2/3 aim dash, btnp4 jump, btnp5 dash; any physical input cancels demo into human play
--
-- ................
-- ................
-- ................
-- .............g..
-- ............##..
-- ................
-- ................
-- ...........##...
-- ................
-- .........##.....
-- ...b............
-- ..............b.
-- ...##....####^^.
-- .............##.
-- s...........^^..
-- ###.........##..

grid={
"................",
"................",
"................",
".............g..",
"............##..",
"................",
"................",
"...........##...",
"................",
".........##.....",
"...b............",
"..............b.",
"...##....####^^.",
".............##.",
"s...........^^..",
"###.........##.."
}

max_run=1
accel=0.6
decel=0.15
grav=0.21
max_fall=2
jump_vel=-2
dash_speed=5
diag=0.7071

player_x=2
player_y=114
player_vx=0
player_vy=0
grounded=false
can_dash=true
dashing=false
dash_timer=0
hitstop=0
dash_dx=0
dash_dy=0
facing=1
score=0
win=false
deaths=0
win_timer=0
berry1=false
berry2=false

demo=true
demo_phase=0
demo_timer=0
demo_sub=0
demo_rc=0
demo_ac=0
demo_took=false
gif_saved=false
demo_l=false
demo_r=false
demo_u=false
demo_d=false
demo_jump=false
demo_dash=false

trail={}
parts={}

specs={
 {dr=1,run=0,dd=8,ddx=1,ddy=-1},
 {dr=0,run=0,dd=9999,ddx=0,ddy=0},
 {dr=1,edge=true,dd=4,ddx=1,ddy=0},
 {dr=-1,run=0,dd=8,ddx=1,ddy=-1},
 {dr=1,run=0,dd=0,ddx=1,ddy=-1},
 {dr=-1,run=0,dd=8,ddx=1,ddy=-1},
 {dr=1,run=9999,dd=9999,ddx=0,ddy=0,walk=true}
}

function _init()
 extcmd("set_filename","qwen38.gif")
 extcmd("rec_frames")
 for i=1,14 do
  add(parts,{x=rnd(128),y=rnd(128),s=0.15+rnd(0.35)})
 end
 respawn()
end

function respawn()
 player_x=1
 player_y=114
 player_vx=0
 player_vy=0
 grounded=false
 can_dash=true
 dashing=false
 dash_timer=0
 hitstop=0
 facing=1
 trail={}
 score=0
 berry1=false
 berry2=false
 demo_phase=0
 demo_sub=0
 demo_rc=0
 demo_ac=0
 demo_took=false
 demo_dashfired=false
 demo_timer=0
end

function is_solid(c,r)
 if c<0 or c>15 or r<0 or r>15 then return true end
 return sub(grid[r+1],c+1,c+1)=="#"
end

function is_spike(c,r)
 if c<0 or c>15 or r<0 or r>15 then return false end
 return sub(grid[r+1],c+1,c+1)=="^"
end

function hit_solid(x,y,w,h)
 local l=flr(x/8)
 local r=flr((x+w-1)/8)
 local t=flr(y/8)
 local b=flr((y+h-1)/8)
 for row=t,b do
  for col=l,r do
   if is_solid(col,row) then return true end
  end
 end
 return false
end

function approach(v,t,r)
 if v<t then v+=r if v>t then v=t end
 elseif v>t then v-=r if v<t then v=t end
 end
 return v
end

function probe()
 return hit_solid(player_x,player_y+1,6,6)
end

function move_ax_h(d)
 local rem=d
 while abs(rem)>0.0001 do
  local s=mid(-1,rem,1)
  if hit_solid(player_x+s,player_y,6,6) then return true end
  player_x+=s
  rem-=s
 end
 return false
end

function move_ax_v(d)
 local rem=d
 while abs(rem)>0.0001 do
  local s=mid(-1,rem,1)
  if hit_solid(player_x,player_y+s,6,6) then return true end
  player_y+=s
  rem-=s
 end
 return false
end

function box_hit(c,r)
 local x0=c*8 y0=r*8
 return not(player_x+6<=x0 or player_x>=x0+8 or player_y+6<=y0 or player_y>=y0+8)
end

function _update()
 if win then
  win_timer-=1
  if win_timer==0 and not gif_saved and demo then
   extcmd("video",4,1)
   gif_saved=true
  end
  upd_parts()
  return
 end
 if demo then
  for i=0,5 do
   if btn(i) then demo=false respawn() return end
  end
  demo_update()
 end
 local il,ir,iu,id,jp,dp
 if demo then
  il=demo_l ir=demo_r iu=demo_u id=demo_d
  jp=demo_jump dp=demo_dash
 else
  il=btn(0) ir=btn(1) iu=btn(2) id=btn(3)
  jp=btnp(4) dp=btnp(5)
 end
 if hitstop>0 then hitstop-=1 return end
 if dashing then
  add(trail,{x=player_x+3,y=player_y+3,t=6})
  move_ax_h(dash_dx)
  move_ax_v(dash_dy)
  dash_timer-=1
  if dash_timer<=0 then
   dashing=false
   player_vx=mid(-max_run,dash_dx,max_run)
   player_vy=dash_dy<=0 and 0 or mid(0,dash_dy,max_fall)
  end
  grounded=probe()
  if grounded then can_dash=true end
  check_spikes() check_berries() check_goal()
  if player_y>130 then deaths+=1 respawn() end
  upd_trail() upd_parts()
  return
 end
 local dx=0
 if il and not ir then dx=-1 facing=-1
 elseif ir and not il then dx=1 facing=1 end
 if dx!=0 then
  player_vx=approach(player_vx,max_run*dx,accel)
 else
  player_vx=approach(player_vx,0,decel)
 end
 player_vy=approach(player_vy,max_fall,grav)
 if jp and grounded then player_vy=jump_vel end
 if dp and can_dash then
  local adx=0 ady=0
  if il and not ir then adx=-1 end
  if ir and not il then adx=1 end
  if iu and not id then ady=-1 end
  if id and not iu then ady=1 end
  if adx==0 and ady==0 then adx=facing end
  local vx=adx*dash_speed vy=ady*dash_speed
  if adx!=0 and ady!=0 then vx=vx*diag vy=vy*diag end
  dash_dx=vx dash_dy=vy
  can_dash=false
  dashing=true
  hitstop=1
  dash_timer=4
  player_vx=0 player_vy=0
  upd_trail() upd_parts()
  return
 end
 if move_ax_h(player_vx) then player_vx=0 end
 if move_ax_v(player_vy) then if player_vy>0 then grounded=true end player_vy=0 end
 grounded=probe()
 if grounded then can_dash=true end
 check_spikes() check_berries() check_goal()
 if player_y>130 then deaths+=1 respawn() end
 upd_trail() upd_parts()
end

function upd_trail()
 for i=#trail,1,-1 do
  trail[i].t-=1
  if trail[i].t<=0 then del(trail,trail[i]) end
 end
end

function upd_parts()
 for p in all(parts) do
  p.y+=p.s
  if p.y>128 then p.y=-2 p.x=rnd(128) end
 end
end

function check_spikes()
 if player_vy<0 then return end
 local l=flr(player_x/8) r=flr((player_x+5)/8)
 local t=flr(player_y/8) b=flr((player_y+5)/8)
 for row=t,b do
  for col=l,r do
   if is_spike(col,row) then deaths+=1 respawn() return end
  end
 end
end

function check_berries()
 if not berry1 and box_hit(3,10) then berry1=true score+=1 end
 if not berry2 and box_hit(14,11) then berry2=true score+=1 end
end

function check_goal()
 if box_hit(13,3) then win=true win_timer=45 end
end

function set_dir(d)
 demo_l=false demo_r=false demo_u=false demo_d=false
 if d==1 then demo_r=true
 elseif d==-1 then demo_l=true
 end
end

function set_dash_dir(sp)
 demo_l=false demo_r=false demo_u=false demo_d=false
 if sp.ddx==1 then demo_r=true
 elseif sp.ddx==-1 then demo_l=true end
 if sp.ddy==-1 then demo_u=true
 elseif sp.ddy==1 then demo_d=true end
end

function at_edge(d)
 local fr=flr((player_y+6)/8)
 local ac=d>0 and flr((player_x+6)/8) or flr((player_x-1)/8)
 return not is_solid(ac,fr)
end

function demo_update()
 demo_jump=false demo_dash=false
 demo_timer+=1
 local sp=specs[demo_phase+1]
 if sp.walk then
  set_dir(sp.dr)
  if demo_timer>2700 then demo=false deaths+=1 respawn() end
  return
 end
 if demo_sub==0 then
  set_dir(sp.dr)
  if grounded then
   local go=false
   if sp.edge then go=at_edge(sp.dr)
   elseif sp.run and sp.run>0 then
    demo_rc+=1 go=demo_rc>sp.run
   else go=true end
   if go then
    demo_jump=true
    demo_took=true
    demo_sub=1
    demo_ac=0
    demo_dashfired=false
   end
  end
 elseif demo_sub==1 then
  local hold=demo_dashfired and sgn(dash_dx) or sp.dr
  set_dir(hold)
  if not demo_dashfired and demo_ac==sp.dd then
   demo_dash=true
   demo_dashfired=true
   set_dash_dir(sp)
  end
  demo_ac+=1
  if demo_took and grounded then
   demo_phase+=1
   demo_sub=0
   demo_rc=0
   demo_took=false
   demo_dashfired=false
  end
 end
 if demo_timer>2700 then
  demo=false deaths+=1 respawn()
 end
end

function _draw()
 draw_bg()
 draw_terrain()
 draw_spikes()
 draw_berries()
 draw_goal()
 draw_trail()
 draw_player()
 draw_parts()
 print("qwen 3.8 max",41,2,0)
 print("qwen 3.8 max",40,1,7)
 rectfill(1,118,18,126,0)
 print(score.."/2",2,120,7)
 if win then
  rectfill(38,55,90,69,0)
  print("clear!",49,61,0)
  print("clear!",48,60,7)
 end
end

function draw_bg()
 cls(12)
 rectfill(0,8,22,18,1)
 rectfill(48,8,72,14,1)
 rectfill(104,8,127,16,1)
 rectfill(0,40,40,127,5)
 rectfill(40,8,64,40,5)
 rectfill(64,16,127,127,5)
 rectfill(40,80,64,127,5)
 rectfill(8,52,30,78,0)
 rectfill(20,96,40,120,0)
 rectfill(44,40,52,127,12)
 rectfill(52,40,62,72,0)
 rectfill(70,40,92,64,0)
 rectfill(96,52,116,80,0)
 rectfill(70,96,92,124,0)
 rectfill(44,58,52,64,1)
 rectfill(70,72,92,78,1)
 rectfill(96,96,116,102,1)
 rectfill(20,108,40,114,1)
 line(46,16,46,40,12)
 line(50,14,50,40,12)
 line(110,16,110,52,12)
 for x=2,124,6 do
  for y=18,124,9 do
   if (x*3+y*5)%13==0 then pset(x,y,6) end
   if (x*5+y*2)%17==0 then pset(x+1,y+2,4) end
  end
 end
 snow_line(0,8,22)
 snow_line(48,8,72)
 snow_line(104,8,127)
 snow_line(64,16,127)
 snow_line(40,8,64)
end

function snow_line(x0,y0,x1)
 for x=x0,x1 do
  if (x*7+y0)%3~=0 then pset(x,y0,7) end
  if (x*3+y0)%5==0 then pset(x,y0+1,7) end
 end
end

function draw_terrain()
 for y=0,15 do
  for x=0,15 do
   local ch=sub(grid[y+1],x+1,x+1)
   if ch=="#" then
    local bx=x*8 by=y*8
    local top=y==0 or sub(grid[y],x+1,x+1)~="#"
    rectfill(bx,by,bx+7,by+7,5)
    pset(bx+2,by+4,6)
    pset(bx+5,by+6,6)
    pset(bx+6,by+3,4)
    if (x*7+y*3)%5==0 then pset(bx+3,by+5,4) end
    if top then
     rectfill(bx,by,bx+7,by+1,7)
     if (x+y)%3==0 then pset(bx+3,by+2,7) end
     if (x*2+y)%4==0 then pset(bx+6,by+2,7) end
     if (x+y)%2==0 then pset(bx+1,by+6,12) end
    end
    local left=x==0 or sub(grid[y+1],x,x)~="#"
    local right=x==15 or sub(grid[y+1],x+2,x+2)~="#"
    if left then rectfill(bx,by,bx,by+7,6) end
    if right then rectfill(bx+7,by,bx+7,by+7,6) end
   end
  end
 end
end

function draw_spikes()
 for y=0,15 do
  for x=0,15 do
   if is_spike(x,y) then
    local bx=x*8 by=y*8
    rectfill(bx,by+6,bx+7,by+7,7)
    for i=0,3 do
     line(bx+i*2,by+6,bx+i*2+1,by+1,7)
     line(bx+i*2+1,by+1,bx+i*2+2,by+6,6)
    end
    pset(bx+1,by+2,6)
    pset(bx+5,by+2,6)
   end
  end
 end
end

function draw_berries()
 if not berry1 then draw_berry(28,84) end
 if not berry2 then draw_berry(116,92) end
end

function draw_berry(bx,by)
 circfill(bx,by,3,8)
 circfill(bx-1,by-1,1,14)
 pset(bx+1,by+1,7)
 rectfill(bx-1,by-5,bx+1,by-3,3)
 pset(bx,by-6,3)
 pset(bx+2,by-4,11)
end

function draw_goal()
 local gx=13*8 gy=3*8
 rectfill(gx+3,gy,4+gx,gy+7,7)
 rectfill(gx+4,gy,gx+7,gy+3,8)
 rectfill(gx+5,gy+1,gx+6,gy+2,14)
 pset(gx+3,gy,6)
end

function draw_trail()
 for t in all(trail) do
  circfill(flr(t.x),flr(t.y),1,7)
 end
end

function draw_player()
 local px=flr(player_x) py=flr(player_y)
 local hc=can_dash and 8 or 1
 rectfill(px,py,px+5,py+1,hc)
 rectfill(px-1,py+1,px+6,py+1,hc)
 rectfill(px+1,py+2,px+4,py+3,15)
 pset(px+2,py+2,0)
 pset(px+3,py+2,0)
 rectfill(px+1,py+4,px+4,py+5,3)
 if facing==1 then pset(px+4,py+3,15) else pset(px+1,py+3,15) end
end

function draw_parts()
 for p in all(parts) do
  pset(flr(p.x),flr(p.y),7)
 end
end
