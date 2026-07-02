pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
-- design notes:
-- celeste classic traits: responsive run, readable jump arc, 8-dir dash w/ hitstop+trail
-- dash recharges only on ground; hair red=has dash, blue=no dash (pal swap 8->12)
-- consts: maxrun 1.5 accel .4 grav .3 jumpv -4.3 maxfall 2.5 dash 4 x10fr freeze 3
-- forced dash: 7-tile pit (56px); run-jump reach 43px, dash reach 68px (gap in [51,60])
-- controls: btn0/1 left/right, btn2/3 aim up/down, btnp4 jump, btnp5 dash

level={
"................",
"..........F.....",
".....#######....",
"................",
"...........S....",
"........#######.",
"................",
".......S........",
".....#######....",
"................",
"................",
"........#######.",
"................",
"................",
"####.......#####",
"####^^^^^^^#####",
}

sp_player=0 sp_tile=1 sp_spike=2 sp_berry=3 sp_flag=4

maxrun=1.5 accel=0.4 grav=0.3 jumpv=-4.3 maxfall=2.5
dashspeed=4 dashtime=10 freezetime=3

startx=8 starty=105
p=nil trail={} snow={} got={}
berries=0 deaths=0 win=false fr=0

function appr(v,t,s)
 if v<t then return min(v+s,t) else return max(v-s,t) end
end


function ftri(x1,y1,x2,y2,x3,y3,c)
 if y1>y2 then x1,x2=x2,x1 y1,y2=y2,y1 end
 if y1>y3 then x1,x3=x3,x1 y1,y3=y3,y1 end
 if y2>y3 then x2,x3=x3,x2 y2,y3=y3,y2 end
 local function lp(ax,ay,bx,by,y)
  if by==ay then return ax end
  return ax+(bx-ax)*(y-ay)/(by-ay)
 end
 for y=y1,y3 do
  local xa=lp(x1,y1,x3,y3,y)
  local xb
  if y<=y2 then xb=lp(x1,y1,x2,y2,y) else xb=lp(x2,y2,x3,y3,y) end
  if xa>xb then xa,xb=xb,xa end
  rectfill(flr(xa),y,flr(xb),y,c)
 end
end

function _init()
 p={x=startx,y=starty,vx=0,vy=0,rem_x=0,rem_y=0,
    can_dash=true,facing=1,dashing=false,dash_t=0,freeze=0,on_ground=false,
    hbx=1,hby=1,hbw=6,hbh=6}
 trail={} got={} berries=0 win=false
 snow={}
 for i=1,30 do add(snow,{x=rnd(128),y=rnd(128),sp=rnd(0.3)+0.2}) end
end

function tchar(tx,ty)
 if tx<0 or tx>15 or ty<0 or ty>15 then return "" end
 return sub(level[ty+1],tx+1,tx+1)
end

function solid_tile(tx,ty)
 if tx<0 or tx>15 or ty<0 then return true end
 if ty>15 then return false end
 return tchar(tx,ty)=="#"
end

function box_solid(bx,by,bw,bh)
 local tx0=flr(bx/8) local tx1=flr((bx+bw-1)/8)
 local ty0=flr(by/8) local ty1=flr((by+bh-1)/8)
 for ty=ty0,ty1 do for tx=tx0,tx1 do
  if solid_tile(tx,ty) then return true end
 end end
 return false
end

function hit_solid(nx,ny)
 return box_solid(nx+p.hbx,ny+p.hby,p.hbw,p.hbh)
end

function pmove()
 p.rem_x+=p.vx
 local mx=flr(p.rem_x+0.5)
 p.rem_x-=mx
 local s=sgn(mx)
 for i=1,abs(mx) do
  if not hit_solid(p.x+s,p.y) then p.x+=s else p.vx=0 p.rem_x=0 break end
 end
 p.rem_y+=p.vy
 local my=flr(p.rem_y+0.5)
 p.rem_y-=my
 local s=sgn(my)
 for i=1,abs(my) do
  if not hit_solid(p.x,p.y+s) then p.y+=s else
   p.vy=0 p.rem_y=0 break
  end
 end
 p.on_ground=hit_solid(p.x,p.y+1)
end

function start_dash()
 local dx=0 dy=0
 if btn(0) then dx=-1 elseif btn(1) then dx=1 end
 if btn(2) then dy=-1 elseif btn(3) then dy=1 end
 if dx==0 and dy==0 then dx=p.facing end
 if dx!=0 and dy!=0 then dx*=0.7071 dy*=0.7071 end
 p.vx=dx*dashspeed
 p.vy=dy*dashspeed
 p.dashing=true
 p.dash_t=dashtime
 p.freeze=freezetime
 p.can_dash=false
 trail={}
end

function kill()
 deaths+=1
 p.x=startx p.y=starty
 p.vx=0 p.vy=0 p.rem_x=0 p.rem_y=0
 p.can_dash=true p.dashing=false p.dash_t=0 p.freeze=0
 p.facing=1
 trail={} got={} berries=0
