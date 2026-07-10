pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
-- design: compact snowy ascent, crisp retries, berries and bright celeste-like silhouettes.
-- physics: run 1.5, jump 3.2, gravity .18, fall 2.5; dash 5 for 8 frames.
-- dash gate: a 48px pillar beats the 28px jump; diagonal jump-dash rises 57px.
-- route: dash onto its 16px safe top, then climb snowy steps past two avoidable spikes.
-- controls: left/right move, z(btn 4) jumps, arrows aim and x(btn 5) dashes.

lvl={
 "................",
 "................",
 "................",
 "...............F",
 "...............#",
 "...........^*###",
 "...........#####",
 "......^.*#######",
 "......##########",
 "......##########",
 "......##########",
 "......##########",
 "......##########",
 "......##########",
 "################",
 "################"
}

function cell(tx,ty)
 if tx<0 or tx>15 then return "#" end
 if ty<0 or ty>15 then return "." end
 return sub(lvl[ty+1],tx+1,tx+1)
end

function overlap(ax,ay,aw,ah,bx,by,bw,bh)
 return ax<bx+bw and ax+aw>bx and ay<by+bh and ay+ah>by
end

function boxsolid(x,y,w,h)
 local x0=flr(x/8)
 local x1=flr((x+w-1)/8)
 local y0=flr(y/8)
 local y1=flr((y+h-1)/8)
 for ty=y0,y1 do
  for tx=x0,x1 do
   if cell(tx,ty)=="#" then return true end
  end
 end
 return false
end

function ground()
 return boxsolid(p.x,p.y+1,p.w,p.h)
end

function approach(v,target,step)
 if v<target then return min(v+step,target) end
 if v>target then return max(v-step,target) end
 return target
end

function move_x(amount)
 local n=max(1,ceil(abs(amount)))
 local step=amount/n
 for i=1,n do
  if boxsolid(p.x+step,p.y,p.w,p.h) then
   p.vx=0
   return
  end
  p.x+=step
 end
end

function move_y(amount)
 local n=max(1,ceil(abs(amount)))
 local step=amount/n
 for i=1,n do
  if boxsolid(p.x,p.y+step,p.w,p.h) then
   p.vy=0
   return
  end
  p.y+=step
 end
end

function respawn()
 p={x=17,y=105,w=6,h=7,vx=0,vy=0,face=1}
 can_dash=true
 dash_t=0
 freeze=0
 dead_t=0
end

function burst(x,y,col,n)
 for i=1,n do
  add(motes,{x=x,y=y,vx=rnd(2)-1,vy=rnd(2)-1.4,life=8+rnd(8),col=col})
 end
end

function kill_player()
 if dead_t>0 or win then return end
 deaths+=1
 dead_t=9
 p.vx=0
 p.vy=0
 burst(p.x+3,p.y+3,8,8)
end

function spike_hit()
 if p.vy<0 then return false end
 local x0=flr(p.x/8)
 local x1=flr((p.x+p.w-1)/8)
 local y0=flr(p.y/8)
 local y1=flr((p.y+p.h-1)/8)
 for ty=y0,y1 do
  for tx=x0,x1 do
   if cell(tx,ty)=="^" and p.y+p.h>ty*8+2 then
    return true
   end
  end
 end
 return false
end

function start_dash()
 local dx=0
 local dy=0
 if btn(0) then dx-=1 end
 if btn(1) then dx+=1 end
 if btn(2) then dy-=1 end
 if btn(3) then dy+=1 end
 if dx==0 and dy==0 then dx=p.face end
 if dx!=0 then p.face=dx>0 and 1 or -1 end
 if dx!=0 and dy!=0 then
  dx*=0.707106
  dy*=0.707106
 end
 p.vx=dx*5
 p.vy=dy*5
 dash_t=8
 freeze=2
 can_dash=false
 burst(p.x+3,p.y+3,7,4)
end

function update_fx()
 for s in all(snow) do
  s.y+=s.spd
  s.x+=sin((tick+s.phase)/90)*0.08
  if s.y>127 then
   s.y=-2
   s.x=rnd(128)
  end
  if s.x<0 then s.x=127 end
  if s.x>127 then s.x=0 end
 end
 for i=#trails,1,-1 do
  local q=trails[i]
  q.life-=1
  if q.life<=0 then deli(trails,i) end
 end
 for i=#motes,1,-1 do
  local q=motes[i]
  q.x+=q.vx
  q.y+=q.vy
  q.vy+=0.08
  q.life-=1
  if q.life<=0 then deli(motes,i) end
 end
end

function check_items()
 for b in all(berries) do
  if not b.got and overlap(p.x,p.y,p.w,p.h,b.x,b.y,8,8) then
   b.got=true
   score+=1
   burst(b.x+4,b.y+4,14,10)
  end
 end
 if overlap(p.x,p.y,p.w,p.h,goal_x,goal_y,8,8) then
  win=true
  p.vx=0
  p.vy=0
  burst(goal_x+4,goal_y+3,7,12)
 end
end

function _init()
 berries={}
 snow={}
 trails={}
 motes={}
 score=0
 deaths=0
 win=false
 tick=0
 goal_x=96
 goal_y=8
 for ty=0,15 do
  for tx=0,15 do
   local c=cell(tx,ty)
   if c=="*" then add(berries,{x=tx*8,y=ty*8,got=false,phase=rnd(1)}) end
   if c=="F" then goal_x=tx*8 goal_y=ty*8 end
  end
 end
 for i=1,22 do
  add(snow,{x=rnd(128),y=rnd(128),spd=0.12+rnd(0.25),phase=rnd(90)})
 end
 respawn()
