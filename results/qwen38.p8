pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
-- qwen 3.8 max: celeste-style cavern — cyan glacial ice, gray-brown rock with pale snow caps over navy depths and silhouettes, snowfall.
-- movement: run 1/accel .6/decel .15, gravity .21, fall 2, jump -2, dash 5 (diag .7071), hitstop 2 + 4 moving frames, recharges on ground.
-- route: intro hop, then a reversal hop for the ice-floe berry, the four-column chasm (cols 8-11) crossed by jump +
-- right dash onto the spike-guarded ledge, then up to the flag; demo takes the berry (1 of 2).
-- any key cancels the demo into free play.
-- controls: d-pad run, up/down aim dash, o jump, x dash.
max_run=1
accel=.6
decel=.15
grav=.21
max_fall=2
jump_v=-2
dash_spd=5
diag=.7071

lvl={
"................",
"................",
"................",
"................",
"................",
"................",
"................",
"................",
"................",
".........b......",
"..b...........g.",
"..##.........^##",
"s....###....####",
"########....####",
"########^^^^####",
"################"
}

function cell(c,r)
 if c<0 or c>15 or r<0 or r>15 then
  return "#"
 end
 return sub(lvl[r+1],c+1,c+1)
end

function sol(c,r)
 return cell(c,r)=="#"
end

function spk(c,r)
 return cell(c,r)=="^"
end

function box(x,y)
 for r=flr(y/8),flr((y+5)/8) do
  for c=flr(x/8),flr((x+5)/8) do
   if sol(c,r) then return true end
  end
 end
 return false
end

function axmv(h,d)
 local rem=d
 while abs(rem)>.001 do
  local s=mid(-1,rem,1)
  local nx=px+(h==0 and s or 0)
  local ny=py+(h==1 and s or 0)
  if box(nx,ny) then return true end
  px,py=nx,ny
  rem-=s
 end
 return false
end

function appr(v,t,s)
 if v<t then return min(v+s,t) end
 return max(v-s,t)
end

function kill()
 dead=true
 dead_t=0
 deaths+=1
end

function touch()
 if py>128 then
  kill()
  return
 end
 local l,r=flr(px/8),flr((px+5)/8)
 local t,b=flr(py/8),flr((py+5)/8)
 for row=max(t,0),min(b,15) do
  for col=max(l,0),min(r,15) do
   if vy>=0 and spk(col,row) then
    kill()
    return
   end
  end
 end
 for i=1,2 do
  if not got[i] then
   local e=ber[i]
   if px<=e.x+7 and px+5>=e.x and py<=e.y+7 and py+5>=e.y then
    got[i]=true
    score+=1
   end
  end
 end
 if not win and px<=gx+7 and px+5>=gx and py<=gy+7 and py+5>=gy then
  win=true
  win_t=0
 end
end

function reset_run()
 px,py=sx,sy
 vx,vy=0,0
 face=1
 grounded=false
 can_dash=true
 dash_left=0
 hitstop=0
 dash_vx,dash_vy=0,0
 dead=false
 dead_t=0
 win=false
 win_t=0
 score=0
 got={false,false}
 phase=1
 pt=0
 deaths=0
 trail={}
end

function respawn()
 px,py=sx,sy
 vx,vy=0,0
 face=1
 grounded=false
 can_dash=true
 dash_left=0
 hitstop=0
 dead=false
 dead_t=0
 trail={}
end

function demo_ctrl()
 local g=grounded
 if phase==1 and g and px>=31 then
  phase,pt=2,0
 elseif phase==2 and g and px>=40 then
  phase,pt=3,0
 elseif phase==3 and g and px<=42 then
  phase,pt=4,0
 elseif phase==4 and g and px<=32 and py<=90 then
  phase,pt=5,0
 elseif phase==5 and px<=18 then
  phase,pt=6,0
 elseif phase==6 and px>=26 then
  phase,pt=7,0
 elseif phase==7 and g and px>=40 and py<=92 then
  phase,pt=8,0
 elseif phase==8 and g and px>=56 then
  phase,pt=9,0
 elseif phase==9 and pt>=6 then
  phase,pt=10,0
 elseif phase==10 and g and px>=88 then
  phase,pt=11,0
 elseif phase==11 and g and px>=95 then
  phase,pt=12,0
 end
 pt+=1
 local dx=1
 if phase==3 or phase==4 or phase==5 then dx=-1 end
 local jp=(phase==2 or phase==4 or phase==7 or phase==9 or phase==12) and pt==1
 local dp=phase==10 and pt==1
 return dx,0,jp,dp
end

