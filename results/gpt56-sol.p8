pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
-- design notes: compact snowy cave, crisp retries, red/blue dash hair, and celeste-like berries.
-- movement: run 1.5, jump -3.4, gravity .18, fall 2.5; dash 4.5 for 8 frames.
-- climax: a 70px gap exceeds the 58.5px run-jump range but fits the 94.5px dash reach.
-- route: safe right jump, left reversal, spike-threaded diagonal rise, then a high return.
-- the final horizontal dash crosses to a safe snowy goal shelf after the vertical variation.
-- demo takes the risky extra jump to the tiny far-left berry perch, skipping the east berry.
-- controls: arrows move/aim, btnp(4) jumps, btnp(5) dashes; any button cancels autoplay.

title="GPT-5.6 Sol"
gif_name="gpt56-sol.gif"

plats={
 {x=3,y=116,w=53,h=12},
 {x=40,y=100,w=33,h=9},
 {x=8,y=84,w=27,h=8},
 {x=1,y=69,w=11,h=7},
 {x=46,y=68,w=30,h=9},
 {x=8,y=52,w=27,h=9},
 {x=104,y=52,w=23,h=14},
 {x=82,y=95,w=17,h=7}
}

spikes={
 {x=56,y=113,w=48,h=8},
 {x=46,y=62,w=7,h=6},
 {x=69,y=62,w=7,h=6}
}

berries={
 {x=3,y=59,got=false},
 {x=88,y=86,got=false}
}

function _init()
 srand(56)
 snow={}
 trail={}
 dust={}
 for i=1,18 do
  add(snow,{x=rnd(128),y=rnd(128),s=.15+rnd(.25),c=i%4==0 and 6 or 7})
 end
 demo=true
 dphase=0
 dshot=false
 oldctl={}
 ctl={}
 for i=0,5 do oldctl[i]=false ctl[i]=false end
 deaths=0
 score=0
 won=false
 clear_t=0
 gif_saved=false
 reset_player()
 extcmd("set_filename",gif_name)
 extcmd("rec_frames")
end

function reset_player()
 p={x=11,y=109,vx=0,vy=0,w=6,h=7,face=1,can_dash=true,dash_t=0,freeze=0}
end

function respawn()
 deaths+=1
 reset_player()
 if demo then
  dphase=0
  dshot=false
  score=0
  for b in all(berries) do b.got=false end
 end
end

function raw_button()
 for i=0,5 do if btn(i) then return true end end
 return false
end

function grounded()
 return solid_at(p.x,p.y+1)
end

function on_plat(n)
 local r=plats[n]
 return grounded() and abs((p.y+p.h)-r.y)<1.1 and p.x+p.w>r.x and p.x<r.x+r.w
end

function demo_inputs()
 for i=0,5 do ctl[i]=false end
 local g=grounded()

 -- resolve landings before choosing this frame's next action
 if dphase==0 and on_plat(2) then dphase=1
 elseif dphase==1 and on_plat(3) then dphase=2
 elseif dphase==2 and berries[1].got and on_plat(4) then dphase=3
 elseif dphase==3 and on_plat(3) then dphase=4 dshot=false
 elseif dphase==4 and on_plat(5) then dphase=5
 elseif dphase==5 and on_plat(6) then dphase=6 dshot=false
 elseif dphase==6 and on_plat(7) then dphase=7 end

 if dphase==0 then
  -- safe introduction: run, then jump right onto the broad shelf
  if g and p.x<22 then ctl[1]=true
  elseif g then ctl[1]=true ctl[4]=true
  elseif p.x<52 then ctl[1]=true
  elseif p.x>58 then ctl[0]=true end

 elseif dphase==1 then
  -- reverse left to the middle shelf
  if g then ctl[0]=true ctl[4]=true
  elseif p.x>19 then ctl[0]=true
  elseif p.x<14 then ctl[1]=true end

 elseif dphase==2 then
  -- optional extra-risk berry jump to the tiny western perch
  if g then ctl[0]=true ctl[4]=true
  elseif p.x>3 then ctl[0]=true
  else ctl[1]=true end

 elseif dphase==3 then
  -- jump back down to rejoin the main route
  if g then ctl[1]=true ctl[4]=true
  elseif p.x<18 then ctl[1]=true
  elseif p.x>25 then ctl[0]=true end

 elseif dphase==4 then
  -- diagonal up-right dash threads the spike-edged landing
  if g then ctl[1]=true ctl[4]=true
  elseif not dshot and p.y<74 then
   ctl[1]=true ctl[2]=true ctl[5]=true dshot=true
  elseif p.x<56 then ctl[1]=true
  elseif p.x>60 then ctl[0]=true end

 elseif dphase==5 then
  -- another reversal climbs to the launch shelf
  if g then ctl[0]=true ctl[4]=true
  elseif p.x>21 then ctl[0]=true
  elseif p.x<15 then ctl[1]=true end

 elseif dphase==6 then
  -- jump, then horizontal dash near the apex of the forced 70px gap
  if g and p.x<25 then ctl[1]=true
  elseif g then ctl[1]=true ctl[4]=true
  elseif not dshot and p.vy>-.45 then
   ctl[1]=true ctl[5]=true dshot=true
  elseif p.x<113 then ctl[1]=true
  else ctl[0]=true end

 elseif dphase==7 then
  ctl[1]=true
 end
