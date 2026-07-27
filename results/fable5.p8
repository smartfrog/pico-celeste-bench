pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
-- fable 5
-- design notes:
-- celeste classic homage: 30fps run/jump/8-dir dash, dash recharges
-- only on ground, hair color shows dash state, snow, fast retries.
-- constants: run 1, acc .6, dec .15, grav .21 (half at apex),
-- jump -2, dash 5 (diag *.7071), 4f dash + 2f freeze.
-- forced obstacle: 4-tile 32px air gap, jump+dash only.
-- route: intro flat jump over spikes -> rising jump to spiked ledge ->
-- up-left diag dash (reversal+vertical) -> optional left berry detour
-- (demo takes it) -> climax right dash over big gap -> step-up to flag.
--
-- controls:
-- btn(0)/btn(1) move left/right
-- btn(2)/btn(3) aim dash up/down
-- btnp(4) jump, btnp(5) dash

name="fable 5"

lvl={
"................",
"................",
"................",
"................",
"................",
"................",
"................",
"................",
".....o..........",
"...............f",
"^ow...g......g^#",
"###.####....###r",
"...............r",
"..g.......##...r",
"####^^###...^^^r",
"################",
}

function tl(tx,ty)
 if tx<0 or tx>15 then return "#" end
 if ty<0 then return "." end
 if ty>15 then return "#" end
 return sub(lvl[ty+1],tx+1,tx+1)
end

function isol(c)
 return c=="#" or c=="r" or c=="i"
end

function sol(x,y)
 return isol(tl(flr(x/8),flr(y/8)))
end

-- player hitbox: x+1..x+6, y+2..y+7 (6x6)
function bsol(x,y)
 return sol(x+1,y+2) or sol(x+6,y+2)
  or sol(x+1,y+7) or sol(x+6,y+7)
end

function pinit()
 p={x=8,y=104,vx=0,vy=0,rx=0,ry=0,f=1,g=false,cd=true,
    dt=0,fz=0,dvx=0,dvy=0,jb=0,cy=0}
end

function reset()
 pinit()
 berries={}
 for ty=0,15 do
  for tx=0,15 do
   if tl(tx,ty)=="o" then
    add(berries,{x=tx*8,y=ty*8,got=false})
   end
  end
 end
 score=0
 win=false
 winf=0
 dead=0
 trail={}
 ds=1
end

function respawn()
 pinit()
 if demo then ds=1 end
end

function _init()
 fr=0
 deaths=0
 snow={}
 for i=1,28 do
  add(snow,{x=rnd(128),y=rnd(128),s=0.3+rnd(0.7)})
 end
 demo=true
 gifd=false
 reset()
 extcmd("set_filename","fable5.gif")
 extcmd("rec_frames")
end

-- demo: deterministic input script (logical buttons only)
function dstep()
 local l,r,u,d,j,x=false,false,false,false,false,false
 local g,px=p.g,p.x
 if ds==1 then r=true if g and px>=24 then j=true ds=2 end
 elseif ds==2 then r=true if g and px>=44 then ds=3 end
 elseif ds==3 then r=true if g and px>=60 then j=true ds=4 end
 elseif ds==4 then r=true if px>=76 then ds=5 end
 elseif ds==5 then if g then ds=6 end
 elseif ds==6 then l=true u=true x=true ds=7
 elseif ds==7 then l=true u=true if g and p.dt<=0 and p.fz<=0 then ds=8 end
 elseif ds==8 then l=true if g and px<=34 then j=true ds=9 end
 elseif ds==9 then l=true if g and px<=12 then ds=10 end
 elseif ds==10 then r=true if g and px>=15 then j=true ds=11 end
 elseif ds==11 then r=true if g and px>=36 then ds=12 end
 elseif ds==12 then r=true if g and px>=55 then j=true ds=13 end
 elseif ds==13 then r=true if not g and px>=64 then x=true ds=14 end
 elseif ds==14 then r=true if g and px>=90 then ds=15 end
 elseif ds==15 then if g then ds=16 end
 elseif ds==16 then r=true if g and px>=104 then j=true ds=17 end
 elseif ds==17 then r=true
 end
 return l,r,u,d,j,x