end

function hit_tile(c,vy_ok)
 local bx=p.x+p.hbx local by=p.y+p.hby
 local tx0=flr(bx/8) local tx1=flr((bx+p.hbw-1)/8)
 local ty0=flr(by/8) local ty1=flr((by+p.hbh-1)/8)
 for ty=ty0,ty1 do for tx=tx0,tx1 do
  if tchar(tx,ty)==c and (vy_ok==nil or p.vy>=0) then
   return tx,ty
  end
 end end
 return nil
end

function check_spikes()
 if p.vy<0 then return end
 local bx=p.x+p.hbx local by=p.y+p.hby
 local px0=bx local px1=bx+p.hbw-1
 local py0=by local py1=by+p.hbh-1
 local tx0=flr(bx/8) local tx1=flr((bx+p.hbw-1)/8)
 local ty0=flr(by/8) local ty1=flr((by+p.hbh-1)/8)
 for ty=ty0,ty1 do for tx=tx0,tx1 do
  if tchar(tx,ty)=="^" then
   local sx0=tx*8+1 local sy0=ty*8+3
   local sx1=sx0+5 local sy1=sy0+4
   if px0<=sx1 and px1>=sx0 and py0<=sy1 and py1>=sy0 then
    kill() return
   end
  end
 end end
end

function check_berries()
 local tx,ty=hit_tile("S",true)
 if tx then
  local k=tx..","..ty
  if got[k]==nil then got[k]=true berries+=1 end
 end
end

function check_goal()
 if hit_tile("F",nil) then win=true end
end

function _update()
 fr+=1
 for s in all(snow) do
  s.y+=s.sp
  if s.y>128 then s.y=0 s.x=rnd(128) end
 end
 if win then return end
 if p.freeze>0 then p.freeze-=1 return end
 if p.dash_t>0 then
  pmove()
  add(trail,{x=p.x,y=p.y})
  if #trail>8 then del(trail,trail[1]) end
  p.dash_t-=1
  if p.dash_t==0 then
   p.dashing=false
   p.vy=0
   if abs(p.vx)>maxrun then p.vx=sgn(p.vx)*maxrun end
  end
  check_spikes() check_berries() check_goal()
  return
 end
 local inp=0
 if btn(0) then inp=-1 p.facing=-1 elseif btn(1) then inp=1 p.facing=1 end
 if inp!=0 then
  p.vx=appr(p.vx,inp*maxrun,accel)
 else
  p.vx=appr(p.vx,0,accel)
 end
 if btnp(4) and p.on_ground then
  p.vy=jumpv p.on_ground=false
 end
 if btnp(5) and p.can_dash then
  start_dash() return
 end
 p.vy=appr(p.vy,maxfall,grav)
 pmove()
 if p.on_ground then p.can_dash=true end
 if p.x<0 then p.x=0 p.vx=0 end
 if p.x>120 then p.x=120 p.vx=0 end
 if p.y>128 then kill() return end
 check_spikes() check_berries() check_goal()
end

function _draw()
 rectfill(0,0,128,128,12)
 ftri(0,72,28,38,58,72,1)
 ftri(38,72,72,32,108,72,1)
 ftri(82,72,112,46,130,72,1)
 ftri(22,90,62,56,102,90,5)
 ftri(80,90,118,62,140,90,5)
 ftri(25,44,28,38,31,44,7)
 ftri(69,38,72,32,75,38,7)
 for ty=0,15 do for tx=0,15 do
  local c=tchar(tx,ty)
  if c=="#" then spr(sp_tile,tx*8,ty*8)
  elseif c=="^" then spr(sp_spike,tx*8,ty*8)
  elseif c=="F" then spr(sp_flag,tx*8,ty*8)
  elseif c=="S" then
   if got[tx..","..ty]==nil then
    spr(sp_berry,tx*8,ty*8+sin(fr*0.08)*1)
   end
  end
 end end
 for s in all(snow) do pset(s.x,s.y,7) end
 for t in all(trail) do
  rectfill(t.x+3,t.y+3,t.x+4,t.y+4,7)
 end
 if not p.can_dash then pal(8,12) end
 spr(sp_player,p.x,p.y)
 pal()
 print("berries:"..berries,2,2,7)
 print("deaths:"..deaths,2,9,6)
 if win then
  rectfill(36,54,92,74,0)
  print("clear!",54,58,10)
  print("berries:"..berries,44,66,7)
 end
end

__gfx__
00888880777777770600006000c00c00500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0888888866666666066006600cccccc05aaaaaa00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
088ff8805555555506660666008888005aaaaaa00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
08f00f805444444566666666088888805aaaaaa00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
088ff8804444444400000000087087805aaaaaa00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00888800454444540000000008888880500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0cccccc0444444440000000000888800500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0c0cc0c0444444440000000000000000500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
