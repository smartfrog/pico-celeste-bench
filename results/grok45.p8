pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
-- design notes:
-- celeste classic: run/jump/8-dir dash, hair=can_dash, snow, fast retry
-- consts: maxrun=1 accel=.6 grav=.21 maxfall=2 jump=-2 dash=5 t=4 freeze=2
-- forced dash: 32px gap tiles4-7; run-jump~20px, jump+dash~50px
-- controls: left/right move, up/down aim dash, o jump, x dash

function _init()
 deaths=0
 score=0
 win=false
 freeze=0
 particles={}
 trails={}
 snow={}
 for i=1,28 do
  add(snow,{x=rnd(128),y=rnd(128),s=.25+rnd(.8),c=7})
 end
 build_level()
 spawn_player()
end

function build_level()
 -- solid(c,r) needs air(c,r-1) to stand on.
 -- gap tiles 4-7 = 32px forces dash (run-jump~20).
 -- stairs: each step +1 col left-edge so air sits above lower ledge.
 -- air above every standable solid. stairs +1 col/row filled.
 -- gap tiles 4-7 = 32px forces dash (run-jump~20).
 local rows={
  "................",
  "................",
  "................",
  "................",
  "...............F",
  "....*..........#",
  "...###........##",
  ".............###",
  "............####",
  "..*........#####",
  ".####.....######",
  ".........#######",
  "####....########",
  "#..#^^^^########",
  "################",
  "################",
 }
 mapdata={}
 berries={}
 spikes={}
 flag=nil
 for ty=0,15 do
  mapdata[ty]={}
  local row=rows[ty+1]
  for tx=0,15 do
   local ch=sub(row,tx+1,tx+1)
   local t=0
   if ch=="#" then t=1
   elseif ch=="^" then
    t=2
    add(spikes,{x=tx*8,y=ty*8})
   elseif ch=="*" then
    add(berries,{x=tx*8+1,y=ty*8+1,got=false,w=6,h=6})
   elseif ch=="F" then
    flag={x=tx*8,y=ty*8}
   end
   mapdata[ty][tx]=t
  end
 end
 spawn={x=12,y=88}
end

function spawn_player()
 p={
  x=spawn.x,y=spawn.y,
  dx=0,dy=0,
  remx=0,remy=0,
  face=1,
  can_dash=true,
  dash_t=0,
  grace=0,
  jbuf=0,
  on_ground=false,
  hit={x=1,y=3,w=6,h=5},
  anim=0,
 }
 trails={}
end

function solid_at(x,y,w,h)
 local x0=flr(x/8)
 local x1=flr((x+w-.001)/8)
 local y0=flr(y/8)
 local y1=flr((y+h-.001)/8)
 for ty=y0,y1 do
  for tx=x0,x1 do
   if tx<0 or tx>15 or ty>15 then return true end
   if ty>=0 and mapdata[ty][tx]==1 then return true end
  end
 end
 return false
end

function appr(v,t,a)
 if v>t then return max(v-a,t) end
 return min(v+a,t)
end

function sign(v)
 if v>0 then return 1 elseif v<0 then return -1 else return 0 end
end

function move_x(amt)
 local step=sign(amt)
 for i=1,abs(amt) do
  if not solid_at(p.x+p.hit.x+step,p.y+p.hit.y,p.hit.w,p.hit.h) then
   p.x+=step
  else
   p.dx=0
   p.remx=0
   return
  end
 end
end

function move_y(amt)
 local step=sign(amt)
 for i=1,abs(amt) do
  if not solid_at(p.x+p.hit.x,p.y+p.hit.y+step,p.hit.w,p.hit.h) then
   p.y+=step
  else
   p.dy=0
   p.remy=0
   return
  end
 end
end

function move_player()
 p.remx+=p.dx
 local ax=flr(p.remx+.5)
 p.remx-=ax
 move_x(ax)
 p.remy+=p.dy
 local ay=flr(p.remy+.5)
 p.remy-=ay
 move_y(ay)
end

function spike_hit()
 local hx=p.x+p.hit.x
 local hy=p.y+p.hit.y
 local hw=p.hit.w
 local hh=p.hit.h
 for s in all(spikes) do
  -- up-spikes: kill only when falling; tight hitbox
  local sx=s.x+1
  local sy=s.y+5
  if hx+hw>sx and hx<sx+6 and hy+hh>sy and hy<sy+3 then
   if p.dy>=0 then return true end
  end
 end
 return false
