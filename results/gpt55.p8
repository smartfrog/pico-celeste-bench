pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
-- celeste classic: snowy one-screen cave, crisp tiny sprites, fast retries.
-- movement: run 1.1, jump -3.0, gravity .24, fall 2.4, dash 4.0 for 8f.
-- forced dash: 40px spike gap; run-jump is about 28px, jump+dash about 60px.
-- route: left ledge to right steps, two optional berries, flag in the upper-right.
-- controls: btn0/1 move, btn2/3 aim up/down, btnp4 jump, btnp5 dash.

lvl={
"................",
"................",
"..............f.",
"............####",
"................",
".............###",
"...........o....",
"............####",
"....o...........",
"...........#####",
"................",
"#####.....######",
"................",
".....^^^^^......",
"################",
"################"
}

startx=13
starty=80
run=1.1
acc=.22
fric=.16
grav=.24
fall=2.4
jump=-3
dash_spd=4
dash_len=8
fr=0

function tile(tx,ty)
 if tx<0 or tx>15 or ty<0 or ty>15 then return "#" end
 return sub(lvl[ty+1],tx+1,tx+1)
end

function pix_tile(x,y)
 return tile(flr(x/8),flr(y/8))
end

function solid_px(x,y)
 return pix_tile(x,y)=="#"
end

function solid_player(x,y)
 return solid_px(x+1,y+1) or solid_px(x+6,y+1) or
        solid_px(x+1,y+7) or solid_px(x+6,y+7)
end

function grounded()
 return solid_player(p.x,p.y+1)
end

function recthit(x1,y1,w1,h1,x2,y2,w2,h2)
 return x1<x2+w2 and x2<x1+w1 and y1<y2+h2 and y2<y1+h1
end

function reset_player()
 p={x=startx,y=starty,dx=0,dy=0,f=1,can_dash=true,dash_t=0}
 freeze=0
 trails={}
end

function _init()
 srand(1)
 berries={}
 goal={x=112,y=16}
 for y=0,15 do
  for x=0,15 do
   local c=tile(x,y)
   if c=="o" then add(berries,{x=x*8,y=y*8,got=false}) end
   if c=="f" then goal={x=x*8,y=y*8} end
  end
 end
 snow={}
 for i=1,28 do add(snow,{x=rnd(128),y=rnd(128),s=.25+rnd(.55)}) end
 score=0
 deaths=0
 win=false
 reset_player()
end

function move_x(v)
 local s=sgn(v)
 local n=abs(v)
 while n>0 do
  local st=min(1,n)*s
  if not solid_player(p.x+st,p.y) then
   p.x+=st
  else
   p.dx=0
   return
  end
  n-=abs(st)
 end
end

function move_y(v)
 local s=sgn(v)
 local n=abs(v)
 while n>0 do
  local st=min(1,n)*s
  if not solid_player(p.x,p.y+st) then
   p.y+=st
  else
   p.dy=0
   return
  end
  n-=abs(st)
 end
end

function emit_trail()
 add(trails,{x=p.x,y=p.y,t=7})
 if #trails>12 then deli(trails,1) end
end

function start_dash()
 local dx=(btn(1) and 1 or 0)-(btn(0) and 1 or 0)
 local dy=(btn(3) and 1 or 0)-(btn(2) and 1 or 0)
 if dx==0 and dy==0 then dx=p.f end
 if dx!=0 and dy!=0 then dx*=.7071 dy*=.7071 end
 p.dx=dx*dash_spd
 p.dy=dy*dash_spd
 p.dash_t=dash_len
 p.can_dash=false
 freeze=2
 emit_trail()
end

function die()
 deaths+=1
 reset_player()
 freeze=4
end

function touch_spike()
 if p.dy<0 then return false end
 return pix_tile(p.x+2,p.y+7)=="^" or pix_tile(p.x+5,p.y+7)=="^"
end

function update_fx()
 for s in all(snow) do
  s.y+=s.s
  s.x+=.08
  if s.y>127 then s.y=0 s.x=rnd(128) end
  if s.x>127 then s.x=0 end
 end
 for t in all(trails) do
  t.t-=1
  if t.t<=0 then del(trails,t) end
 end
end

