pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
-- design notes:
-- celeste: 8-dir dash, ground recharge, hair, freeze, trail, snow
-- maxrun=1 grav=0.21 jump=-3.2 dash=5*4 freeze=2 hb 6x5
-- force: 40px gap lowL->lowR (runjump~30, jump+hdash~50)
-- intro r-jump floor->lowL; var l-reverse lowL->mid+spikes; climax h-dash then up-dash
-- demo detour: high berry from mid (jump+updash), skip right berry

-- controls: left/right, up/down aim, o jump, x dash

maxrun=1
accel=.6
airacc=.4
deccel=.15
grav=.21
maxfall=2.5
jspd=-3.2
dspd=5
dlen=4
frz=2

cname="Grok 4.5"
gname="grok45.gif"

function _init()
 deaths=0
 score=0
 win=false
 wint=0
 demo=true
 di=1
 df=0
 rec=false
 freeze=0
 trails={}
 snow={}
 for i=1,24 do
  add(snow,{x=rnd(128),y=rnd(128),sp=.25+rnd(.9),c=6+flr(rnd(2))})
 end
 -- surfaces y: floor112 low88 mid64 high48 rmid56 goal24
 -- lowL x16-48, gap 48-88 (40px), lowR x88-128
 -- mid x8-40, high x0-24, goal x96-128
 lvl={
  "0000000000000000",
  "0000000000000000",
  "0000000000000400",
  "0000000000005555",
  "0000000000000000",
  "0300000000000000",
  "5550000000000000",
  "0000000000005550",
  "0555550000000000",
  "0000000000000000",
  "0000000000000000",
  "0055550000015555",
  "0000000000000000",
  "0000002220000030",
  "1111110000011111",
  "1111110000011111"
 }
 solid={}
 plats={}
 spike={}
 fruit={}
 flag=nil
 for ty=0,15 do
  local row=lvl[ty+1]
  for tx=0,15 do
   local c=sub(row,tx+1,tx+1)
   local x,y=tx*8,ty*8
   if c=="1" then add(solid,{x=x,y=y})
   elseif c=="5" then add(plats,{x=x,y=y})
   elseif c=="2" then add(spike,{x=x,y=y})
   elseif c=="3" then add(fruit,{x=x,y=y,got=false,by=y,o=rnd(1)})
   elseif c=="4" then flag={x=x,y=y}
   end
  end
 end
 spawn()
 extcmd("set_filename",gname)
 extcmd("rec_frames")
end

function spawn()
 p={
  x=12,y=104,vx=0,vy=0,rx=0,ry=0,
  face=1,cand=true,dt=0,ft=0,
  ground=false,grace=0,jbuf=0,hair={}
 }
 for i=1,4 do add(p.hair,{x=p.x+4,y=p.y+2}) end
end

function solid_full(x,y,w,h)
 for s in all(solid) do
  if x<s.x+8 and x+w>s.x and y<s.y+8 and y+h>s.y then return true end
 end
 return false
end

function solid_plat(x,y,w,h,vy)
 if vy and vy<0 then return false end
 local band=6
 if vy and vy>0 then band=max(6,flr(abs(vy))+3) end
 for s in all(plats) do
  if x<s.x+8 and x+w>s.x and y+h>s.y and y+h<=s.y+band and y<s.y+2 then
   return true
  end
 end
 return false
end

function is_solid(x,y,w,h,vy)
 return solid_full(x,y,w,h) or solid_plat(x,y,w,h,vy or 0)
end

function on_ground()
 return is_solid(p.x+1,p.y+8,6,1,1)
end

function move_x()
 local rem=p.rx+p.vx
 local n=flr(rem+.5)
 p.rx=rem-n
 local s=sgn(n)
 for i=1,abs(n) do
  if is_solid(p.x+1+s,p.y+3,6,5,p.vy) then
   p.vx=0 p.rx=0 return
  end
  p.x+=s
 end
end

function move_y()
 local rem=p.ry+p.vy
 local n=flr(rem+.5)
 p.ry=rem-n
 local s=sgn(n)
 for i=1,abs(n) do
  if is_solid(p.x+1,p.y+3+s,6,5,p.vy) then
   p.vy=0 p.ry=0 return
  end
  p.y+=s
 end
end

function appr(v,t,a)
 if v>t then return max(t,v-a) else return min(t,v+a) end
end

function sgn(v)
 return v>0 and 1 or v<0 and -1 or 0
end

function ib(b)
 if demo then
  local st=scr[di]
  if not st then return false end
  for bb in all(st.b) do if bb==b then return true end end
  return false
 end
 return btn(b)
