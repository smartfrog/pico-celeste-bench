pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
-- opus 4.8 - celeste-like (single screen)
-- traits: run+jump+8dir dash, dash recharges only on ground, hair color=dash ready
-- consts: run 1, accel .6, decel .15, grav .21, jump -2, dash 5 (diag*.707), dash 4f, freeze 2f
-- forced dash: 4-tile gap (cols 10-13) at the climax; jump+dash clears it, a plain jump cannot
-- route: intro jump over spike > two rising jumps up the ledges > up-dash berry detour > forced right dash to flag
-- demo grabs one strawberry via the up-dash detour (exactly 1) then clears the goal
-- controls: btn0/1 move left/right, btn2/3 aim dash up/down, o=jump(btn4), x=dash(btn5)

lvl={
 "................",
 "................",
 "................",
 "................",
 "................",
 "................",
 ".............s..",
 "........s.......",
 "..............gg",
 "..............##",
 "........##......",
 "......##........",
 "...##...........",
 "##^.............",
 "###.......^^^^..",
 "###.......####..",
}

spawn_x=2
spawn_y=96

held={}
prev={}
demo_mode=true
demo_i=1
demo_c=0
deaths=0
score=0
win=false
win_t=0
gif_saved=false

demo={
 {n=10,k="r"},
 {n=1,k="ro"},
 {n=14,k="r"},
 {n=3,k=""},
 {n=7,k="r"},
 {n=1,k="ro"},
 {n=15,k="r"},
 {n=3,k=""},
 {n=6,k="r"},
 {n=1,k="ro"},
 {n=13,k="r"},
 {n=3,k=""},
 {n=1,k="ux"},
 {n=14,k=""},
 {n=4,k="r"},
 {n=1,k="ro"},
 {n=1,k="rx"},
 {n=16,k="r"},
 {n=90,k=""},
}

function _init()
 make_snow()
 trail={}
 dust={}
 start_run(true)
end

function start_run(dm)
 demo_mode=dm
 demo_i=1
 demo_c=0
 score=0
 win=false
 win_t=0
 gif_saved=false
 berries={}
 goals={}
 for ty=0,15 do
  for tx=0,15 do
   local c=mget2(tx,ty)
   if c=="s" then add(berries,{x=tx,y=ty,got=false}) end
   if c=="g" then add(goals,{x=tx,y=ty}) end
  end
 end
 for i=0,5 do held[i]=false prev[i]=false end
 respawn()
 if dm then
  extcmd("set_filename","opus48.gif")
  extcmd("rec_frames")
 end
end

function respawn()
 p={x=spawn_x,y=spawn_y,dx=0,dy=0,dt=0,fz=0,cd=true,f=1,gr=0}
end

function mget2(tx,ty)
 if tx<0 or tx>15 or ty<0 or ty>15 then return "." end
 return sub(lvl[ty+1],tx+1,tx+1)
end

function solid_tile(tx,ty)
 if tx<0 or tx>15 then return true end
 return mget2(tx,ty)=="#"
end

function appr(v,t,a)
 if v>t then return max(v-a,t) end
 return min(v+a,t)
end

function hasc(s,c)
 local i=1
 while true do
  local ch=sub(s,i,i)
  if ch=="" then return false end
  if ch==c then return true end
  i+=1
 end
end

function cur_keys()
 if demo_i>#demo then return "" end
 local seg=demo[demo_i]
 local k=seg.k
 demo_c+=1
 if demo_c>=seg.n then demo_i+=1 demo_c=0 end
 return k
end

function set_inputs()
 for i=0,5 do prev[i]=held[i] end
 if demo_mode then
  for i=0,5 do
   if btnp(i) then start_run(false) break end
  end
 end
 if demo_mode then
  local k=cur_keys()
  held[0]=hasc(k,"l")
  held[1]=hasc(k,"r")
  held[2]=hasc(k,"u")
  held[3]=hasc(k,"d")
  held[4]=hasc(k,"o")
  held[5]=hasc(k,"x")
 else
  for i=0,5 do held[i]=btn(i) end
 end
end

function ib(i) return held[i] end
function ibp(i) return held[i] and not prev[i] end

function collide(x,y)
 local x0=flr((x+1)/8)
 local x1=flr((x+6)/8)
 local y0=flr((y+2)/8)
 local y1=flr((y+7)/8)
 for tx=x0,x1 do
  for ty=y0,y1 do
   if solid_tile(tx,ty) then return true end
  end
 end
 return false
end

function move_x(a)
 local s=sgn(a)
 local n=abs(a)
 while n>0 do
  local d=min(n,1)
  if not collide(p.x+s*d,p.y) then
   p.x+=s*d
  else
   p.dx=0
   return
  end
  n-=d
 end
end

function move_y(a)
 local s=sgn(a)
 local n=abs(a)
 while n>0 do
  local d=min(n,1)
  if not collide(p.x,p.y+s*d) then
   p.y+=s*d
  else
   p.dy=0
   return
  end
  n-=d
 end
end

function near(tx,ty,m)
 return abs(p.x+4-(tx*8+4))<m and abs(p.y+4-(ty*8+4))<m
end

function hit_spike()
 if p.dy<-0.1 then return false end
 local x0=flr((p.x+1)/8)
 local x1=flr((p.x+6)/8)
 local y0=flr((p.y+4)/8)
 local y1=flr((p.y+7)/8)
 for tx=x0,x1 do
  for ty=y0,y1 do
   if mget2(tx,ty)=="^" then return true end
  end
 end
 return false
end

function die()
 deaths+=1
 make_death()
 respawn()
end

