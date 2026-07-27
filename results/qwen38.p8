pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
-- snowy cavern celeste-like: dark navy/black interior, gray-brown rock (5)
-- with cream snow caps (7), cyan icy shafts (12), red-hair player (8/12),
-- pink berries + green stems, white spikes. constants: run 1 / acc .6 /
-- dec .15, grav .21 maxfall 2, jump -2, dash 5 diag .7071, 2 hitstop + 4
-- move. route: intro flat jump, reversal + spike-constrained variation with
-- berry detour, 4-col forced gap (run+jump+hdash) to 2-wide ledge, goal.
-- controls: btn0/1 move, btn2/3 aim dash, btnp4 jump, btnp5 dash

-- top-level state (observable)
px=0 py=0 vx=0 vy=0 grounded=false can_dash=true dashing=false facing=1
score=0 win=false deaths=0 demo=true cancelled=false dphase=0 rec_timer=-1
-- dash internals
hitstop=0 dash_move=0 ddx=0 ddy=0
-- inputs
il=false ir=false iu=false id=false ijp=false idp=false

sp_x=10 sp_y=90
w=6 h=6
acc=0.6 dec=0.15 maxr=1 grav=0.21 maxf=2 jumpv=-2 dashv=5 diag=0.7071

map_src={
 "................",
 "................",
 "................",
 "................",
 "................",
 "................",
 "................",
 "................",
 "................",
 ".....b.........g",
 "...............g",
 "........##....##",
 "###b###.##....##",
 "#######.##....##",
 "#######^##.^^.##",
 "#######.##....##",
}
t={}
spikes={}
berries={}
goal=nil

trail={}
parts={}

function parse()
 t={}
 for y=1,16 do
  local row={}
  local s=map_src[y]
  for x=1,16 do
   local c=sub(s,x,x)
   local v=0
   if c=="#" then v=1
   elseif c=="^" then v=2
   elseif c=="b" or c=="B" then v=3
   elseif c=="g" or c=="G" then v=4 end
   row[x]=v
   if v==2 then add(spikes,{x=x-1,y=y-1}) end
   if v==3 then add(berries,{x=x-1,y=y-1,got=false}) end
   if v==4 then goal={x=x-1,y=y-1} end
  end
  t[y]=row
 end
end

function solid(tx,ty)
 if tx<0 or tx>15 then return true end
 if ty<0 then return true end
 if ty>15 then return false end
 return t[ty+1][tx+1]==1
end

function respawn()
 px=sp_x py=sp_y vx=0 vy=0 grounded=false can_dash=true
 dashing=false hitstop=0 dash_move=0 facing=1
 if demo and not cancelled then dphase=0 end
end

function die()
 deaths+=1
 respawn()
end

function start_dash()
 local ax=(ir and 1 or 0)-(il and 1 or 0)
 local ay=(id and 1 or 0)-(iu and 1 or 0)
 if ax==0 and ay==0 then ax=facing end
 local m=1
 if ax~=0 and ay~=0 then m=diag end
 ddx=ax*dashv*m ddy=ay*dashv*m
 dashing=true hitstop=2 dash_move=4 can_dash=false
end

function move_x()
 px+=vx
 local top=flr(py/8) local bot=flr((py+h-1)/8)
 if vx>0 then
  local c=flr((px+w-1)/8)
  for ty=top,bot do if solid(c,ty) then px=c*8-w vx=0 break end end
 elseif vx<0 then
  local c=flr(px/8)
  for ty=top,bot do if solid(c,ty) then px=(c+1)*8 vx=0 break end end
 end
end

function move_y()
 py+=vy
 local lft=flr(px/8) local rgt=flr((px+w-1)/8)
 grounded=false
 if vy>0 then
  local r=flr((py+h)/8)
  for tx=lft,rgt do if solid(tx,r) then py=r*8-h vy=0 grounded=true break end end
 elseif vy<0 then
  local r=flr(py/8)
  for tx=lft,rgt do if solid(tx,r) then py=(r+1)*8 vy=0 break end end
 end
end

function check_hazards()
 if py>128 then die() return end
 local lft=flr(px/8) local rgt=flr((px+w-1)/8)
 local top=flr(py/8) local bot=flr((py+h-1)/8)
 for ty=top,bot do for tx=lft,rgt do
   if t[ty+1] and t[ty+1][tx+1]==2 then
    if vy>=0 then die() return end
   end
 end end
 for b in all(berries) do
  if not b.got and px+ w> b.x*8+1 and px< b.x*8+7 and py+h> b.y*8+1 and py< b.y*8+7 then
   b.got=true score+=1
  end
 end
 if goal and px+w>goal.x*8 and px<goal.x*8+8 and py+h>goal.y*8 and py<goal.y*8+8 then
  if not win then
   win=true
   if demo and not cancelled then rec_timer=45 end
  end
 end
