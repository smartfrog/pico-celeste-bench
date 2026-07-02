pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
-- design notes (celeste classic-like)
-- feel: run spd 1, grav .21 (half at apex), maxfall 2, jump vy -2, coyote+jbuffer.
-- dash: 8-dir, spd 5 (diag*.707), 6f, 2f freeze, no gravity; red hair=ready,blue=used.
-- forced dash: a 32px (4-tile) pit; run-jump reaches ~22px, jump+dash ~57px.
-- controls: btn0/1 move, btn2/3 aim dash up/down, btnp4 jump, btnp5 dash.

function _init()
 srand(1)
 lvl={
  "####........####",
  "##............##",
  "................",
  "#...............",
  "#...............",
  "#...............",
  "#...............",
  "#...............",
  "#...............",
  "#...............",
  "#............x.f",
  "#..........x..##",
  "#p.^.^......####",
  "#######....#####",
  "#######....#####",
  "#######....#####",
 }
 solids={}
 spikes={}
 straws={}
 for r=0,15 do
  solids[r]={}
  for c=0,15 do
   local ch=sub(lvl[r+1],c+1,c+1)
   solids[r][c]=(ch=="#")
   if ch=="^" then add(spikes,{x=c*8,y=r*8}) end
   if ch=="x" then add(straws,{x=c*8,y=r*8,got=false}) end
   if ch=="f" then goal={x=c*8,y=r*8} end
   if ch=="p" then startx=c*8 starty=r*8 end
  end
 end
 score=0
 win=false
 trail={}
 parts={}
 for i=1,26 do
  add(parts,{x=rnd(128),y=rnd(128),s=0.2+rnd(0.5),vx=-0.15-rnd(0.25)})
 end
 respawn()
end

function respawn()
 p={
  x=startx,y=starty,
  vx=0,vy=0,rx=0,ry=0,
  flip=false,
  can_dash=true,
  dtime=0,ddx=0,ddy=0,
  freeze=0,grace=0,jbuf=0,
 }
 trail={}
end

function appr(v,t,a)
 if v>t then return max(v-a,t) else return min(v+a,t) end
end

function tsolid(c,r)
 if c<0 or c>15 then return true end
 if r<0 or r>15 then return false end
 return solids[r][c]
end

-- hitbox: offset(1,3) size 6x5
function is_solid(ox,oy)
 local x0=p.x+1+ox
 local y0=p.y+3+oy
 for c=flr(x0/8),flr((x0+5)/8) do
  for r=flr(y0/8),flr((y0+4)/8) do
   if tsolid(c,r) then return true end
  end
 end
 return false
end

function move_x(a)
 local st=sgn(a)
 for i=1,abs(a) do
  if not is_solid(st,0) then p.x+=st else p.vx=0 return end
 end
end
function move_y(a)
 local st=sgn(a)
 for i=1,abs(a) do
  if not is_solid(0,st) then p.y+=st else p.vy=0 return end
 end
end

function box(bx,by,bw,bh)
 return p.x+8>bx and p.x<bx+bw and p.y+8>by and p.y<by+bh
end

function spike_hit(s)
 if p.vy<0 then return false end
 if p.x+6<s.x+2 or p.x+1>s.x+5 then return false end
 local feet=p.y+7
 return feet>=s.y+2 and feet<=s.y+8
end

function start_dash()
 local dx=(btn(1) and 1 or 0)-(btn(0) and 1 or 0)
 local dy=(btn(3) and 1 or 0)-(btn(2) and 1 or 0)
 if dx==0 and dy==0 then dx=p.flip and -1 or 1 end
 if dx~=0 and dy~=0 then
  p.ddx=dx*3.53
  p.ddy=dy*3.53
 else
  p.ddx=dx*5
  p.ddy=dy*5
 end
 p.vx=p.ddx
 p.vy=p.ddy
 p.dtime=6
 p.freeze=2
 p.can_dash=false
end

