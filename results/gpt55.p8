pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
-- design notes:
-- celeste traits: crisp 30fps run/jump, hitstop dash, fast retries.
-- constants: run 1.2, jump -3.6, grav .35, dash 4.8 for 8f.
-- forced dash: the 40px final gap beats the ~24px run-jump by 8+px.
-- route: intro right jump, left reversal, berry detour, center jump.
-- climax: up-right dash to a high ledge, then grounded horizontal dash.
-- demo collects the upper-left strawberry and skips the risky lower berry.

-- controls: btn0/1 move, btn2/3 aim dash, btnp4 jump, btnp5 dash.

cart_name="GPT-5.5"
gif_name="gpt55.gif"

level={
"................",
"................",
"................",
"................",
"................",
"................",
"................",
".........#.....#",
"................",
".........^......",
".###..####......",
"........^.......",
".....####.......",
"................",
"#####.....^^^^..",
"#####.....####.."
}

spawn_x=10
spawn_y=106
maxrun=1.2
acc=.38
fric=.78
grav=.35
jump_v=-3.6
fallmax=3
dash_spd=4.8
dash_len=8

goal={x=116,y=39,w=12,h=19}
berries={
 {x=18,y=62,got=false},
 {x=100,y=90,got=false}
}
snow={}
trail={}
ih={}
ip={}

function _init()
 srand(9)
 deaths=0
 score=0
 demo=true
 demo_rec=true
 gif_done=false
 clear_t=0
 demo_phase=0
 phase_t=0
 win=false
 reset_berries()
 reset_player()
 init_snow()
 extcmd("set_filename",gif_name)
 extcmd("rec_frames")
end

function reset_berries()
 for b in all(berries) do
  b.got=false
 end
 score=0
end

function reset_player()
 p={x=spawn_x,y=spawn_y,w=6,h=6,vx=0,vy=0,ground=true,
  can_dash=true,dash=0,freeze=0,face=1}
end

function cancel_demo()
 demo=false
 demo_rec=false
 win=false
 clear_t=0
 gif_done=false
 demo_phase=0
 phase_t=0
 reset_berries()
 reset_player()
end

function init_snow()
 snow={}
 for i=1,24 do
  add(snow,{x=rnd(128),y=rnd(128),s=.25+rnd(.5)})
 end
end

function tile(tx,ty)
 if ty<0 or ty>15 then return "." end
 if tx<0 or tx>15 then return "#" end
 return sub(level[ty+1],tx+1,tx+1)
end

function solid_tile(tx,ty)
 return tile(tx,ty)=="#"
end

function solid_px(x,y)
 if x<0 or x>127 then return true end
 if y<0 then return false end
 if y>127 then return false end
 return solid_tile(flr(x/8),flr(y/8))
end

function hit_solid(x,y)
 return solid_px(x,y) or solid_px(x+p.w-1,y) or
  solid_px(x,y+p.h-1) or solid_px(x+p.w-1,y+p.h-1)
end

function touch_ground()
 return solid_px(p.x,p.y+p.h) or solid_px(p.x+p.w-1,p.y+p.h)
end

function move_x(dx)
 local left=abs(dx)
 local step=sgn(dx)
 while left>0 do
  local m=min(1,left)*step
  p.x+=m
  if hit_solid(p.x,p.y) then
   p.x-=m
   p.vx=0
   return
  end
  left-=abs(m)
 end
end

function move_y(dy)
 local left=abs(dy)
 local step=sgn(dy)
 while left>0 do
  local m=min(1,left)*step
  p.y+=m
  if hit_solid(p.x,p.y) then
   p.y-=m
   if dy>0 then p.ground=true p.can_dash=true end
   p.vy=0
   return
  end
  left-=abs(m)
 end
end

function overlap(ax1,ay1,ax2,ay2,bx1,by1,bx2,by2)
 return ax1<bx2 and ax2>bx1 and ay1<by2 and ay2>by1
end

function spike_hit()
 if p.vy<0 then return false end
 local ax1=p.x+1
 local ay1=p.y+1
 local ax2=p.x+p.w-2
 local ay2=p.y+p.h
 for ty=0,15 do
  for tx=0,15 do
   if tile(tx,ty)=="^" then
    local sx=tx*8
    local sy=ty*8
    if overlap(ax1,ay1,ax2,ay2,sx+1,sy+3,sx+7,sy+8) then
     return true
    end
   end
  end
 end
 return false
end

function kill_player()
 deaths+=1
 if demo then
  reset_berries()
  demo_phase=0
  phase_t=0
 end
 reset_player()
end

function ib(i)
 return ih[i]
end

function ibp(i)
 return ip[i]
end