end

function read_inputs()
 if demo and raw_button() then
  demo=false
  score=0
  for b in all(berries) do b.got=false end
  reset_player()
  for i=0,5 do oldctl[i]=false end
 end
 if demo then
  demo_inputs()
 else
  for i=0,5 do ctl[i]=btn(i) end
 end
end

function pressed(i)
 return ctl[i] and not oldctl[i]
end

function overlap(x,y,w,h,r)
 return x+w>r.x and x<r.x+r.w and y+h>r.y and y<r.y+r.h
end

function solid_at(x,y)
 if x<1 or x+p.w>127 then return true end
 for r in all(plats) do
  if overlap(x,y,p.w,p.h,r) then return true end
 end
 return false
end

function move_x(a)
 while abs(a)>.001 do
  local s=mid(-1,a,1)
  if solid_at(p.x+s,p.y) then
   p.vx=0
   p.dash_t=0
   return
  end
  p.x+=s
  a-=s
 end
end

function move_y(a)
 while abs(a)>.001 do
  local s=mid(-1,a,1)
  if solid_at(p.x,p.y+s) then
   p.vy=0
   p.dash_t=0
   return
  end
  p.y+=s
  a-=s
 end
end

function start_dash()
 local dx=(ctl[1] and 1 or 0)-(ctl[0] and 1 or 0)
 local dy=(ctl[3] and 1 or 0)-(ctl[2] and 1 or 0)
 if dx==0 and dy==0 then dx=p.face end
 if dx!=0 and dy!=0 then dx*=.7071 dy*=.7071 end
 p.vx=dx*4.5
 p.vy=dy*4.5
 p.dash_t=8
 p.freeze=2
 p.can_dash=false
 for i=1,4 do
  add(trail,{x=p.x+rnd(4),y=p.y+rnd(6),t=7-i})
 end
end

function hazard_check()
 if p.vy>=0 then
  for s in all(spikes) do
   if overlap(p.x+1,p.y+1,p.w-2,p.h-1,s) then
    respawn()
    return true
   end
  end
 end
 if p.y>128 then respawn() return true end
 return false
end

function object_check()
 for b in all(berries) do
  if not b.got and overlap(p.x,p.y,p.w,p.h,{x=b.x,y=b.y,w=6,h=7}) then
   b.got=true
   score+=1
   for i=1,7 do add(dust,{x=b.x+3,y=b.y+3,vx=rnd(2)-1,vy=rnd(2)-1,t=14,c=8}) end
  end
 end
 local goal={x=116,y=39,w=9,h=13}
 if grounded() and overlap(p.x,p.y,p.w,p.h,goal) then
  won=true
  clear_t=0
  p.vx=0 p.vy=0
 end
end

function update_fx()
 for s in all(snow) do
  s.y+=s.s
  s.x+=.08
  if s.y>127 then s.y=-2 s.x=rnd(128) end
  if s.x>127 then s.x=0 end
 end
 for q in all(trail) do
  q.t-=1
  if q.t<=0 then del(trail,q) end
 end
 for q in all(dust) do
  q.x+=q.vx q.y+=q.vy q.vy+=.08 q.t-=1
  if q.t<=0 then del(dust,q) end
 end
end

