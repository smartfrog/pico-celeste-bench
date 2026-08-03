pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
-- qwen 3.8 max -- single-screen celeste-like climb through a snow cavern.
-- look: navy depths dithered with cyan, gray-brown rock masses with pale snow
-- caps and cyan ice, black pits, sparse snowfall, quiet top title zone.
-- physics: run 1 accel .6 decel .15 gravity .21 maxfall 2 jump -2; dash 5
-- (diag .7071), 2 hitstop then 4 moving frames; dash recharges on ground only.
-- route: intro jump over the spike pit, switchback hop, leftward dash-climb to
-- the berry ledge, back onto the takeoff, jump+dash across the 4-column canyon
-- onto the safe 2-wide ledge, two airy dash-climbs, then the flag on the right.
-- the demo detours for the ledge berry only, and saves qwen38.gif on CLEAR!.
-- controls: left/right move, up/down aim, x jump, c dash.

lvl={
"................",
"................",
"......####......",
"......####......",
"......####......",
"......####....g.",
"......####...###",
"......######.###",
"......####....##",
"..b.........#.##",
"..##..........##",
".....#....##..##",
"s...##....##^b##",
"##^###....######",
"######....######",
"######....######"
}

max_run=1 acc=0.6 dec=0.15 grav=0.21
max_fall=2 jump_v=-2 dash_spd=5 diag=0.7071
sx=0 sy=12
px,py,vx,vy=0,0,0,0
grounded=false can_dash=true face=1 dashing=false
hit=0 dash_t=0 dvx,dvy=0,0
score=0 win=false win_t=0
dead=false dead_t=0 deaths=0
demo=true norec=false saved=false demo_t=0
phase=1 ph_t=0 t=0
berries={}
trail={}
snow={}
burst={}

function tile(c,r)
 if c<0 or c>15 or r<0 or r>15 then return "." end
 return sub(lvl[r+1],c+1,c+1)
end
function solid(c,r)
 if c<0 or c>15 then return true end
 return tile(c,r)=="#"
end

function box(x,y)
 local l=flr(x/8) r=flr((x+5)/8)
 if l<0 or r>15 then return true end
 local t=flr(y/8) b=flr((y+5)/8)
 if t<0 then t=0 end
 if b>15 then b=15 end
 for rr=t,b do
  for cc=l,r do
   if solid(cc,rr) then return true end
  end
 end
 return false
end

function approach(v,tt,s)
 if v>tt then return max(v-s,tt) end
 return min(v+s,tt)
end

function mvx(d)
 while d!=0 do
  local s=mid(-1,d,1)
  if box(px+s,py) then return true end
  px+=s d-=s
 end
 return false
end

function mvy(d)
 while d!=0 do
  local s=mid(-1,d,1)
  if box(px,py+s) then
   if vy>0 then grounded=true end
   return true
  end
  py+=s d-=s
 end
 return false
end

function update_ground()
 grounded=box(px,py+1)
 if grounded then can_dash=true end
end

function touch()
 if py>=128 then kill() return end
 local l=flr(px/8) r=flr((px+5)/8)
 local t0=flr(py/8) b0=flr((py+5)/8)
 local fall=vy>=0
 for rr=max(t0,0),min(b0,15) do
  for cc=max(l,0),min(r,15) do
   local ch=tile(cc,rr)
   if fall and ch=="^" then kill()
   elseif ch=="g" then do_win()
   elseif ch=="b" and not berries[rr*16+cc] then
    berries[rr*16+cc]=true
    score+=1
   end
  end
 end
end

function step_p(idx,idy,ij,dp)
 if hit>0 then hit-=1 return end
 if dash_t>0 then
  mvx(dvx) mvy(dvy)
  dash_t-=1
  if dash_t==0 then
   vx=mid(-1,dvx,1)
   vy=0
   if dvy>0 then vy=mid(0,dvy,max_fall) end
   dashing=false
  end
  update_ground()
  touch()
  return
 end
 if dp and can_dash then
  local ax,ay=idx,idy
  if ax==0 and ay==0 then ax=face ay=0 end
  dvx=ax*dash_spd dvy=ay*dash_spd
  if ax!=0 and ay!=0 then dvx*=diag dvy*=diag end
  can_dash=false dashing=true
  hit=1 dash_t=4 vx=0 vy=0
  return
 end
 if idx!=0 then face=idx vx=approach(vx,max_run*idx,acc)
 else vx=approach(vx,0,dec) end
 vy=approach(vy,max_fall,grav)
 if ij and grounded then vy=jump_v end
 if mvx(vx) then vx=0 end
 if mvy(vy) then vy=0 end
 update_ground()
 touch()
end

function kill()
 if dead or win then return end
 dead=true dead_t=30 deaths+=1
 dashing=false dash_t=0
 burst={}
 for i=1,8 do
  add(burst,{x=px+3,y=py+3,
   vx=cos(i/8)*1.5,vy=sin(i/8)*1.5-1})
 end
end

function do_win()
 if win then return end
 win=true win_t=0 dashing=false
end