end

function kill_player()
 deaths+=1
 for i=1,10 do
  add(particles,{
   x=p.x+4,y=p.y+4,
   dx=rnd(3)-1.5,dy=rnd(3)-1.5,
   t=18,c=8+flr(rnd(2))
  })
 end
 spawn_player()
end

function _update()
 for s in all(snow) do
  s.y+=s.s
  s.x+=sin(s.y/50)*.25
  if s.y>128 then
   s.y=-1
   s.x=rnd(128)
  end
 end
 for pt in all(particles) do
  pt.x+=pt.dx
  pt.y+=pt.dy
  pt.dy+=.05
  pt.t-=1
  if pt.t<=0 then del(particles,pt) end
 end
 for tr in all(trails) do
  tr.t-=1
  if tr.t<=0 then del(trails,tr) end
 end

 if win then return end
 if freeze>0 then
  freeze-=1
  return
 end

 local input=0
 if btn(1) then input=1
 elseif btn(0) then input=-1 end

 p.on_ground=solid_at(p.x+p.hit.x,p.y+p.hit.y+1,p.hit.w,p.hit.h)

 if p.on_ground then
  p.grace=6
  p.can_dash=true
 elseif p.grace>0 then
  p.grace-=1
 end

 if btnp(4) then p.jbuf=4
 elseif p.jbuf>0 then p.jbuf-=1 end

 if p.dash_t>0 then
  p.dash_t-=1
  add(trails,{x=p.x+1,y=p.y+2,t=7})
  if p.dash_t==0 then
   if abs(p.dx)>2 then p.dx=sign(p.dx)*2 end
   if abs(p.dy)>2 then p.dy=sign(p.dy)*2 end
  end
 else
  local maxrun=1
  local accel=.6
  local deccel=.15
  if not p.on_ground then accel=.4 end
  if abs(p.dx)>maxrun then
   p.dx=appr(p.dx,sign(p.dx)*maxrun,deccel)
  else
   p.dx=appr(p.dx,input*maxrun,accel)
  end
  if p.dx!=0 then p.face=sign(p.dx) end

  local maxfall=2
  local grav=.21
  if abs(p.dy)<=.15 then grav*=.5 end
  if not p.on_ground then
   p.dy=appr(p.dy,maxfall,grav)
  end

  if p.jbuf>0 and p.grace>0 then
   p.jbuf=0
   p.grace=0
   p.dy=-2
   add(particles,{x=p.x+3,y=p.y+7,dx=0,dy=.4,t=8,c=6})
  end

  if btnp(5) and p.can_dash then
   local dx=0
   local dy=0
   if btn(0) then dx-=1 end
   if btn(1) then dx+=1 end
   if btn(2) then dy-=1 end
   if btn(3) then dy+=1 end
   if dx==0 and dy==0 then dx=p.face end
   if dx!=0 and dy!=0 then
    dx*=.707
    dy*=.707
   end
   p.dx=dx*5
   p.dy=dy*5
   p.dash_t=4
   p.can_dash=false
   freeze=2
   for i=1,4 do
    add(particles,{
     x=p.x+4,y=p.y+4,
     dx=rnd(2)-1,dy=rnd(2)-1,
     t=8,c=7
    })
   end
  end
 end

 move_player()

 if spike_hit() or p.y>128 then
  kill_player()
  return
 end

 for b in all(berries) do
  if not b.got then
   if p.x+p.hit.x+p.hit.w>b.x and p.x+p.hit.x<b.x+b.w
    and p.y+p.hit.y+p.hit.h>b.y and p.y+p.hit.y<b.y+b.h then
    b.got=true
    score+=1
    for i=1,8 do
     add(particles,{
      x=b.x+3,y=b.y+3,
      dx=rnd(2)-1,dy=rnd(2)-1.5,
      t=20,c=8
     })
    end
   end
  end
 end

 if flag then
  if p.x+p.hit.x+p.hit.w>flag.x+1 and p.x+p.hit.x<flag.x+7
   and p.y+p.hit.y+p.hit.h>flag.y and p.y+p.hit.y<flag.y+8 then
   win=true
  end
 end

 p.anim+=.25
