pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
-- controls: arrows=move, z=jump(btnp4), x=dash(btnp5)
-- up(btn2) aim dash up, down(btn3) aim dash down
-- design notes:
--   emulates celeste classic: responsive run/jump/dash, 30fps
--   constants: maxrun=1, accel=0.6/0.4, jump=-2, grav=0.21
--   d_full=10, dash_time=3 (boosted for single-screen dash gap)
--   forced obstacle: 32px gap at row13 cols6-9;
--   run-jump~20px < gap < dash~40px, margins >8px
--   spikes (5,12) pre-gap + (11,10) climbing, strawbs at (36,72) + (100,44), flag (104,24)

function sign(v) return v>0 and 1 or v<0 and -1 or 0 end
function appr(v,t,r) if v>t then return max(v-r,t) end if v<t then return min(v+r,t) end return v end

p={x=8,y=96,vx=0,vy=0,remx=0,remy=0,facing=1,can_dash=true,
 dash_time=0,freeze=0,grace=0,jbuffer=0,on_ground=false,
 dead=false,win=false,spr_off=0}
score=0 deaths=0 djump=1 shake=0 win_phase=0 trails={} snow={}
strawbs={{x=36,y=72,c=false},{x=100,y=44,c=false}}
flag={x=104,y=24}

function solid_at(x,y,w,h)
 for tx=flr(x/8),flr((x+w-1)/8) do
  for ty=flr(y/8),flr((y+h-1)/8) do
   local t=mget(tx,ty) if t==1 or t==2 then return true end
  end
 end
 return false
end

function spike_at(x,y,w,h)
 for tx=flr(x/8),flr((x+w-1)/8) do
  for ty=flr(y/8),flr((y+h-1)/8) do
   if mget(tx,ty)==3 then return true end
  end
 end
 return false
end

function is_solid(ox,oy) return solid_at(p.x+1+ox,p.y+3+oy,6,5) end

function respawn()
 p.x=8 p.y=96 p.vx=0 p.vy=0 p.remx=0 p.remy=0
 p.dash_time=0 p.freeze=0 p.grace=0 p.jbuffer=0
 p.can_dash=true p.dead=false djump=1 deaths+=1 shake=8
end

function add_trail() add(trails,{x=p.x+4,y=p.y+4,t=5}) end

function move_x()
 p.remx+=p.vx local a=flr(p.remx+0.5) p.remx-=a local s=sign(a)
 for i=1,abs(a) do if not is_solid(s,0) then p.x+=s else p.vx=0 p.remx=0 break end end
end

function move_y()
 p.remy+=p.vy local a=flr(p.remy+0.5) p.remy-=a local s=sign(a)
 for i=1,abs(a) do if not is_solid(0,s) then p.y+=s else p.vy=0 p.remy=0 break end end
end

clouds={}
function _init()
 for i=0,5 do add(clouds,{x=rnd(128),y=8+rnd(32),w=24+rnd(32),spd=0.3+rnd(0.4)}) end
 for i=0,31 do
  add(snow,{x=rnd(128),y=rnd(128),spd=0.25+rnd(2),off=rnd(1),s=flr(rnd(2)),c=6+flr(0.5+rnd(1))})
 end
end

