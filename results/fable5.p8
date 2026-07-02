pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
-- snowridge -- a celeste classic homage
-- emulates: readable 128x128 look, run/jump + 8-way normalized dash with
--  hitstop and white trail, ground-only dash recharge, hair dash indicator
--  (red=ready, blue=spent), spike death + instant respawn, berries, goal flag.
-- constants (30fps): maxrun 1, accel .6, grav .21, maxfall 2, jump -2, dash 5/4f.
-- forced dash: 4-tile spiked pit (32px) beats max run-jump (~19px); wide safe landing.
-- controls: btn(0/1)=move, btn(2)=aim up, btn(3)=aim down, btnp(4)=jump, btnp(5)=dash

lvl={
"................",
"................",
"................",
"................",
"................",
"................",
"................",
"................",
"..........b.....",
"w......b......fg",
"#.....g......g##",
"#....###....####",
"#p.g^...#.......",
"#########^^^^###",
"################",
"################"}

maxrun=1 acc=0.6 dcc=0.2
grav=0.21 maxfall=2 jumpv=2
dspd=5 dtime0=4 freeze0=2

function tat(x,y)
 if x<0 or x>15 or y>15 then return "#" end
 if y<0 then return "." end
 return sub(lvl[y+1],x+1,x+1)
end

function solid(x,y,w,h)
 for cx=flr(x/8),flr((x+w-1)/8) do
  for cy=flr(y/8),flr((y+h-1)/8) do
   if tat(cx,cy)=="#" then return true end
  end
 end
 return false
end

function appr(v,t,a)
 return v>t and max(v-a,t) or min(v+a,t)
end

function sg(v)
 return v>0 and 1 or (v<0 and -1 or 0)
end

function boxhit(x,y,w,h,x2,y2,w2,h2)
 return x<x2+w2 and x+w>x2 and y<y2+h2 and y+h>y2
end

function reset_player()
 p={x=px0,y=py0,dx=0,dy=0,fac=1,
  can_dash=true,dtime=0,ddx=0,ddy=0,
  grace=0,jbuf=0,dead=0}
 hair={{x=px0,y=py0},{x=px0,y=py0}}
 freeze=0
end

function _init()
 berries={} spikes={} parts={} snow={}
 got=0 win=false fr=0 deaths=0
 for y=0,15 do
  for x=0,15 do
   local c=tat(x,y)
   if c=="p" then px0=x*8 py0=y*8 end
   if c=="b" then add(berries,{x=x*8,y=y*8,got=false,t=rnd(1)}) end
   if c=="f" then fx=x*8 fy=y*8 end
   if c=="^" then add(spikes,{x=x*8,y=y*8}) end
  end
 end
 for i=1,25 do
  add(snow,{x=rnd(128),y=rnd(128),s=0.5+rnd(1.5)})
 end
 reset_player()
end

function kill()
 if p.dead>0 then return end
 p.dead=15
 deaths+=1
 for i=1,16 do
  local a=rnd(1)
  add(parts,{x=p.x+4,y=p.y+4,
   dx=cos(a)*(1+rnd(2)),dy=sin(a)*(1+rnd(2)),
   t=8+rnd(5),c=rnd(1)<0.5 and 7 or 8,r=1+rnd(1)})
 end
end

function movex(a)
 local d=sg(a) local n=abs(a)
 while n>0 do
  local s=min(n,1) n-=s
  if solid(p.x+d*s+1,p.y+2,6,6) then
   p.dx=0 p.ddx=0 break
  end
  p.x+=d*s
 end
end

function movey(a)
 local d=sg(a) local n=abs(a)
 while n>0 do
  local s=min(n,1) n-=s
  if solid(p.x+1,p.y+d*s+2,6,6) then
   if d>0 then p.y=flr(p.y) end
   p.dy=0 p.ddy=0 break
  end
  p.y+=d*s
 end
end

function upd_player()
 local ong=solid(p.x+1,p.y+8,6,1)
 if ong then
  p.grace=4
  p.can_dash=true
 elseif p.grace>0 then
  p.grace-=1
 end
 if p.jbuf>0 then p.jbuf-=1 end
 if btnp(4) then p.jbuf=4 end

 local ix=(btn(1) and 1 or 0)-(btn(0) and 1 or 0)
 if ix!=0 then p.fac=ix end

 -- dash start
 if btnp(5) and p.can_dash then
  local dx=ix
  local dy=(btn(3) and 1 or 0)-(btn(2) and 1 or 0)
  if dx==0 and dy==0 then dx=p.fac end
  local sp=dspd
  if dx!=0 and dy!=0 then sp*=0.7071 end
  p.ddx=dx*sp p.ddy=dy*sp
  p.dx=p.ddx p.dy=p.ddy
  p.dtime=dtime0
  freeze=freeze0
  p.can_dash=false
  return
 end

 if p.dtime>0 then
  -- dashing: no gravity, no run accel, fixed velocity + white trail
  p.dtime-=1
  p.dx=p.ddx p.dy=p.ddy
  add(parts,{x=p.x+4,y=p.y+4,dx=0,dy=0,t=5,c=7,r=2.5})
  if p.dtime==0 then
   p.dx=sg(p.ddx)*2
   p.dy=sg(p.ddy)*0.75
  end
 else
  -- run
  if abs(p.dx)>maxrun then
   p.dx=appr(p.dx,sg(p.dx)*maxrun,dcc)
  else
   p.dx=appr(p.dx,ix*maxrun,ong and acc or acc*0.8)
  end
  -- gravity w/ apex float
  local g=grav
  if abs(p.dy)<=0.15 then g*=0.5 end
  if not ong then p.dy=appr(p.dy,maxfall,g) end
  -- jump (buffered + coyote)
  if p.jbuf>0 and p.grace>0 then
   p.jbuf=0 p.grace=0
   p.dy=-jumpv
   for i=1,3 do
    add(parts,{x=p.x+1+rnd(6),y=p.y+7,dx=rnd(0.8)-0.4,dy=-rnd(0.4),t=5,c=7,r=1})
   end
  end
 end

 movex(p.dx)
 movey(p.dy)

 if p.y<0 then p.y=0 if p.dy<0 then p.dy=0 end end
 if p.y>120 then kill() end

 -- spikes (up-spikes hurt while falling/standing)
 if p.dy>=0 then
  for s in all(spikes) do
   if boxhit(p.x+1,p.y+2,6,6,s.x,s.y+3,8,5) then kill() end
  end
 end

 -- berries
 for b in all(berries) do
  if not b.got and boxhit(p.x+1,p.y+2,6,6,b.x,b.y,8,8) then
   b.got=true got+=1
   add(parts,{x=b.x+1,y=b.y,dx=0,dy=-0.8,t=20,c=7,r=0,txt="1000"})
   for i=1,6 do
    local a=rnd(1)
    add(parts,{x=b.x+4,y=b.y+4,dx=cos(a)*2,dy=sin(a)*2,t=6,c=7,r=1})
   end
  end
 end

 -- goal
 if boxhit(p.x+1,p.y+2,6,6,fx,fy,8,8) then
  win=true
 end