end

k={} pk={}
for i=0,5 do k[i]=false pk[i]=false end

function getinp()
 for i=0,5 do pk[i]=k[i] end
 if demo then
  local l,r,u,d,j,x=dstep()
  k[0],k[1],k[2],k[3],k[4],k[5]=l,r,u,d,j,x
 else
  for i=0,5 do k[i]=btn(i) end
 end
end

function prs(i)
 return k[i] and not pk[i]
end

function kill()
 deaths+=1
 dead=10
 dx0=p.x dy0=p.y
end

function hazards()
 local x1,y1,x2,y2=p.x+1,p.y+2,p.x+6,p.y+7
 for ty=max(0,flr(y1/8)),flr(y2/8) do
  for tx=flr(x1/8),flr(x2/8) do
   local c=tl(tx,ty)
   if c=="^" and p.vy>=0 and y2>=ty*8+3 then
    kill()
    return
   end
   if c=="f" then
    win=true
    winf=0
   end
  end
 end
 for b in all(berries) do
  if not b.got and x2>=b.x and x1<=b.x+7
   and y2>=b.y and y1<=b.y+7 then
   b.got=true
   score+=1
  end
 end
end

function movex()
 p.rx+=p.vx
 local a=flr(p.rx+0.5)
 p.rx-=a
 local s=sgn(a)
 for i=1,abs(a) do
  if bsol(p.x+s,p.y) then
   p.vx=0 p.rx=0
   break
  end
  p.x+=s
 end
end

function movey()
 p.ry+=p.vy
 local a=flr(p.ry+0.5)
 p.ry-=a
 local s=sgn(a)
 for i=1,abs(a) do
  if bsol(p.x,p.y+s) then
   p.vy=0 p.ry=0
   break
  end
  p.y+=s
 end
end

function _update()
 fr+=1
 -- ambient snow
 for s in all(snow) do
  s.y+=s.s
  s.x-=s.s*0.4
  if s.y>128 then s.y=-2 s.x=rnd(128) end
  if s.x<0 then s.x+=128 end
 end
 -- dash trail fade
 for t in all(trail) do
  t.t-=1
  if t.t<=0 then del(trail,t) end
 end
 -- demo cancel on any user button
 if demo and not win then
  for i=0,5 do
   if btn(i) then
    demo=false
    reset()
    return
   end
  end
 end
 if win then
  winf+=1
  if demo and not gifd and winf==45 then
   extcmd("video",4,1)
   gifd=true
  end
  return
 end
 if dead>0 then
  dead-=1
  if dead==0 then respawn() end
  return
 end
 getinp()
 if p.fz>0 then
  p.fz-=1
  return
 end
 local l,r,u,d=k[0],k[1],k[2],k[3]
 local jp,dp=prs(4),prs(5)
 if l then p.f=-1 elseif r then p.f=1 end
 p.g=bsol(p.x,p.y+1)
 if p.g then
  p.cy=4
  if p.dt<=0 then p.cd=true end
 elseif p.cy>0 then
  p.cy-=1
 end
 if jp then p.jb=4 elseif p.jb>0 then p.jb-=1 end
 -- start dash
 if dp and p.cd then
  local dx,dy=0,0
  if l then dx=-1 elseif r then dx=1 end
  if u then dy=-1 elseif d then dy=1 end
  if dx==0 and dy==0 then dx=p.f end
  local m=1
  if dx~=0 and dy~=0 then m=0.70710678 end
  p.dvx=dx*5*m
  p.dvy=dy*5*m
  p.dt=4
  p.fz=2
  p.cd=false
  return
 end
 if p.dt>0 then
  -- dashing: no gravity, no run accel
  p.dt-=1
  p.vx=p.dvx
  p.vy=p.dvy
  add(trail,{x=p.x,y=p.y,t=8})
  if p.dt==0 then
   if p.dvx~=0 then p.vx=sgn(p.dvx) else p.vx=0 end
   if p.dvy<0 then p.vy=-1.5
   elseif p.dvy>0 then p.vy=1
   else p.vy=0 end
  end
 else
  local ax=0
  if l then ax-=1 end
  if r then ax+=1 end
  if ax~=0 then
   p.vx=mid(-1,p.vx+ax*0.6,1)
  elseif abs(p.vx)>0.15 then
   p.vx-=sgn(p.vx)*0.15
  else
   p.vx=0
  end
  if not p.g then
   local gg=0.21
   if abs(p.vy)<=0.15 then gg=0.105 end
   p.vy=min(p.vy+gg,2)
  end
  if p.jb>0 and p.cy>0 then
   p.vy=-2
   p.jb=0
   p.cy=0
   p.g=false
  end
 end
 movex()
 movey()
 hazards()