function _update()
 if p.dead then respawn() return end
 if p.win then return end
 if p.freeze>0 then p.freeze-=1 return end
 if shake>0 then shake-=1 end
 local input=btn(1) and 1 or btn(0) and -1 or 0
 if p.vy>0 and spike_at(p.x+1,p.y+3,6,5) then p.dead=true return end
 if p.y>128 then p.dead=true return end
 local on_ground=is_solid(0,1) p.on_ground=on_ground
 if btnp(4) then p.jbuffer=4 end
 if p.jbuffer>0 then p.jbuffer-=1 end
 if on_ground then p.grace=6 if djump<1 then djump=1 p.can_dash=true end
 elseif p.grace>0 then p.grace-=1 end
 local dp=btnp(5)
 if p.dash_time>0 then
  add_trail() p.dash_time-=1
  if p.dash_time<=0 then p.vx=appr(p.vx,0,abs(p.vx)*0.5) p.vy=appr(p.vy,0,abs(p.vy)*0.5) end
 elseif p.can_dash and dp then
  local dx=input local dy=0
  if btn(2) then dy=-1 end if btn(3) then dy=1 end
  if dx==0 and dy==0 then dx=p.facing end
  local spd=10 local dh=spd*0.7071
  if dx~=0 and dy~=0 then p.vx=dx*dh p.vy=dy*dh elseif dx~=0 then p.vx=dx*spd p.vy=0 else p.vx=0 p.vy=dy*spd end
  p.facing=dx~=0 and dx or p.facing
  p.dash_time=3 p.freeze=2 p.can_dash=false djump=0 shake=4 add_trail()
 else
  local maxrun=1 local accel=on_ground and 0.6 or 0.4 local deccel=0.15
  if abs(p.vx)>maxrun then p.vx=appr(p.vx,sign(p.vx)*maxrun,deccel)
  else p.vx=appr(p.vx,input*maxrun,accel) end
  if p.vx~=0 then p.facing=sign(p.vx) end
  local maxfall=2 local grav=0.21 if abs(p.vy)<=0.15 then grav*=0.5 end
  if not on_ground then p.vy=appr(p.vy,maxfall,grav) end
  if p.jbuffer>0 and p.grace>0 then p.vy=-2 p.jbuffer=0 p.grace=0 end
 end
 move_x() move_y()
 p.x=mid(-2,p.x,120) if p.x<=-2 or p.x>=120 then p.vx=0 end
 for s in all(strawbs) do if not s.c and abs(p.x+4-s.x)<7 and abs(p.y+4-s.y)<7 then s.c=true score+=1 end end
 if not p.win and abs(p.x+4-flag.x-2)<10 and abs(p.y+4-flag.y-6)<14 then p.win=true win_phase=0 end
 if p.win then win_phase+=1 end
 p.spr_off+=0.25
 if not on_ground then p.spr=9 elseif btn(3) then p.spr=10 elseif btn(2) then p.spr=6
 elseif abs(p.vx)<0.1 or input==0 then p.spr=6 else p.spr=6+(p.spr_off%4) end
 for i=#trails,1,-1 do trails[i].t-=1 if trails[i].t<=0 then del(trails,trails[i]) end end
 for sp in all(snow) do sp.x+=sp.spd sp.y+=sin(sp.off)*0.5 sp.off+=min(0.05,sp.spd/32) if sp.x>132 then sp.x=-4 sp.y=rnd(128) end end
end

function _draw()
 cls(1)
 local sx=0 sy=0 if shake>0 then sx=rnd(3)-1 sy=rnd(3)-1 end camera(sx,sy)
 -- clouds
 for c in all(clouds) do
  c.x+=c.spd if c.x>132 then c.x=-c.w-4 end
  rectfill(c.x,c.y,c.x+c.w,c.y+6+(1-c.w/48)*10,6)
 end
 map(0,0,0,0,16,16)
 for tr in all(trails) do circfill(tr.x,tr.y,1+tr.t%2,7) end
 spr(12,flag.x,flag.y) spr(13,flag.x-4,flag.y-6)
 for s in all(strawbs) do if not s.c then spr(11,s.x,s.y) end end
 if not p.dead then
  local hc=p.can_dash and 8 or 12
  local hx=p.x+4-p.facing*2 local hy=p.y+(btn(3) and 4 or 3)
  local lx,ly=hx,hy
  for i=1,5 do lx+=(hx-lx)/1.5 ly+=(hy+0.5-ly)/1.5 circfill(lx,ly,max(1,min(2,3-i)),hc) end
  spr(p.spr,p.x,p.y,1,1,p.facing<0)
 end
 for sp in all(snow) do rectfill(sp.x,sp.y,sp.x+sp.s,sp.y+sp.s,sp.c) end
 if score>0 then spr(11,2,2) print("x"..score,12,4,7) end
 if p.win then rectfill(24,42,104,86,0) print("clear!",44,50,7) print("score:"..score,44,58,7) print("deaths:"..deaths,44,66,7) end
 camera()
end

__gfx__
00000000555555551111151100005000000005555550000000088000000880000008800000088000000880000000330000000000000000000000000000000000
00000000566556651151151100056500000056555565000000888800008888000088880000888800088888800003303000005000000000000007700000000000
000000005655565551511511000566500005665555665000007F8F00007F8F00007F8F00007F8F00077F8F700003330000005000000BB0000077770000070000
0000000055555555115115110055566500556555555655000077F7000077F7000077F7000077F7000077F7000088888000005000000BBB000077770000000000
000000005565655551511511005555650555555555555550007FCC00007FCC00007FCC0007CFCC00007FCC000888888800005000000BB0000077770000000000
000000006555565511511511550555550555555555555550000CCC70000CC770000CCC7000CCCC00000CC0000884848800005000000000000077770000000000
000000005555555515111511550555550555555555555550000777000007C7000007C70000077C00000000000888888800005000000000000007700000000000
00000000555555555111151155055555000000000000000000000000000077000007007000007000000000000088888000005000000000000000000000000000

__map__
00000000000000000000000000000000
00000000000000000000000000000000
00000000000000000000000000000000
00000000000000000000000000010000
00000000000000000000000001010000
00000000000000000000000101010000
00000000000000000000000101010000
00000000000000000000000101010000
00000000000000000000000001010000
00000000000000000000000001010000
00000000000000000000010301010000
00000000000000000001010100000000
00000000000300000000000001010000
01010101010100000000010101010101
01010101010101010101010101010101
02020202020202020202020202020202