end

function upd_hair()
 local ax,ay=p.x+4-p.fac*2,p.y+1
 hair[1].x+=(ax-hair[1].x)*0.5
 hair[1].y+=(ay-hair[1].y)*0.5
 hair[2].x+=(hair[1].x-hair[2].x)*0.5
 hair[2].y+=(hair[1].y-hair[2].y)*0.5
end

function _update()
 fr+=1
 if freeze>0 then freeze-=1 return end
 if win then return end
 -- ambient snow
 for s in all(snow) do
  s.x-=s.s
  s.y+=0.3+s.s*0.2
  if s.x<-2 then s.x=130 end
  if s.y>130 then s.y=-2 end
 end
 -- particles
 for pt in all(parts) do
  pt.t-=1 pt.x+=pt.dx pt.y+=pt.dy
  if pt.t<=0 then del(parts,pt) end
 end
 for b in all(berries) do b.t+=0.04 end
 if p.dead>0 then
  p.dead-=1
  if p.dead<=0 then reset_player() end
  return
 end
 upd_player()
 upd_hair()
end

function _draw()
 cls(12)
 -- terrain: snowy tops, rock, dark caves deeper in
 palt(0,false)
 for cy=0,15 do
  for cx=0,15 do
   if tat(cx,cy)=="#" then
    local s=3
    if tat(cx,cy-1)!="#" then s=4
    elseif tat(cx,cy-2)=="#" then s=5 end
    spr(s,cx*8,cy*8)
   end
  end
 end
 palt()
 -- spikes + decor
 for cy=0,15 do
  for cx=0,15 do
   local t=tat(cx,cy)
   if t=="^" then spr(6,cx*8,cy*8)
   elseif t=="g" then spr(11,cx*8,cy*8)
   elseif t=="w" then spr(10,cx*8,cy*8) end
  end
 end
 -- flag
 spr(8+flr(fr/8)%2,fx,fy)
 -- berries
 for b in all(berries) do
  if not b.got then
   spr(7,b.x,b.y+sin(b.t)*1.5)
  end
 end
 -- particles + dash trail
 for pt in all(parts) do
  if pt.txt then
   print(pt.txt,pt.x,pt.y,pt.c)
  else
   circfill(pt.x,pt.y,pt.r*(pt.t/8+0.3),pt.c)
  end
 end
 -- player + hair (hair color = dash indicator)
 if p.dead<=0 then
  local hc=p.can_dash and 8 or 12
  circfill(hair[2].x,hair[2].y,1,hc)
  circfill(hair[1].x,hair[1].y,2,hc)
  if not p.can_dash then pal(8,12) end
  local sp=1
  local ix=(btn(1) and 1 or 0)-(btn(0) and 1 or 0)
  if not solid(p.x+1,p.y+8,6,1) then sp=2
  elseif ix!=0 and flr(fr/4)%2==0 then sp=2 end
  spr(sp,p.x,p.y,1,1,p.fac<0)
  pal()
 end
 -- ambient snow
 for s in all(snow) do
  pset(s.x,s.y,7)
  if s.s>1.4 then pset(s.x+1,s.y,7) end
 end
 -- hud
 spr(7,2,2)
 print("x"..got,11,4,7)
 -- victory
 if win then
  rectfill(28,50,99,74,0)
  rect(28,50,99,74,7)
  print("clear!",52,56,7)
  print("berries:"..got.."/2",42,66,14)
 end
end
__gfx__
00000000000000000000000055555555777777770000000000000000000000000600000006000000000000000000000000000000000000000000000000000000
0000000000000000000000005555555577777777000111000000000000300b0b06888800060888000ee0ee000000000000000000000000000000000000000000
000000000088888000888880555055557577775700000000000000000003b33006888880068888800eeeee000000000000000000000000000000000000000000
0000000008888888088888885555555555555555011000000007000700288882068888000608880000e8e0000000000000000000000000000000000000000000
00000000088ffff8088ffff8555111555555555500000011000700070089888806000000060000000eeeee000003000000000000000000000000000000000000
0000000008f1ff1808f1ff18555550555550555500000000006770670088889806000000060000000ee3ee00000b000b00000000000000000000000000000000
0000000000fffff000fffff050555555555555550011100005676567008898880600000006000000000b00000003000b00000000000000000000000000000000
00000000003333000733303055555555555550550000c00005666566002888820600000006000000000b00000000b0b300000000000000000000000000000000