function update_player()
 if p.y>128 then respawn() return end
 if p.freeze>0 then p.freeze-=1 return end

 local ong=is_solid(0,1)
 if ong then
  p.grace=6
  p.can_dash=true
 elseif p.grace>0 then
  p.grace-=1
 end

 local ix=(btn(1) and 1 or 0)-(btn(0) and 1 or 0)
 if btnp(4) then p.jbuf=4 elseif p.jbuf>0 then p.jbuf-=1 end
 if ix~=0 then p.flip=(ix<0) end

 if btnp(5) and p.can_dash then start_dash() end
 if p.freeze>0 then return end

 if p.dtime>0 then
  p.dtime-=1
  p.vx=p.ddx
  p.vy=p.ddy
  add(trail,{x=p.x,y=p.y,t=5})
  if p.dtime<=0 then
   p.vx=mid(-1,p.vx,1)
   p.vy=0
  end
 else
  local acc=ong and 0.6 or 0.4
  if abs(p.vx)>1 then
   p.vx=appr(p.vx,sgn(p.vx),0.15)
  else
   p.vx=appr(p.vx,ix,acc)
  end
  local g=0.21
  if abs(p.vy)<=0.15 then g=0.105 end
  p.vy=appr(p.vy,2,g)
  if p.jbuf>0 and p.grace>0 then
   p.vy=-2
   p.jbuf=0
   p.grace=0
  end
 end

 p.rx+=p.vx
 local mx=flr(p.rx+0.5) p.rx-=mx move_x(mx)
 p.ry+=p.vy
 local my=flr(p.ry+0.5) p.ry-=my move_y(my)

 for s in all(spikes) do
  if spike_hit(s) then respawn() return end
 end
 for s in all(straws) do
  if not s.got and box(s.x,s.y,8,8) then
   s.got=true
   score+=1
  end
 end
 if box(goal.x,goal.y,8,8) then win=true end
end

function _update()
 if win then return end
 update_player()
 for t in all(trail) do
  t.t-=1
  if t.t<=0 then del(trail,t) end
 end
 for pt in all(parts) do
  pt.y+=pt.s
  pt.x+=pt.vx
  if pt.y>128 then pt.y=0 pt.x=rnd(128) end
  if pt.x<0 then pt.x=128 end
 end
end

function _draw()
 cls(12)
 rectfill(8,14,119,127,1)
 rectfill(0,110,127,127,1)
 for r=0,15 do
  for c=0,15 do
   if solids[r][c] then
    spr((not tsolid(c,r-1)) and 16 or 17,c*8,r*8)
   end
  end
 end
 for s in all(spikes) do spr(5,s.x,s.y) end
 for s in all(straws) do
  if not s.got then spr(2,s.x,s.y) end
 end
 spr(3,goal.x,goal.y)
 for t in all(trail) do
  local col=t.t>2 and 7 or 6
  rectfill(t.x+2,t.y+2,t.x+5,t.y+5,col)
 end
 if not p.can_dash then pal(8,12) end
 spr(1,p.x,p.y,1,1,p.flip)
 pal()
 for pt in all(parts) do
  pset(pt.x,pt.y,pt.s>0.5 and 7 or 6)
 end
 spr(2,1,0)
 print(score.."/2",11,2,7)
 if win then
  rectfill(34,52,93,74,0)
  rect(34,52,93,74,7)
  print("clear!",50,58,10)
  print("berries "..score.."/2",39,66,7)
 end
end

__gfx__
0000000000888800000b3000006eee00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000888888000b3b000006eee00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000008ffff8000888000006ee000000000000070070000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000008f0f0800887880000600000000000000777077000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000ffff000878878000600000000000007777777000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000003bbbb300888788000600000000000007777777000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000003bbbbbb30088880000600000000000006666666000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000001001000008800006660000000000006666666000000000000000000000000000000000000000000000000000000000000000000000000000000000
77777777555555550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
76666667555455550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
65555556555555450000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
55555555455555550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
55545555555554550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
55555455554555550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
45555554555555540000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
55555555455555550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