function read_input()
 if demo then
  local cancel=false
  for i=0,5 do
   if btnp(i) then cancel=true end
  end
  if cancel then
   cancel_demo()
  else
   demo_ai()
   return
  end
 end
 for i=0,5 do
  ih[i]=btn(i)
  ip[i]=btnp(i)
 end
end

function clear_input()
 for i=0,5 do ih[i]=false ip[i]=false end
end

function set_phase(n)
 demo_phase=n
 phase_t=0
end

function demo_ai()
 clear_input()
 phase_t+=1
 if demo_phase==0 then
  ih[1]=true
  if p.ground and p.y>100 and p.x>28 then ip[4]=true end
  if p.ground and p.y<95 and p.x>34 then set_phase(1) end
 elseif demo_phase==1 then
  ih[0]=true
  if p.ground and p.y>86 and p.y<96 then ip[4]=true end
  if p.ground and p.y<78 and p.x<33 then set_phase(2) end
 elseif demo_phase==2 then
  if not berries[1].got then
   if p.ground and p.y<78 and p.x<33 then ip[4]=true end
   if phase_t<9 then ih[0]=true else ih[1]=true end
  else
   if p.ground then
    set_phase(3)
   else
    if p.x<15 then ih[1]=true end
    if p.x>23 then ih[0]=true end
   end
  end
 elseif demo_phase==3 then
  ih[1]=true
  if p.ground and p.y<78 and p.x>21 and p.x<36 then ip[4]=true end
  if p.ground and p.y<78 and p.x>45 then set_phase(4) end
 elseif demo_phase==4 then
  if p.x<44 then ih[1]=true end
  if p.x>47 then ih[0]=true end
  if p.ground and p.x>=44 and p.x<=47 then set_phase(5) end
 elseif demo_phase==5 then
  if phase_t==1 and p.ground then ip[4]=true end
  if phase_t==5 then ih[1]=true ih[2]=true ip[5]=true end
  if phase_t>8 then
   if p.x<72 then ih[1]=true end
   if p.x>78 then ih[0]=true end
  end
  if p.ground and p.y<54 then set_phase(6) end
 elseif demo_phase==6 then
  ih[1]=true
  if p.ground and p.x>=76 then set_phase(7) end
 elseif demo_phase==7 then
  ih[1]=true
  if phase_t==1 then ip[5]=true end
  if p.ground and p.y<54 and p.x>104 then set_phase(8) end
 elseif demo_phase==8 then
  ih[1]=true
 end
end

function add_trail()
 add(trail,{x=p.x,y=p.y,t=10})
 if #trail>22 then del(trail,trail[1]) end
end

function start_dash()
 local dx=0
 local dy=0
 if ib(0) then dx-=1 end
 if ib(1) then dx+=1 end
 if ib(2) then dy-=1 end
 if ib(3) then dy+=1 end
 if dx==0 and dy==0 then dx=p.face end
 if dx!=0 and dy!=0 then
  dx*=.7071
  dy*=.7071
 end
 p.vx=dx*dash_spd
 p.vy=dy*dash_spd
 p.dash=dash_len
 p.freeze=2
 p.can_dash=false
 add_trail()
end

function update_player()
 if p.freeze>0 then
  p.freeze-=1
  return
 end
 if p.dash>0 then
  add_trail()
  p.dash-=1
  p.ground=false
  move_x(p.vx)
  move_y(p.vy)
  if p.dash==0 then
   p.vx*=.45
   p.vy*=.25
  end
 else
  local ax=0
  if ib(0) then ax-=acc p.face=-1 end
  if ib(1) then ax+=acc p.face=1 end
  if ax==0 then p.vx*=fric else p.vx+=ax end
  p.vx=mid(-maxrun,p.vx,maxrun)
  if ibp(4) and p.ground then
   p.vy=jump_v
   p.ground=false
  end
  if ibp(5) and p.can_dash then
   start_dash()
   return
  end
  p.vy=min(fallmax,p.vy+grav)
  p.ground=false
  move_x(p.vx)
  move_y(p.vy)
 end
 if touch_ground() and p.dash<=0 then
  p.ground=true
  p.can_dash=true
 end
 if spike_hit() or p.y>130 then kill_player() end
end

function update_strawberries()
 for b in all(berries) do
  if not b.got then
   local cx=p.x+3
   local cy=p.y+3
   if abs(cx-b.x)<=6 and abs(cy-b.y)<=6 then
    b.got=true
    score+=1
   end
  end
 end
end

function check_goal()
 if overlap(p.x,p.y,p.x+p.w,p.y+p.h,goal.x,goal.y,goal.x+goal.w,goal.y+goal.h) then
  win=true
  p.vx=0
  p.vy=0
 end
end

function update_particles()
 for s in all(snow) do
  s.y+=s.s
  s.x+=.05
  if s.y>127 then
   s.y=0
   s.x=rnd(128)
  end
  if s.x>127 then s.x=0 end
 end
 for t in all(trail) do
  t.t-=1
  if t.t<=0 then del(trail,t) end
 end