function step_p(dx,dy,jp,dp)
 if hitstop>0 then
  hitstop-=1
  return
 end
 if dash_left>0 then
  axmv(0,dash_vx)
  axmv(1,dash_vy)
  if #trail<24 then
   add(trail,{x=px,y=py,l=8})
  end
  dash_left-=1
  if dash_left==0 then
   vx=mid(-1,dash_vx,1)
   vy=dash_vy<=0 and 0 or mid(0,dash_vy,max_fall)
  end
  grounded=box(px,py+1)
  if grounded then can_dash=true end
  touch()
  return
 end
 if dp and can_dash then
  if dx==0 and dy==0 then dx=face end
  local mx,my=dx,dy
  if dx!=0 and dy!=0 then
   mx,my=dx*diag,dy*diag
  end
  dash_vx,dash_vy=mx*dash_spd,my*dash_spd
  if dx!=0 then face=dx end
  can_dash=false
  hitstop=1
  dash_left=4
  vx,vy=0,0
  return
 end
 if dx!=0 then
  face=dx
  vx=appr(vx,max_run*dx,accel)
 else
  vx=appr(vx,0,decel)
 end
 vy=appr(vy,max_fall,grav)
 if jp and grounded then vy=jump_v end
 if axmv(0,vx) then vx=0 end
 if axmv(1,vy) then
  if vy>0 then grounded=true end
  vy=0
 end
 grounded=box(px,py+1)
 if grounded then can_dash=true end
 touch()
end

function _init()
 ber={}
 for r=0,15 do
  for c=0,15 do
   local ch=cell(c,r)
   if ch=="b" then
    add(ber,{x=c*8,y=r*8})
   elseif ch=="g" then
    gx,gy=c*8,r*8
   elseif ch=="s" then
    sx,sy=c*8+1,r*8+2
   end
  end
 end
 t=0
 demo=true
 save_ok=true
 saved=false
 extcmd("set_filename","qwen38.gif")
 extcmd("rec_frames")
 reset_run()
end

function _update()
 t+=1
 if win then
  win_t+=1
  if win_t==45 and demo and save_ok and not saved then
   extcmd("video",4,1)
   saved=true
  end
  return
 end
 if dead then
  dead_t+=1
  if dead_t>=24 then
   if demo then
    reset_run()
   else
    respawn()
   end
  end
  return
 end
 if demo then
  for i=0,5 do
   if btn(i) then
    demo=false
    save_ok=false
    respawn()
    break
   end
  end
 end
 local dx,dy,jp,dp
 if demo then
  dx,dy,jp,dp=demo_ctrl()
 else
  dx=(btn(1) and 1 or 0)-(btn(0) and 1 or 0)
  dy=(btn(3) and 1 or 0)-(btn(2) and 1 or 0)
  jp=btnp(4)
  dp=btnp(5)
 end
 step_p(dx,dy,jp,dp)
 for e in all(trail) do
  e.l-=1
  if e.l<=0 then del(trail,e) end
 end
end

function draw_bg()
 rectfill(0,8,9,127,12)
 rectfill(118,8,127,127,12)
 for i=1,10 do
  local sx=(i*37)%128
  local sy=8+(i*53)%112
  rectfill(sx,sy,sx+(i%2),sy+(i%2),7)
 end
 rectfill(0,0,127,7,7)
 rectfill(10,8,117,20,12)
 for x=0,124,9 do
  local dl=10+(x%18)
  rectfill(x,8,x+2,8+dl,7)
  rectfill(x+1,8,x+1,6+dl,12)
 end
 rectfill(8,48,58,95,5)
 rectfill(8,48,58,49,7)
 rectfill(20,60,23,63,0)
 rectfill(40,72,42,74,0)
 rectfill(90,44,119,95,5)
 rectfill(90,44,119,45,7)
 rectfill(100,58,103,61,0)
 rectfill(110,76,112,78,0)
 rectfill(60,36,88,127,12)
 rectfill(63,36,85,40,7)
 rectfill(60,36,62,127,1)
 rectfill(86,36,88,127,1)
 for i=0,3 do
  local cx=66+i*6
  line(cx,44+(i%3)*6,cx+1,124,1)
 end
 rectfill(14,52,28,59,1)
 rectfill(96,50,106,57,1)
end

function draw_tile(c,r)
 local x,y=c*8,r*8
 if r==11 and (c==2 or c==3) then
  rectfill(x,y,x+7,y+7,7)
  rectfill(x+2,y+2,x+5,y+5,12)
  line(x+3,y+8,x+3,y+12,7)
  line(x+3,y+9,x+3,y+11,12)
  return
 end
 local lu,dn=not sol(c,r-1),not sol(c,r+1)
 local le,ri=not sol(c-1,r),not sol(c+1,r)
 if not (lu or dn or le or ri) then
  rectfill(x,y,x+7,y+7,(r%4==1 or r%4==2) and 1 or 0)
  if (c*7+r*3)%9==0 then
   rectfill(x+3,y+3,x+4,y+4,0)
  end
  return
 end
 rectfill(x,y,x+7,y+7,7)
 local x0,y0=x+(le and 2 or 0),y+(lu and 2 or 0)
 local x1,y1=x+7-(ri and 2 or 0),y+7-(dn and 2 or 0)
 rectfill(x0,y0,x1,y1,5)
 if (c*5+r*2)%6==0 then
  pset(x0+(c*2+r)%4,y0+(c+r*2)%4,0)
 end
 if (c*13+r*7)%11==0 then
  line(x0+1,y0+2,x0+3,y0+4,0)
 end
 if lu then
  if (c+r)%2==0 then
   pset(x+(c*3)%7,y+2,7)
  end
  if (c*11+r)%5==0 then
   pset(x+2,y-1,11)
   pset(x+3,y-2,11)
   pset(x+4,y-1,11)
  end
 end
 if dn then
  line(x+2,y+8,x+2,y+10,7)
  line(x+5,y+8,x+5,y+9,7)
 end
 if c>=5 and c<=7 and r==12 then
  line(x+1,y+8,x+1,y+11,12)
  line(x+5,y+8,x+5,y+13,12)
 end