end

function ibp(b)
 if demo then
  local st=scr[di]
  if not st or df!=0 then return false end
  for bb in all(st.b) do if bb==b then return true end end
  return false
 end
 return btnp(b)
end

function do_dash()
 if not p.cand then return end
 local ix,iy=0,0
 if ib(0) then ix-=1 end
 if ib(1) then ix+=1 end
 if ib(2) then iy-=1 end
 if ib(3) then iy+=1 end
 if ix==0 and iy==0 then ix=p.face end
 if ix!=0 and iy!=0 then
  p.vx=ix*dspd*.7071
  p.vy=iy*dspd*.7071
 else
  p.vx=ix*dspd
  p.vy=iy*dspd
 end
 if ix!=0 then p.face=ix end
 p.dt=dlen
 p.cand=false
 p.ft=frz
 freeze=frz
end

function kill()
 deaths+=1
 spawn()
 if demo then
  score=0
  for f in all(fruit) do f.got=false end
  di=1 df=0
 end
end

function update_p()
 if p.ft>0 then p.ft-=1 return end

 local gnd=on_ground()
 p.ground=gnd
 if gnd then
  p.grace=6
  p.cand=true
 elseif p.grace>0 then
  p.grace-=1
 end

 if ibp(4) then p.jbuf=4
 elseif p.jbuf>0 then p.jbuf-=1 end

 if p.dt>0 then
  add(trails,{x=p.x+4,y=p.y+4,t=5})
  move_x() move_y()
  p.dt-=1
  if p.dt==0 then p.vx*=.35 p.vy*=.35 end
 else
  local input=0
  if ib(1) then input=1 end
  if ib(0) then input=-1 end
  local a=gnd and accel or airacc
  if abs(p.vx)>maxrun then
   p.vx=appr(p.vx,sgn(p.vx)*maxrun,deccel)
  else
   p.vx=appr(p.vx,input*maxrun,a)
  end
  if p.vx!=0 then p.face=sgn(p.vx) end

  local gv=grav
  if abs(p.vy)<=.15 then gv*=.5 end
  if not gnd then
   p.vy=appr(p.vy,maxfall,gv)
  elseif p.vy>0 then
   p.vy=0
  end

  if p.jbuf>0 and p.grace>0 then
   p.vy=jspd p.jbuf=0 p.grace=0
  end

  if ibp(5) then do_dash() end
  move_x() move_y()
 end

 if p.x<-4 then p.x=-4 p.vx=0 end
 if p.x>120 then p.x=120 p.vx=0 end

 local hx,hy=p.x+1,p.y+3
 for s in all(spike) do
  if hx<s.x+8 and hx+6>s.x and hy<s.y+8 and hy+5>s.y then
   if p.vy>=0 then kill() return end
  end
 end
 if p.y>130 then kill() return end

 for f in all(fruit) do
  if not f.got then
   f.o+=.04
   f.y=f.by+sin(f.o)*2
   if abs(p.x+4-f.x-4)<7 and abs(p.y+4-f.y-4)<7 then
    f.got=true score+=1
   end
  end
 end

 if flag and not win then
  if abs(p.x+4-flag.x-4)<7 and abs(p.y+4-flag.y-4)<9 then
   win=true wint=0
  end
 end
end

-- 0L 1R 2U 3D 4J 5X
scr={
 -- 1 intro floor->lowL
 {b={1},f=14},
 {b={},f=1},
 {b={4},f=1},
 {b={1},f=18},
 {b={},f=16},
 -- 2 reverse lowL->mid
 {b={0},f=12},
 {b={},f=1},
 {b={4},f=1},
 {b={0},f=16},
 {b={},f=16},
 -- 3 berry detour jump+updash
 {b={0},f=5},
 {b={},f=1},
 {b={4},f=1},
 {b={2},f=5},
 {b={2,5},f=1},
 {b={},f=8},
 {b={0},f=8},
 {b={},f=10},
 -- 4 drop high->mid: small right, long wait
 {b={1},f=4},
 {b={},f=24},
 -- 5 mid->lowL
 {b={1},f=6},
 {b={},f=1},
 {b={4},f=1},
 {b={1},f=16},
 {b={},f=16},
 -- 6 hdash gap
 {b={1},f=14},
 {b={},f=1},
 {b={4},f=1},
 {b={1},f=3},
 {b={1,5},f=1},
 {b={1},f=18},
 {b={},f=16},
 -- 7 lowR: settle, walk left, jump+updash rmid
 {b={},f=10},
 {b={0},f=12},
 {b={},f=1},
 {b={4},f=1},
 {b={2},f=6},
 {b={2,5},f=1},
 {b={2,1},f=14},
 {b={1},f=8},
 {b={},f=14},
 -- 8 rmid->goal: jump then updash
 {b={},f=4},
 {b={4},f=1},
 {b={2},f=4},
 {b={2,5},f=1},
 {b={2},f=8},
 {b={2,1},f=10},
 {b={1},f=8},
 {b={},f=1},
 {b={4},f=1},
 {b={2},f=3},
 {b={2,5},f=1},
 {b={2,1},f=12},
 {b={1},f=16},
 {b={},f=40},
}