end

function ctrl_demo()
 il=false ir=false iu=false id=false ijp=false idp=false
 if dphase==0 then
  ir=true
  if grounded and px>18 then ijp=true dphase=1 end
 elseif dphase==1 then
  ir=true
  if grounded then dphase=2 end
 elseif dphase==2 then
  il=true
  if grounded and py>94 then dphase=3 end
 elseif dphase==3 then
  ir=true
  if grounded and px>26 then ijp=true dphase=4 end
 elseif dphase==4 then
  ir=true
  if grounded then dphase=5 end
 elseif dphase==5 then
  ir=true
  if grounded and px>47 and px<56 then ijp=true dphase=6 end
 elseif dphase==6 then
  ir=true
  if grounded then dphase=7 end
 elseif dphase==7 then
  ir=true
  if grounded and px>75 and px<80 then ijp=true end
  if not grounded then dphase=71 end
 elseif dphase==71 then
  ir=true
  if py<76 then idp=true dphase=8 end
 elseif dphase==8 then
  ir=true
  if grounded then dphase=9 end
 elseif dphase==9 then
  ir=true
 end
end

function get_inputs()
 local p0=btn(0) local p1=btn(1) local p2=btn(2) local p3=btn(3)
 local q4=btnp(4) local q5=btnp(5)
 if demo and not cancelled then
  if p0 or p1 or p2 or p3 or q4 or q5 then
   cancelled=true demo=false respawn()
   il=p0 ir=p1 iu=p2 id=p3 ijp=false idp=false
  else
   ctrl_demo()
  end
 else
  il=p0 ir=p1 iu=p2 id=p3 ijp=q4 idp=q5
 end
 if il and ir then il=false ir=false end
 if iu and id then iu=false id=false end
end

function _init()
 parse()
 respawn()
 parts={}
 for i=1,7 do add(parts,{x=rnd(128),y=rnd(128),s=0.2+rnd(0.4)}) end
 if demo then
  extcmd("set_filename","qwen38.gif")
  extcmd("rec_frames")
 end
end

function _update()
 -- particles always
 for p in all(parts) do
  p.y+=p.s if p.y>127 then p.y=0 p.x=rnd(128) end
 end
 if win then
  if rec_timer>0 then
   rec_timer-=1
   if rec_timer==0 then extcmd("video",4,1) end
  end
  return
 end
 get_inputs()
 if dashing then
  if hitstop>0 then
   hitstop-=1
  else
   vx=ddx vy=ddy dash_move-=1
   add(trail,{x=px+3,y=py+3,l=6})
   move_x() move_y()
    if dash_move<=0 then dashing=false vy=0 end
  end
 else
  if il then vx-=acc facing=-1 elseif ir then vx+=acc facing=1
  else
   if vx>0 then vx=max(0,vx-dec) elseif vx<0 then vx=min(0,vx+dec) end
  end
  vx=mid(-maxr,maxr,vx)
  if grounded and ijp then vy=jumpv grounded=false end
  vy+=grav vy=min(vy,maxf)
  move_x() move_y()
  if grounded then can_dash=true end
  if idp and can_dash then start_dash() end
 end
 -- trail decay
 for i=#trail,1,-1 do trail[i].l-=1 if trail[i].l<=0 then del(trail,i) end end
 check_hazards()
end