function respawn()
 dead=false burst={}
 px=sx*8+1 py=sy*8+2
 vx=0 vy=0 hit=0 dash_t=0 dashing=false
 can_dash=true grounded=false face=1
end

function demo_ctrl()
 ph_t+=1
 if ph_t>240 then
  demo=false norec=true respawn()
  return 0,0,false,false
 end
 local dx,dy,jp,dp=0,0,false,false
 local r=flr((py+6)/8)
 if phase==1 then
  dx=1
  if grounded and not box(px+1,py+1) then
   jp=true phase=2 ph_t=0
  end
 elseif phase==2 then
  dx=1
  if grounded and r==12 and ph_t>1 then
   phase=3 ph_t=0
  end
 elseif phase==3 then
  dx=1
  if ph_t==1 then jp=true end
  if grounded and r==11 and ph_t>1 then
   phase=4 ph_t=0
  end
 elseif phase==4 then
  dx=-1
  if ph_t==1 then jp=true end
  if ph_t==4 then dp=true dy=-1 end
  if grounded and r==10 and ph_t>1 then
   phase=5 ph_t=0
  end
 elseif phase==5 then
  dx=1
  if grounded and px>=19 then
   phase=6 ph_t=0
  end
 elseif phase==6 then
  dx=1
  if ph_t==1 then jp=true end
  if grounded and r==11 and px>=35 and ph_t>1 then
   phase=7 ph_t=0
  end
 elseif phase==7 then
  dx=1
  if grounded and not box(px+1,py+1) then
   jp=true phase=8 ph_t=0
  end
 elseif phase==8 then
  dx=1
  if ph_t==5 then dp=true end
  if grounded and r==11 and px>=74 and ph_t>1 then
   phase=9 ph_t=0
  end
 elseif phase==9 then
  dx=-1
  if grounded and px<=78 then
   phase=10 ph_t=0
  end
 elseif phase==10 then
  dx=1
  if ph_t==1 then jp=true end
  if ph_t==6 then dp=true dy=-1 end
  if grounded and r==9 and ph_t>1 then
   phase=11 ph_t=0
  end
 elseif phase==11 then
  dx=-1
  if ph_t==1 then jp=true end
  if ph_t==4 then dp=true dy=-1 end
  if grounded and r==7 and ph_t>1 then
   phase=12 ph_t=0
  end
 elseif phase==12 then
  dx=1
  if grounded and not box(px+1,py+1) then
   jp=true phase=13 ph_t=0
  end
 elseif phase==13 then
  dx=1
  if grounded and r==6 and ph_t>1 then
   phase=14 ph_t=0
  end
 elseif phase==14 then
  dx=1
 end
 return dx,dy,jp,dp
end

function upd_fx()
 t+=1
 for f in all(snow) do
  f.y+=f.s
  f.x+=0.3*sin(t*0.02+f.o)
  if f.y>130 then f.y-=132 f.x=rnd(128) end
 end
 if dead then
  for b in all(burst) do
   b.x+=b.vx b.y+=b.vy b.vy+=0.15
  end
 end
 if dashing then
  add(trail,{x=px,y=py,a=10})
 end
 for tr in all(trail) do
  tr.a-=1
  if tr.a<=0 then del(trail,tr) end
 end
end

function _update()
 upd_fx()
 if dead then
  dead_t-=1
  if dead_t<=0 then respawn() end
  return
 end
 if win then
  win_t+=1
  if demo and not norec and not saved and win_t==45 then
   extcmd("video",4,1)
   saved=true
  end
  return
 end
 local dx,dy,jp,dp=0,0,false,false
 if demo then
  demo_t+=1
  for i=0,5 do
   if btn(i) then
    demo=false norec=true respawn()
    return
   end
  end
  if demo_t>2700 then
   demo=false norec=true respawn()
   return
  end
  dx,dy,jp,dp=demo_ctrl()
 else
  dx=(btn(1) and 1 or 0)-(btn(0) and 1 or 0)
  dy=(btn(3) and 1 or 0)-(btn(2) and 1 or 0)
  jp=btnp(4) dp=btnp(5)
 end
 step_p(dx,dy,jp,dp)
end

function ice_zone(c,r)
 if r>=7 and r<=8 and c>=6 and c<=9 then return true end
 if r==10 and c>=2 and c<=3 then return true end
 if c==12 and r==9 then return true end
 if (c==5 or c==10) and r>=12 then return true end
 if c>=14 and r>=9 then return true end
 return false
end

function build_map()
 for r=0,15 do
  for c=0,15 do
   local ch=tile(c,r)
   local idx=0
   if ch=="#" then
    if tile(c,r-1)!="#" then
     idx=4
    elseif ice_zone(c,r) then
     idx=5
    elseif tile(c,r+1)=="#" and tile(c-1,r)=="#"
     and tile(c+1,r)=="#" then
     idx=10
    else
     local h=(c*31+r*17)%5
     if h<2 then idx=1
     elseif h<4 then idx=2
     else idx=3
     end
    end
   elseif ch=="^" then
    idx=6
   end
   mset(c,r,idx)
  end
 end
end