end

function draw_tile(tx,ty)
 local x=tx*8
 local y=ty*8
 rectfill(x,y,x+7,y+7,1)
 rectfill(x,y,x+7,y+2,7)
 line(x,y+2,x+7,y+2,6)
 rectfill(x,y+3,x+7,y+7,12)
 pset(x+1,y+1,6)
 pset(x+4,y,6)
 pset(x+2,y+5,13)
 pset(x+6,y+4,13)
 pset(x+5,y+6,1)
end

function draw_spike(s)
 local x=s.x
 local y=s.y
 for i=0,3 do
  line(x+3-i,y+7-i,x+4+i,y+7-i,6)
 end
 line(x+3,y+1,x+3,y+7,7)
 line(x+4,y+1,x+4,y+7,7)
 pset(x+3,y,7)
 pset(x+4,y,7)
end

function draw_berry(b)
 if b.got then return end
 local x=b.x
 local y=b.y
 local bob=sin(time()*2+x)*.8
 circfill(x+3,y+3+bob,3,8)
 pset(x+2,y+2+bob,14)
 pset(x+4,y+4+bob,2)
 pset(x+3,y+bob,11)
 pset(x+2,y-1+bob,11)
 pset(x+4,y-1+bob,3)
end

function draw_flag(f)
 local x=f.x
 local y=f.y
 local wave=flr(sin(time()*2.5)*1.5)
 line(x+2,y,x+2,y+7,6)
 line(x+3,y,x+3,y+7,7)
 rectfill(x+4,y+1,x+7+wave,y+4,8)
 pset(x+5,y+2,14)
 pset(x+6,y+3,2)
end

function draw_player()
 local x=flr(p.x)
 local y=flr(p.y)
 -- hair: red=dash ready, blue=used, white=dashing
 local hc=8
 if p.dash_t>0 then hc=7
 elseif not p.can_dash then hc=12 end
 circfill(x+3,y+1,2,hc)
 circfill(x+2,y+2,2,hc)
 circfill(x+5,y+2,2,hc)
 if p.face<0 then
  circfill(x,y+2,2,hc)
  circfill(x+1,y+3,1,hc)
 else
  circfill(x+7,y+2,2,hc)
  circfill(x+6,y+3,1,hc)
 end
 rectfill(x+2,y+3,x+5,y+6,15)
 if p.face>=0 then
  pset(x+3,y+4,0)
  pset(x+5,y+4,0)
 else
  pset(x+2,y+4,0)
  pset(x+4,y+4,0)
 end
 rectfill(x+2,y+6,x+5,y+7,3)
 if p.on_ground and abs(p.dx)>.2 then
  if flr(p.anim)%2==0 then
   pset(x+2,y+7,1)
   pset(x+5,y+7,10)
  else
   pset(x+3,y+7,10)
   pset(x+4,y+7,1)
  end
 end
end

function _draw()
 cls(1)
 rectfill(24,16,100,110,0)
 rectfill(16,40,70,120,13)
 rectfill(64,24,120,100,0)
 rectfill(48,56,104,120,13)
 for i=0,10 do
  rectfill(0,i*8,6+i%3,i*8+7,12)
  rectfill(122-i%3,i*8,127,i*8+7,12)
 end

 for s in all(snow) do
  pset(s.x,s.y,s.c)
 end

 for ty=0,15 do
  for tx=0,15 do
   if mapdata[ty][tx]==1 then draw_tile(tx,ty) end
  end
 end

 for s in all(spikes) do draw_spike(s) end
 for b in all(berries) do draw_berry(b) end
 if flag then draw_flag(flag) end

 for tr in all(trails) do
  circfill(tr.x+2,tr.y+2,tr.t>3 and 2 or 1,7)
 end

 for pt in all(particles) do
  pset(pt.x,pt.y,pt.c or 7)
 end

 if not win then draw_player() end

 print("x"..score,2,2,7)
 print("d"..deaths,18,2,6)

 if win then
  rectfill(26,50,102,78,0)
  rectfill(28,52,100,76,1)
  print("clear!",48,56,7)
  print("berries:"..score,36,66,8)
 end
end