end

function draw_spike(c,r)
 local x,y=c*8,r*8
 rectfill(x,y+6,x+7,y+7,7)
 for i=0,3 do
  local bx=x+i*2
  line(bx,y+6,bx+1,y+1,6)
  pset(bx+1,y+1,7)
 end
end

function draw_berry(e,i)
 local sw=sin(t/40+i*.25)*1.5
 local bx,by=e.x+4,e.y+4+sw
 pset(bx,by-4,11)
 pset(bx-1,by-3,11)
 pset(bx+1,by-3,11)
 rectfill(bx-2,by-2,bx+2,by-1,8)
 rectfill(bx-2,by,bx+2,by,8)
 rectfill(bx-1,by+1,bx+1,by+1,8)
 pset(bx,by+2,8)
 pset(bx-1,by-1,14)
 pset(bx+1,by,14)
 pset(bx-1,by+1,14)
 pset(bx-1,by-2,7)
 if (t/20+i)%2<1 then
  pset(bx+2,by-2,7)
 end
end

function draw_flag()
 local fx,gy2=116,80
 rectfill(fx,gy2,fx+1,gy2+7,7)
 pset(fx,gy2-1,12)
 local wv=sin(t/30)*1
 rectfill(fx+2,gy2+wv,fx+7,gy2+3+wv,8)
 rectfill(fx+2,gy2+wv,fx+5,gy2+1+wv,14)
end

pspr={
".hhhh.",
"hhhhhh",
"hffff.",
"hfeff.",
".gggg.",
".gggg.",
".l..l."
}
pcmap={h=8,f=15,e=0,g=3,l=1}

function draw_player()
 if dead then
  for i=1,8 do
   pset(flr(px)+2+sin(i/8+t/16)*5,flr(py)+2+cos(i/8+t/16)*5,7)
  end
  return
 end
 local x,y=flr(px),flr(py)
 pcmap.h=can_dash and 8 or 1
 local legs=6
 if not grounded then
  legs=7
 elseif abs(vx)>.1 and (t/4)%2<1 then
  legs=8
 end
 for r=0,6 do
  local row=pspr[r+1]
  if r==6 then
   if legs==7 then
    row=".l.l.."
   elseif legs==8 then
    row="l..l.."
   end
  end
  for cix=0,5 do
   local ch=sub(row,cix+1,cix+1)
   if ch~="." then
    local cx=cix
    if face==-1 then cx=5-cix end
    pset(x+cx,y-1+r,pcmap[ch])
   end
  end
 end
 if face==1 then
  pset(x-1,y+1,pcmap.h)
  pset(x-1,y+2,pcmap.h)
 else
  pset(x+6,y+1,pcmap.h)
  pset(x+6,y+2,pcmap.h)
 end
end

function draw_hud()
 print("qwen 3.8 max",41,2,12)
 print("qwen 3.8 max",40,1,0)
 rectfill(0,118,26,126,0)
 circfill(6,122,2,8)
 pset(6,119,11)
 print("x"..score,12,119,7)
 if deaths>0 then
  print("falls:"..deaths,88,119,6)
 end
end

function draw_clear()
 rectfill(30,44,98,70,0)
 print("clear!",53,49,8)
 print("clear!",52,48,10)
 print("qwen 3.8 max",41,58,7)
 print("berries: "..score.."/2",42,64,12)
end

function _draw()
 cls(0)
 draw_bg()
 for r=0,15 do
  for c=0,15 do
   local ch=cell(c,r)
   if ch=="#" then
    draw_tile(c,r)
   elseif ch=="^" then
    draw_spike(c,r)
   end
  end
 end
 draw_flag()
 for i=1,2 do
  if not got[i] then
   draw_berry(ber[i],i)
  end
 end
 for e in all(trail) do
  rect(e.x+1,e.y+1,e.x+4,e.y+4,e.l>4 and 7 or 12)
 end
 draw_player()
 for i=1,12 do
  local fxs=(i*37+t*(1+(i%3)))%136-4
  local fys=(i*53+t*(2+(i%4)))%128
  pset(fxs,fys,i%3==0 and 7 or 6)
 end
 draw_hud()
 if win then
  draw_clear()
 end
end