end

function _update()
 if win then return end
 tick+=1
 update_fx()
 if dead_t>0 then
  dead_t-=1
  if dead_t==0 then respawn() end
  return
 end
 if freeze>0 then
  freeze-=1
  return
 end

 local onground=ground()
 if onground then can_dash=true end
 if btnp(5) and can_dash then
  start_dash()
  return
 end

 if dash_t>0 then
  add(trails,{x=p.x,y=p.y,life=7})
  move_x(p.vx)
  move_y(p.vy)
  dash_t-=1
  if dash_t==0 then
   p.vx*=0.35
   p.vy*=0.35
  end
 else
  local dir=0
  if btn(0) then dir-=1 end
  if btn(1) then dir+=1 end
  if dir!=0 then
   p.face=dir
   p.vx=approach(p.vx,dir*1.5,0.35)
  else
   p.vx=approach(p.vx,0,0.25)
  end
  if btnp(4) and onground then
   p.vy=-3.2
   burst(p.x+3,p.y+7,7,3)
  end
  p.vy=min(p.vy+0.18,2.5)
  move_x(p.vx)
  move_y(p.vy)
 end

 if ground() then can_dash=true end
 check_items()
 if p.y>130 or spike_hit() then kill_player() end
end

function draw_bg()
 cls(12)
 for y=20,96 do
  local w=(y-20)*0.78
  line(49-w,y,49+w,y,5)
 end
 for y=20,35 do
  local w=(y-20)*0.78
  line(49-w,y,49+w,y,7)
 end
 for y=43,116 do
  local w=(y-43)*0.58
  line(101-w,y,101+w,y,1)
 end
 line(0,87,28,56,1)
 line(0,88,39,88,1)
 for i=0,6 do
  pset((i*19+11)%128,(i*31+9)%76,7)
 end
end

function draw_solid(tx,ty)
 local x=tx*8
 local y=ty*8
 rectfill(x,y,x+7,y+7,1)
 if cell(tx,ty-1)!="#" then
  line(x,y,x+7,y,7)
  line(x,y+1,x+7,y+1,6)
  if (tx+ty)%3==0 then pset(x+6,y+2,7) end
 end
 if cell(tx-1,ty)!="#" then line(x,y+2,x,y+7,5) end
 if cell(tx+1,ty)!="#" then line(x+7,y+2,x+7,y+7,5) end
 if (tx*3+ty)%5==0 then pset(x+3,y+5,5) end
end

function draw_spike(tx,ty)
 local x=tx*8
 local y=ty*8
 for k=0,1 do
  local q=x+k*4
  line(q,y+7,q+2,y+1,7)
  line(q+2,y+1,q+3,y+7,7)
  pset(q+2,y+5,6)
 end
end

function draw_berry(b)
 local y=b.y+sin((tick+b.phase*90)/45)
 circfill(b.x+3,y+4,3,8)
 circfill(b.x+5,y+4,2,14)
 pset(b.x+2,y+3,7)
 pset(b.x+4,y+6,2)
 line(b.x+3,y+1,b.x+1,y,11)
 line(b.x+4,y+1,b.x+6,y,3)
end

function draw_flag()
 line(goal_x+1,goal_y+1,goal_x+1,goal_y+9,7)
 rectfill(goal_x+2,goal_y+1,goal_x+7,goal_y+5,8)
 line(goal_x+3,goal_y+1,goal_x+7,goal_y+1,14)
 pset(goal_x+6,goal_y+4,2)
end

function draw_player()
 if dead_t>0 and dead_t%2==0 then return end
 local x=flr(p.x)
 local y=flr(p.y)
 local hair=can_dash and 8 or 12
 if dash_t>0 then hair=7 end
 if p.face>0 then
  rectfill(x-2,y+1,x+1,y+4,hair)
  pset(x-3,y+3,hair)
 else
  rectfill(x+4,y+1,x+7,y+4,hair)
  pset(x+8,y+3,hair)
 end
 rectfill(x+1,y+1,x+4,y+4,15)
 rectfill(x+1,y,x+4,y+1,hair)
 pset(x+(p.face>0 and 4 or 1),y+2,0)
 rectfill(x+1,y+5,x+4,y+6,3)
 pset(x,y+6,11)
 pset(x+5,y+6,11)
end

function draw_hud()
 rectfill(2,2,34,10,1)
 circfill(7,6,2,8)
 pset(7,3,11)
 print("x"..score,11,4,7)
 print("d:"..deaths,39,4,7)
 if tick<150 and not win then
  rectfill(34,116,94,124,1)
  print("z jump  x dash",37,118,7)
 end
end

function _draw()
 draw_bg()
 for ty=0,15 do
  for tx=0,15 do
   local c=cell(tx,ty)
   if c=="#" then draw_solid(tx,ty) end
   if c=="^" then draw_spike(tx,ty) end
  end
 end
 for q in all(trails) do
  local col=q.life>3 and 7 or 6
  rectfill(q.x,q.y+1,q.x+4,q.y+5,col)
 end
 for b in all(berries) do
  if not b.got then draw_berry(b) end
 end
 draw_flag()
 for s in all(snow) do
  pset(s.x,s.y,s.spd>0.25 and 7 or 6)
 end
 for q in all(motes) do pset(q.x,q.y,q.col) end
 draw_player()
 draw_hud()
 if win then
  rectfill(29,49,98,76,1)
  rect(29,49,98,76,7)
  print("* clear! *",45,56,7)
  print(score.." berries",47,66,14)
 end
end