-- ---------- drawing ----------
function draw_bg()
 cls(0)
 -- interior navy strata (depth) full width; rock/cyan overdraw later
 for _,yb in ipairs({24,56,88}) do rectfill(0,yb,127,yb+7,1) end
 -- left outside opening: cyan with jagged snowy right edge (cols 1-3)
 for y=0,95 do
  local ex=31+((y*7)%3)-1
  rectfill(8,y,ex,y,12)
  if y%7==0 then pset(9+((y*3)%18),y,7) end
  if (y*5)%9==0 then pset(ex,y,7) end
  if (y*3+1)%4<2 then pset(ex+1,y,7) end
 end
 -- central hanging icicle: thin cyan core, irregular white edges
 for y=6,120 do
  local o=(y*3)%2
  rectfill(75+o,y,77+o,y,12)
  if (y*5)%6<2 then pset(74+o,y,7) end
  if (y*7)%6<2 then pset(78+o,y,7) end
  if (y*11)%9==0 then pset(76+o,y,7) end
 end
 rectfill(73,4,80,6,7)
 pset(75,7,12) pset(77,9,12)
 -- title backing: dark navy so white text reads; rock overhang tips + snow
 rectfill(40,0,87,7,1)
 rectfill(40,0,43,3,5) pset(41,4,7) pset(42,5,7)
 rectfill(84,0,87,3,5) pset(85,4,7) pset(84,5,7)
 for x=44,83 do
  if (x*5+2)%9<2 then pset(x,6,5) end
  if (x*3+1)%7<1 then pset(x,7,7) end
 end
 -- ambient snow specks in the dark interior
 for i=1,16 do pset((i*37+5)%128,(i*53+11)%120+8,7) end
end

function draw_rock(x,y,tx,ty)
 rectfill(x,y,x+7,y+7,5)
 -- sparse texture
 if (tx*3+ty*5)%5==0 then pset(x+2,y+3,4) end
 if (tx*7+ty*2)%6==0 then pset(x+5,y+5,13) end
 if (tx+ty*4)%9==0 then pset(x+6,y+2,0) end
 -- snow cap if air above
 if not solid(tx,ty-1) then
  rectfill(x,y,x+7,y+1,7)
  local d=(tx*7+ty*3)%8
  pset(x+d,y+2,7)
  pset(x+((d+3)%8),y+2,7)
  if (tx+ty)%3==0 then pset(x+((d+5)%8),y+3,7) end
 end
end

function draw_spike(x,y)
 for i=0,3 do
  rectfill(x+3-i,y+7-i*2,x+4+i,y+7-i*2,6)
 end
 pset(x+3,y+1,7) pset(x+4,y+1,7)
end

function draw_berry(x,y)
 rectfill(x+2,y+2,x+5,y+6,8)
 rectfill(x+1,y+3,x+6,y+5,8)
 pset(x+3,y+3,7)
 rectfill(x+3,y,4,y+1,3)
 pset(x+5,y,11)
end

function draw_flag(x,y)
 rectfill(x+1,y,1,y+7,6)
 rectfill(x+2,y+1,x+6,y+3,8)
 pset(x+3,y+2,7)
end

function draw_terrain()
 for ty=0,15 do for tx=0,15 do
  local v=t[ty+1][tx+1]
  local x=tx*8 local y=ty*8
  if v==1 then draw_rock(x,y,tx,ty)
  elseif v==2 then draw_spike(x,y)
  elseif v==4 then draw_flag(x,y) end
 end end
 for b in all(berries) do if not b.got then draw_berry(b.x*8,b.y*8) end end
end

function draw_player()
 local ox=px-1 local oy=py-1
 local hc=can_dash and 8 or 12
 -- trail
 for tr in all(trail) do rectfill(tr.x-1,tr.y-1,tr.x+1,tr.y+1,7) end
 -- hair (back of head)
 if facing>0 then
  rectfill(ox,oy,ox+3,oy+3,hc)
  rectfill(ox+1,oy-1,ox+3,oy,hc)
  rectfill(ox+3,oy+1,ox+5,oy+3,7) -- face
  pset(ox+4,oy+2,0)
 else
  rectfill(ox+2,oy,ox+5,oy+3,hc)
  rectfill(ox+2,oy-1,ox+4,oy,hc)
  rectfill(ox,oy+1,ox+2,oy+3,7)
  pset(ox+1,oy+2,0)
 end
 -- body
 rectfill(ox+1,oy+4,ox+4,oy+5,3)
 rectfill(ox+1,oy+6,ox+2,oy+6,3)
 rectfill(ox+3,oy+6,ox+4,oy+6,3)
end

function draw_title()
 local n="qwen 3.8 max"
 local lx=64-#n*2
 print(n,lx+1,1,0)
 print(n,lx,0,7)
end

function _draw()
 draw_bg()
 draw_terrain()
 for p in all(parts) do pset(p.x,p.y,7) end
 draw_player()
 draw_title()
 rectfill(113,1,116,4,8)
 pset(114,2,7)
 rectfill(114,0,115,0,3)
 print(score.."",118,1,0)
 print(score.."",117,0,7)
 if win then
  print("clear!",52,60,7)
 end
end