end

function update_gif()
 if demo_rec and not gif_done then
  clear_t+=1
  if clear_t>=45 then
   extcmd("video",4,1)
   gif_done=true
  end
 end
end

function _update()
 if win then
  update_gif()
  return
 end
 read_input()
 update_particles()
 update_player()
 update_strawberries()
 check_goal()
end

function draw_bg()
 cls(12)
 rectfill(30,14,122,127,0)
 rectfill(38,24,97,45,5)
 rectfill(62,20,78,64,0)
 rectfill(85,32,118,52,1)
 rectfill(30,76,120,96,1)
 rectfill(12,118,127,127,12)
 for y=0,127,8 do
  if y%24!=8 then rectfill(0,y,4,y+7,7) end
  if y%32!=16 then rectfill(123,y,127,y+7,7) end
 end
 rectfill(4,0,13,22,7)
 rectfill(5,54,20,61,7)
 rectfill(104,84,127,91,7)
 line(35,92,66,50,5)
 line(36,93,67,51,5)
 line(68,51,98,91,5)
 for i=1,18 do
  pset((i*17)%128,(i*29)%128,7)
 end
 for s in all(snow) do
  pset(s.x,s.y,7)
 end
end

function draw_solid(x,y,tx,ty)
 rectfill(x,y,x+7,y+7,5)
 rectfill(x+6,y,x+7,y+7,0)
 rectfill(x,y+6,x+7,y+7,1)
 if not solid_tile(tx,ty-1) then
  rectfill(x,y,x+7,y+2,7)
  if (tx+ty)%3==0 then pset(x+2,y+1,12) end
 end
 if (tx*5+ty)%4==0 then pset(x+3,y+5,6) end
end

function draw_spike(x,y)
 line(x+1,y+7,x+3,y+2,6)
 line(x+3,y+2,x+5,y+7,7)
 line(x+2,y+7,x+4,y+3,7)
 line(x+4,y+3,x+6,y+7,6)
end

function draw_level()
 for ty=0,15 do
  for tx=0,15 do
   local c=tile(tx,ty)
   local x=tx*8
   local y=ty*8
   if c=="#" then draw_solid(x,y,tx,ty) end
   if c=="^" then draw_spike(x,y) end
  end
 end
end

function draw_berry(b)
 if b.got then return end
 local x=flr(b.x)
 local y=flr(b.y)
 rectfill(x-1,y-5,x+1,y-4,11)
 pset(x,y-6,3)
 circfill(x-2,y,2,8)
 circfill(x+2,y,2,14)
 circfill(x,y+2,3,8)
 pset(x-2,y-1,7)
 pset(x+1,y+1,7)
end

function draw_goal()
 local x=goal.x+2
 local y=goal.y
 rectfill(x,y+7,x+1,y+19,3)
 rectfill(x+2,y,x+10,y+7,14)
 rectfill(x+6,y+3,x+10,y+10,14)
 rectfill(x+3,y+2,x+5,y+4,8)
 pset(x+8,y+1,7)
end

function draw_player()
 local x=flr(p.x)-1
 local y=flr(p.y)-2
 local hc=8
 if not p.can_dash then hc=12 end
 if p.dash>0 then hc=7 end
 rectfill(x+2,y+5,x+6,y+9,3)
 rectfill(x+3,y+3,x+7,y+6,15)
 if p.face>=0 then
  rectfill(x,y+2,x+4,y+5,hc)
  pset(x+1,y+6,hc)
 else
  rectfill(x+5,y+2,x+8,y+5,hc)
  pset(x+6,y+6,hc)
 end
 pset(x+6,y+4,0)
 rectfill(x+3,y+9,x+4,y+10,1)
 rectfill(x+6,y+9,x+7,y+10,1)
end

function draw_trail()
 for t in all(trail) do
  local c=7
  if t.t<5 then c=6 end
  rectfill(t.x,t.y,t.x+4,t.y+4,c)
 end
end

function draw_hud()
 print(cart_name,49,2,0)
 print(cart_name,48,1,7)
 draw_berry({x=7,y=121,got=false})
 print("x"..score,13,118,7)
 if demo and not win then print("demo",108,2,6) end
end

function draw_clear()
 rectfill(34,47,94,78,0)
 rect(34,47,94,78,7)
 print("clear!",52,55,7)
 print(cart_name,48,65,14)
 print("berry "..score.."/2",47,73,7)
end

function _draw()
 draw_bg()
 draw_goal()
 for b in all(berries) do draw_berry(b) end
 draw_level()
 draw_trail()
 draw_player()
 draw_hud()
 if win then draw_clear() end
end