function update_demo()
 if not demo then return end
 for i=0,5 do
  if btn(i) then
   demo=false score=0
   for f in all(fruit) do f.got=false end
   win=false spawn()
   return
  end
 end
 local st=scr[di]
 if not st then demo=false return end
 df+=1
 if df>=st.f then
  di+=1
  df=0
 end
end

function _update()
 if freeze>0 then freeze-=1 return end
 if win then
  wint+=1
  if demo and not rec and wint>=45 then
   extcmd("video",4,1)
   rec=true
  end
  return
 end
 update_demo()
 update_p()
 for t in all(trails) do
  t.t-=1
  if t.t<=0 then del(trails,t) end
 end
 for s in all(snow) do
  s.y+=s.sp s.x+=s.sp*.25
  if s.y>128 then s.y=0 s.x=rnd(128) end
  if s.x>128 then s.x=0 end
 end
end

function draw_block(x,y)
 rectfill(x,y,x+7,y+7,1)
 rectfill(x,y,x+7,y+1,7)
 rectfill(x,y+2,x+7,y+2,6)
 rectfill(x+1,y+3,x+6,y+6,12)
end

function _draw()
 cls(12)
 rectfill(10,28,58,115,1)
 rectfill(48,18,105,105,1)
 rectfill(88,32,128,118,1)
 rectfill(22,48,82,122,13)
 rectfill(68,38,118,108,13)
 circfill(8,102,26,12)
 circfill(8,102,20,7)
 circfill(120,98,28,12)
 circfill(120,98,22,7)
 rectfill(58,50,70,112,12)
 for i=0,7 do
  line(60+(i%3),50+i*8,64,58+i*8,7)
 end

 for s in all(solid) do draw_block(s.x,s.y) end
 for s in all(plats) do draw_block(s.x,s.y) end

 for s in all(spike) do
  for i=0,3 do
   local bx=s.x+1+i*2
   line(bx,s.y+7,bx+1,s.y+1,6)
   pset(bx+1,s.y,7)
  end
 end

 for f in all(fruit) do
  if not f.got then
   circfill(f.x+4,f.y+5,3,8)
   circfill(f.x+3,f.y+4,2,14)
   pset(f.x+4,f.y+2,11)
   pset(f.x+3,f.y+1,3)
   pset(f.x+5,f.y+1,3)
  end
 end

 if flag then
  local fx,fy=flag.x+2,flag.y
  line(fx,fy,fx,fy+12,6)
  local w=flr(sin(time()*2)*2)
  rectfill(fx+1,fy+1,fx+6+w,fy+5,8)
  line(fx+1,fy+1,fx+6+w,fy+1,14)
 end

 for t in all(trails) do
  circfill(t.x,t.y,max(1,t.t/2),7)
 end

 local hc=p.cand and 8 or 12
 local last={x=p.x+4-p.face,y=p.y+2}
 for i,h in ipairs(p.hair) do
  h.x+=(last.x-h.x)/1.5
  h.y+=(last.y+.5-h.y)/1.5
  circfill(h.x,h.y,max(1,3-i*.4),hc)
  last=h
 end
 circfill(p.x+3,p.y+2,2,hc)
 circfill(p.x+5,p.y+2,2,hc)
 rectfill(p.x+2,p.y+3,p.x+5,p.y+5,15)
 pset(p.x+3,p.y+4,0)
 pset(p.x+5,p.y+4,0)
 rectfill(p.x+2,p.y+6,p.x+5,p.y+7,3)

 for s in all(snow) do pset(s.x,s.y,s.c) end

 print(cname,1,1,7)
 print("*"..score,1,9,8)
 if demo then print("demo",100,1,5) end

 if win then
  rectfill(28,50,100,78,0)
  print("clear!",50,56,7)
  print(cname,40,66,6)
 end
end