function draw_sky()
 cls(12)
 for i=0,10 do
  pset(((i*53)%124)+2,6+(i*37)%40,7)
 end
 fillp(0x7777)
 rectfill(0,56,127,63,0x1c)
 fillp()
 rectfill(0,64,127,127,1)
 rectfill(48,96,79,127,0)
end

function mtn(cx,w,ytop,ybase,col)
 for y=ytop,ybase do
  local hw=w/2*((y-ytop)/(ybase-ytop))
  line(cx-hw,y,cx+hw,y,col)
 end
end

function mtn_down(cx,w,ytop,ybase,col)
 for y=ytop,ybase do
  local hw=w/2*(1-(y-ytop)/(ybase-ytop))
  line(cx-hw,y,cx+hw,y,col)
 end
end

function draw_back()
 mtn(18,44,58,127,1)
 mtn(58,56,66,127,1)
 mtn(104,56,54,127,1)
 mtn_down(6,20,0,12,1)
 mtn_down(122,20,0,10,1)
 pset(22,90,12) pset(98,92,12)
 pset(58,102,12) pset(120,72,12)
 local n=0
 for f in all(snow) do
  n+=1
  if n%3==0 then pset(f.x,f.y,13) end
 end
end

function draw_halo()
 for r=0,15 do
  for c=0,15 do
   if tile(c,r)=="#" then
    local x,y=c*8,r*8
    if tile(c,r-1)!="#" then rectfill(x-1,y-1,x+8,y,7) end
    if tile(c-1,r)!="#" then rectfill(x-1,y-1,x,y+8,7) end
    if tile(c+1,r)!="#" then rectfill(x+7,y-1,x+8,y+8,7) end
   end
  end
 end
end

function draw_flag()
 local gx=14*8+3
 line(gx,40,gx,48,6)
 local wv=(t\8)%2
 rectfill(gx+1,40+wv,gx+8,44+wv,8)
 rectfill(gx+1,41+wv,gx+8,41+wv,14)
 pset(gx+4,42+wv,7)
 if t%32<4 then pset(gx+8,39+wv,7) end
end

function draw_berries()
 local bi=0
 for r=0,15 do
  for c=0,15 do
   if tile(c,r)=="b" then
    bi+=1
    if not berries[r*16+c] then
     local bob=sin(t*0.03+bi*0.4)*1.5
     spr(7,c*8,r*8-1+bob)
     if (t+bi*13)%40<4 then
      pset(c*8+7,r*8-2+bob,7)
     end
    end
   end
  end
 end
end

function draw_trail()
 for tr in all(trail) do
  local col=7
  if tr.a<7 then col=6 end
  if tr.a<4 then col=13 end
  rectfill(tr.x+1,tr.y+1,tr.x+4,tr.y+4,col)
 end
end

function draw_player()
 if dead then
  for b in all(burst) do
   pset(b.x,b.y,7)
  end
  return
 end
 local sp=8
 if not can_dash then sp=9 end
 spr(sp,px-1,py-1,1,1,face<0)
end

function draw_hud()
 print("qwen 3.8 max",35,2,1)
 print("qwen 3.8 max",34,1,7)
 rectfill(3,119,8,124,8)
 rectfill(4,118,6,118,3)
 pset(4,120,7)
 print(score.."/2",11,120,7)
end

function draw_clear()
 local fc=7
 if (t\4)%2==1 then fc=10 end
 print("clear!",50,52,fc)
 print("qwen 3.8 max",34,64,12)
 print(score.."/2",59,76,7)
end

function _draw()
 draw_sky()
 draw_back()
 draw_halo()
 map(0,0)
 draw_flag()
 draw_berries()
 draw_trail()
 draw_player()
 local n=0
 for f in all(snow) do
  n+=1
  if n%3!=0 then pset(f.x,f.y,n%2==0 and 7 or 6) end
 end
 draw_hud()
 if win then draw_clear() end
end

function _init()
 srand(1)
 t=0 phase=1 ph_t=0
 for i=1,12 do
  add(snow,{x=rnd(128),y=rnd(128),
   s=0.2+rnd(0.3),o=rnd(1)})
 end
 build_map()
 respawn()
 extcmd("set_filename","qwen38.gif")
 extcmd("rec_frames")
end

__gfx__
00000000555555555555555555555555777777771111111100000000000330000088800000ddd000000000000000000000000000000000000000000000000000
00000000555505555555555555655555777777771cccccc100600600003bb300088888000ddddd00000000000000000000000000000000000000000000000000
00000000555555555111115555555565767776771cc7ccc1066d066d00888800088888000ddddd00005500000000000000000000000000000000000000000000
00000000505555555555555555555555575555751cccccc1066d066d08e88e80088fff000ddfff00000000000000000000000000000000000000000000000000
00000000555555555555555556555555555555551ccc7cc1066d066d08887880088f0f000ddf0f00000000550000000000000000000000000000000000000000
00000000555055555511115555555655555055551cccccc1066d066d008888000033300000333000000000000000000000000000000000000000000000000000
00000000555555555555555555555555555555551ccccc71066d066d000880000033330000333300000000000000000000000000000000000000000000000000
00000000555555555555555555655555555555551111111101100110000000000044044000440440005500000000000000000000000000000000000000000000