function update_player()
 if win then return end
 if p.fz>0 then p.fz-=1 return end

 local ix=(ib(1) and 1 or 0)-(ib(0) and 1 or 0)
 local iy=(ib(3) and 1 or 0)-(ib(2) and 1 or 0)
 if ix!=0 then p.f=ix end

 local g=collide(p.x,p.y+1)
 if g then
  p.cd=true
  p.gr=4
 elseif p.gr>0 then
  p.gr-=1
 end

 if ibp(4) and (g or p.gr>0) then
  p.dy=-2
  p.gr=0
 end

 if ibp(5) and p.cd then
  p.cd=false
  p.dt=5
  p.fz=2
  if ix==0 and iy==0 then
   p.dx=p.f*5 p.dy=0
  elseif ix!=0 and iy!=0 then
   p.dx=ix*3.5355 p.dy=iy*3.5355
  else
   p.dx=ix*5 p.dy=iy*5
  end
  add_trail()
  return
 end

 if p.dt>0 then
  p.dt-=1
  add_trail()
  if p.dt==0 and p.dy<0 then p.dy=0 end
 else
  local acc=g and 0.6 or 0.4
  if ix!=0 then p.dx=appr(p.dx,ix,acc) else p.dx=appr(p.dx,0,0.15) end
  local gg=0.21
  if abs(p.dy)<0.15 then gg=0.105 end
  p.dy=appr(p.dy,2,gg)
 end

 move_x(p.dx)
 move_y(p.dy)

 if hit_spike() then die() return end
 if p.y>136 then die() return end

 for b in all(berries) do
  if not b.got and near(b.x,b.y,9) then
   b.got=true
   score+=1
  end
 end

 for gl in all(goals) do
  if near(gl.x,gl.y,9) then
   win=true
   win_t=0
  end
 end
end

function make_snow()
 snow={}
 for i=1,26 do
  add(snow,{x=rnd(128),y=rnd(128),vy=0.3+rnd(0.7),vx=-0.3-rnd(0.4),c=(rnd(1)<0.5) and 6 or 7})
 end
end

function add_trail()
 add(trail,{x=p.x+3,y=p.y+3,t=6})
end

function make_death()
 for i=1,10 do
  add(dust,{x=p.x+4,y=p.y+4,vx=cos(i/10)*1.3,vy=sin(i/10)*1.3,t=14})
 end
end

function update_particles()
 for s in all(snow) do
  s.y+=s.vy s.x+=s.vx
  if s.y>128 then s.y=0 s.x=rnd(128) end
  if s.x<0 then s.x=127 end
 end
 for t in all(trail) do
  t.t-=1
  if t.t<=0 then del(trail,t) end
 end
 for d in all(dust) do
  d.x+=d.vx d.y+=d.vy d.vy+=0.12 d.t-=1
  if d.t<=0 then del(dust,d) end
 end
end

function _update()
 set_inputs()
 update_particles()
 update_player()
 if demo_mode and win then
  win_t+=1
  if win_t==45 and not gif_saved then
   extcmd("video",4,1)
   gif_saved=true
  end
 end
end

function draw_level()
 for ty=0,15 do
  for tx=0,15 do
   local c=mget2(tx,ty)
   if c=="#" then
    if mget2(tx,ty-1)=="#" then
     spr(16,tx*8,ty*8)
    else
     spr(17,tx*8,ty*8)
    end
   elseif c=="^" then
    spr(4,tx*8,ty*8)
   end
  end
 end
end

function draw_berries()
 for b in all(berries) do
  if not b.got then
   spr(3,b.x*8,b.y*8+sin(time()/2+b.x))
  end
 end
end

function draw_goal()
 for gl in all(goals) do
  if gl.x==14 then
   spr(5,gl.x*8,gl.y*8)
  end
 end
end

function draw_player()
 spr(1,p.x,p.y,1,1,p.f<0)
 local hc=p.cd and 8 or 12
 rectfill(p.x+2,p.y,p.x+5,p.y+1,hc)
 if p.f>0 then
  rectfill(p.x+1,p.y+1,p.x+1,p.y+2,hc)
 else
  rectfill(p.x+5,p.y+1,p.x+6,p.y+2,hc)
 end
end

function draw_trail()
 for t in all(trail) do
  local c=t.t>3 and 7 or 6
  rectfill(t.x-1,t.y-1,t.x+1,t.y+1,c)
 end
end

function draw_dust()
 for d in all(dust) do
  pset(d.x,d.y,7)
 end
end

function draw_hud()
 print("opus 4.8",49,3,0)
 print("opus 4.8",48,2,7)
 spr(3,1,0)
 print("x"..score,10,2,7)
end

function draw_clear()
 rectfill(40,56,88,70,0)
 rect(40,56,88,70,7)
 print("clear!",50,61,8)
 print("clear!",49,60,7)
end

function _draw()
 cls(1)
 rectfill(0,0,127,18,12)
 rectfill(0,19,127,34,13)
 for s in all(snow) do pset(s.x,s.y,s.c) end
 draw_level()
 draw_berries()
 draw_goal()
 draw_trail()
 draw_player()
 draw_dust()
 draw_hud()
 if win then draw_clear() end
end
__gfx__
00000000000000000000000000033000000000000688880000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000fff00000fff00000388300000000000688880000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000f0f00000f0f00008888880000000000688880000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000fff00000fff00008a88a80000770000688000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000033333000333330008888880000770000600000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000033333000333330000888800007777000600000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000005335000035300000088000077777700600000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000005005000404000000000000777777770600000000000000000000000000000000000000000000000000000000000000000000000000000000000000
55555555777777770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
55515555677777760000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
55555555566556650000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
15511155555555550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
55555555551551550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
55155515555555550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
55555555515555150000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
51555551555555550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