function _update()
 if won then
  if demo and not gif_saved then
   clear_t+=1
   if clear_t>=45 then
    extcmd("video",4,1)
    gif_saved=true
   end
  end
  return
 end

 read_inputs()
 update_fx()

 if p.freeze>0 then
  p.freeze-=1
 else
  if pressed(5) and p.can_dash then start_dash() end

  if p.dash_t>0 then
   add(trail,{x=p.x,y=p.y,t=5})
   move_x(p.vx)
   move_y(p.vy)
   p.dash_t-=1
  else
   local m=(ctl[1] and 1 or 0)-(ctl[0] and 1 or 0)
   if m!=0 then
    p.vx=mid(-1.5,p.vx+m*.3,1.5)
    p.face=m
   else
    p.vx=approach(p.vx,0,.22)
   end
   if pressed(4) and grounded() then
    p.vy=-3.4
    for i=1,3 do add(dust,{x=p.x+3,y=p.y+7,vx=rnd(1)-.5,vy=-rnd(1),t=9,c=7}) end
   end
   p.vy=min(2.5,p.vy+.18)
   move_x(p.vx)
   move_y(p.vy)
  end
 end

 if grounded() and p.vy>=0 then p.can_dash=true end
 if not hazard_check() then object_check() end
 for i=0,5 do oldctl[i]=ctl[i] end
end

function approach(v,t,a)
 if v<t then return min(v+a,t) end
 return max(v-a,t)
end

function draw_mountain()
 cls(0)
 -- cold blue cave openings and layered rock, echoing the reference scene
 rectfill(0,14,127,127,1)
 rectfill(0,77,127,127,0)
 palt(0,false)
 color(5)
 for x=0,127,16 do
  local h=18+((x/16)%3)*7
  uptri(x,72,13,h,5)
 end
 rectfill(0,0,127,12,5)
 for x=0,127,16 do
  rectfill(x,10,x+8,14+(x%5),5)
 end
 rectfill(5,20,34,23,13)
 rectfill(91,25,119,28,13)
 rectfill(14,36,28,39,1)
 rectfill(70,34,84,37,1)
end

function uptri(x,y,w,h,c)
 for dy=0,h do
  local inset=flr(dy*w/(h*2))
  line(x+inset,y-dy,x+w-inset,y-dy,c)
 end
end

function draw_platform(r)
 rectfill(r.x,r.y,r.x+r.w-1,r.y+r.h-1,5)
 rectfill(r.x,r.y,r.x+r.w-1,r.y+1,7)
 for x=r.x+2,r.x+r.w-2,6 do
  pset(x,r.y+2,6)
 end
 if r.y<110 then
  line(r.x+2,r.y+r.h,r.x+r.w-4,r.y+r.h,1)
 end
end

function draw_spikes(s)
 for x=s.x,s.x+s.w-1,4 do
  uptri(x,s.y+s.h-1,3,s.h-1,7)
  pset(x+2,s.y+1,6)
 end
end

function draw_berry(b)
 if b.got then return end
 local x=b.x local y=b.y
 pset(x+2,y,3) pset(x+4,y,3)
 rectfill(x+1,y+2,x+5,y+5,8)
 pset(x,y+3,8) pset(x+3,y+6,8)
 pset(x+2,y+3,10) pset(x+4,y+4,10)
end

function draw_flag()
 line(119,40,119,51,3)
 rectfill(120,40,125,46,14)
 rectfill(120,40,123,42,8)
 pset(121,43,15)
end

function draw_player()
 local x=flr(p.x) local y=flr(p.y)
 local hc=p.can_dash and 8 or 12
 if p.dash_t>0 then hc=7 end
 -- six-pixel madeline silhouette: bright hair, face, pack and teal coat
 rectfill(x+1,y,x+4,y+2,hc)
 pset(x,y+1,hc) pset(x+5,y+2,hc)
 rectfill(x+2,y+2,x+4,y+4,15)
 pset(x+4,y+3,0)
 rectfill(x+1,y+4,x+4,y+6,3)
 pset(x,y+4,hc)
 pset(x+1,y+7,6) pset(x+4,y+7,6)
end

function draw_ui()
 rectfill(39,0,89,8,0)
 print(title,42,2,7)
 print("x"..score,3,3,7)
 draw_berry({x=1,y=1,got=false})
 if demo and not won then print("demo",105,3,6) end
end

function _draw()
 draw_mountain()
 for s in all(snow) do pset(flr(s.x),flr(s.y),s.c) end
 for r in all(plats) do draw_platform(r) end
 for s in all(spikes) do draw_spikes(s) end
 for b in all(berries) do draw_berry(b) end
 draw_flag()
 for q in all(trail) do
  if q.t%2==0 then rectfill(q.x,q.y,q.x+2,q.y+2,7) else pset(q.x,q.y,7) end
 end
 for q in all(dust) do pset(q.x,q.y,q.c) end
 draw_player()
 draw_ui()
 if won then
  rectfill(31,77,96,100,0)
  rect(31,77,96,100,7)
  print("clear!",51,82,7)
  print("berries "..score,45,91,8)
 end
end