function collect_and_goal()
 for b in all(berries) do
  if not b.got and recthit(p.x+1,p.y+1,6,7,b.x+2,b.y+2,4,4) then
   b.got=true
   score+=1
  end
 end
 if recthit(p.x+1,p.y+1,6,7,goal.x+1,goal.y,6,8) then
  win=true
  p.dx=0
  p.dy=0
 end
end

function _update()
 if win then return end
 fr+=1
 update_fx()
 if freeze>0 then freeze-=1 return end

 if grounded() then p.can_dash=true end

 if p.dash_t>0 then
  p.dash_t-=1
  emit_trail()
  move_x(p.dx)
  move_y(p.dy)
  if p.dash_t<=0 then p.dx*=.35 p.dy*=.35 end
 else
  if btn(0) then p.dx-=acc p.f=-1 end
  if btn(1) then p.dx+=acc p.f=1 end
  if not btn(0) and not btn(1) then
   if abs(p.dx)<=fric then p.dx=0 else p.dx-=sgn(p.dx)*fric end
  end
  p.dx=mid(-run,p.dx,run)
  if btnp(4) and grounded() then p.dy=jump end
  if btnp(5) and p.can_dash then start_dash() return end
  p.dy=min(fall,p.dy+grav)
  move_x(p.dx)
  move_y(p.dy)
 end

 if touch_spike() then die() return end
 collect_and_goal()
end

function draw_bg()
 cls(12)
 rectfill(18,10,109,126,0)
 rectfill(35,28,98,42,1)
 rectfill(28,60,116,72,1)
 rectfill(40,96,123,108,1)
 for i=0,7 do rectfill(18+i*8,84-i*7,32+i*8,126,5) end
 for i=0,6 do rectfill(96-i*7,18+i*7,112,126,5) end
 rectfill(0,0,7,127,12)
 rectfill(120,0,127,127,12)
 rectfill(0,0,127,5,7)
 rectfill(0,121,127,127,7)
 for i=0,12 do
  local x=(i*23+fr/4)%128
  pset(x,(i*17+11)%128,7)
 end
end

function draw_solid(tx,ty)
 local x=tx*8
 local y=ty*8
 rectfill(x,y,x+7,y+7,5)
 if tile(tx,ty-1)!="#" then
  rectfill(x,y,x+7,y+2,7)
  rectfill(x,y+2,x+7,y+2,6)
 end
 if tile(tx-1,ty)!="#" then rectfill(x,y,x,y+7,7) end
 if tile(tx+1,ty)!="#" then rectfill(x+7,y,x+7,y+7,0) end
 if (tx+ty)%3==0 then pset(x+2,y+5,0) end
 if (tx*2+ty)%5==0 then pset(x+5,y+4,6) end
end

function draw_level()
 for y=0,15 do
  for x=0,15 do
   local c=tile(x,y)
   if c=="#" then draw_solid(x,y) end
   if c=="^" then spr(4,x*8,y*8) end
  end
 end
 for b in all(berries) do
  if not b.got then spr(2,b.x,b.y) end
 end
 spr(3,goal.x,goal.y)
end

function draw_player()
 for t in all(trails) do
  rectfill(t.x+1,t.y+1,t.x+6,t.y+6,7)
 end
 spr(p.can_dash and 1 or 16,p.x,p.y,1,1,p.f<0)
end

function _draw()
 draw_bg()
 draw_level()
 draw_player()
 for s in all(snow) do pset(s.x,s.y,7) end
 spr(2,2,2)
 print(score.."/"..#berries,11,3,7)
 print("d"..deaths,2,113,6)
 if p.can_dash then print("dash",92,3,7) else print("dash",92,3,6) end
 if win then
  rectfill(37,52,91,75,0)
  rect(37,52,91,75,7)
  print("clear!",51,58,7)
  print("berries "..score.."/"..#berries,43,68,14)
 end
end
__gfx__
0000000000e88e00000bb00000e00e0000077000000b000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000e8888e000b88b000eeeeee00007700000bb000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000efefe000088880000eeee0000777700000b000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000ff3000088a8880000bb0000077770000bb000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000033330008888880000bb00007766770000b000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000333300008a8800000bb0000776677000bb000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000003030000008800000b00b007776677700b0b00000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000666666660000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00cddc00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0cddddc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0cfcfc00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00ff3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00333300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00333300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