end

function drawplayer()
 local hc=p.cd and 8 or 12
 -- trailing hair blob
 circfill(p.x+4-p.f*3,p.y+3,1,hc)
 circfill(p.x+4-p.f*2,p.y+2,2,hc)
 pal(8,hc)
 spr(1,p.x,p.y,1,1,p.f==-1)
 pal()
end

function _draw()
 cls(0)
 -- icy sky openings (background)
 rectfill(0,0,14,55,12)
 line(15,0,15,55,7)
 pset(16,12,7) pset(16,30,7) pset(16,44,7)
 rectfill(114,0,127,38,12)
 line(113,0,113,38,7)
 line(114,39,127,39,7)
 pset(112,8,7) pset(112,26,7)
 -- cave background bands
 rectfill(18,16,110,22,1)
 rectfill(24,44,110,50,1)
 rectfill(0,70,54,76,1)
 rectfill(64,98,127,104,1)
 -- tiles
 for ty=0,15 do
  for tx=0,15 do
   local c=tl(tx,ty)
   if c=="#" then spr(2,tx*8,ty*8)
   elseif c=="r" then spr(3,tx*8,ty*8)
   elseif c=="i" then spr(9,tx*8,ty*8)
   elseif c=="^" then spr(4,tx*8,ty*8)
   elseif c=="f" then spr(6,tx*8,ty*8)
   elseif c=="g" then spr(7,tx*8,ty*8)
   elseif c=="w" then spr(8,tx*8,ty*8)
   end
  end
 end
 -- berries
 for b in all(berries) do
  if not b.got then
   spr(5,b.x,b.y+sin(fr/40))
  end
 end
 -- white dash trail
 for t in all(trail) do
  circfill(t.x+4,t.y+4,t.t/3,7)
 end
 -- player
 if dead>0 then
  circ(dx0+4,dy0+4,(10-dead)*1.4,7)
 else
  drawplayer()
 end
 -- snow
 for s in all(snow) do
  pset(s.x,s.y,7)
 end
 -- ui: cartridge name always at top
 print(name,51,3,1)
 print(name,50,2,7)
 spr(5,1,1)
 print("x"..score,10,3,7)
 if demo and not win then
  print("demo",56,121,6)
 end
 if win then
  rectfill(38,55,90,71,0)
  rect(38,55,90,71,7)
  print("clear!",53,61,7)
 end
end
__gfx__
0000000000888800777777775555555500000000000b30006888800000000000000e000077777777000000000000000000000000000000000000000000000000
00000000088888807fffff7f505555150000000000888800688888000000000000e8e0007ccccccc000000000000000000000000000000000000000000000000
00000000088ff1f0ff7fffff5555055507000070087888806888800000000000000e0000cc7ccccc000000000000000000000000000000000000000000000000
00000000088ffff0fffff7ff5155555507000070088888806888000000000000000b0000ccccc7cc000000000000000000000000000000000000000000000000
0000000003bbbb307fffffff55555055077007700888888060000000000b0000000b30007ccccccc000000000000000000000000000000000000000000000000
0000000003bbbb30ff7ffff7055555510770077002888820600000000b0b00b0000b0000ccc7cccc000000000000000000000000000000000000000000000000
0000000000300300fffff7ff555155556770077600288200600000000b3b0b30000b0000ccccccc7000000000000000000000000000000000000000000000000
0000000000f00f00ffffffff5555555577777777000000006000000003b33b3000b3b000cccccccc000000000000000000000000000000000000000000000000
