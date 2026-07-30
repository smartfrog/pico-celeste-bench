pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
-- opus 5 "frostbite hollow" -- from the refs: black cavern negative space, navy distant ridges, gray-brown rock masses, cream snow caps with cyan ice blobs, red-pink berries with green stems, red-haired player.
-- constants exactly as supplied: max run 1, accel .6, decel .15, gravity .21, max fall 2, jump -2, dash 5 with .7071 diagonals, 2 hitstop updates then 4 moving dash updates, 6x6 hitbox.
-- climax: row 7 holds exactly 4 empty columns (7..10) over a spike pit; run + jump + horizontal dash crosses it and lands on the safe 2-wide shelf at cols 11-12, under the flag tier.
-- route: introduction hops east over the spiked notch onto the step, the reversal runs west and dashes up-left to the ice shelf, then east up to the high ledge, the gap, the elevated flag.
-- demo detour: on the high ledge it jumps and dashes straight up for the berry at col 4 row 4 (1 of 2; the nook berry at col 6 row 11 stays avoidable), lands, then crosses the gap.
-- the display name "Opus 5" sits in the quiet top 8px title zone with a black shadow; autoplay saves opus5.gif after 45 frozen clear! updates, and any physical button cancels autoplay.

-- controls: left/right run, up/down aim the dash, o jump, x dash

-- level: . empty  # solid  ^ spike  s spawn  b berry  g goal
lvl={
 "................",
 "................",
 "................",
 "................",
 "....b...........",
 "..............g.",
 ".............###",
 "....###....#####",
 "....###....#####",
 "##.........#####",
 "...........#####",
 "s..##.b....#####",
 "##.####....#####",
 "##.####....#####",
 "##^####^^^^#####",
 "################"}

-- supplied movement constants
maxrun,accel,decel=1,0.6,0.15
grav,maxfall,jumpv=0.21,2,-2
dashspd,diagf=5,0.7071
hitstop_n,dash_n=2,4

-- cyan ice veins, kept in connected patches inside the rock masses
icev={{0,9},{1,9},{5,8},{6,8},{12,9},{13,9},{12,10},{0,13},{1,13}}
-- distant navy massifs, drawn behind the playfield
bgm={{0,8,30,20},{8,20,40,28},{84,4,127,14},{72,14,127,24},{34,18,72,32},
     {24,50,66,78},{0,66,26,92},{96,28,127,50},{40,96,120,112},{0,116,127,127}}
-- ice light leaking in at the cavern mouths
bgi={{0,26,3,44},{124,30,127,56},{125,72,127,96},{0,86,2,102}}
-- distant snow drifts sitting on the far ridges
bgd={{14,12},{26,18},{86,2},{104,12},{30,46},{52,92},{4,62},{112,26}}

function appr(v,tg,st)
 if v>tg then return max(v-st,tg) end
 return min(v+st,tg)
end

function build()
 sol,spk,bry,gol,ice={},{},{},{},{}
 spawnc,spawnr=0,11
 for r=0,15 do
  local s=lvl[r+1]
  for c=0,15 do
   local ch,k=sub(s,c+1,c+1),r*16+c
   if ch=="#" then sol[k]=true
   elseif ch=="^" then spk[k]=true
   elseif ch=="b" then bry[k]=true
   elseif ch=="g" then gol[k]=true
   elseif ch=="s" then spawnc,spawnr=c,r end
  end
 end
 for v in all(icev) do ice[v[2]*16+v[1]]=true end
end

function boxhit(x,y)
 local l,r=flr(x/8),flr((x+5)/8)
 if l<0 or r>15 then return true end
 local t,b=flr(y/8),flr((y+5)/8)
 if t<0 then t=0 end
 if b>15 then b=15 end
 for rr=t,b do
  for cc=l,r do
   if sol[rr*16+cc] then return true end
  end
 end
 return false
end

function movex(d)
 local rem=d
 while abs(rem)>0.01 do
  local st=mid(-1,rem,1)
  if boxhit(px+st,py) then return true end
  px+=st rem-=st
 end
 return false
end

function movey(d)
 local rem=d
 while abs(rem)>0.01 do
  local st=mid(-1,rem,1)
  if boxhit(px,py+st) then return true end
  py+=st rem-=st
 end
 return false
end

function burst(x,y,n,c1,c2,sp)
 for i=1,n do
  add(sparks,{x=x,y=y,vx=rnd(sp*2)-sp,vy=rnd(sp*2)-sp-0.4,
              l=12+rnd(10),c=(i%2==0) and c1 or c2})
 end
end

function die()
 if dead then return end
 dead=true dtimer=0 deaths+=1
 burst(px+3,py+3,12,7,12,1.6)
 if demo then demo=false gifok=false end
end

function respawn()
 px,py=spawnc*8+1,spawnr*8+2
 vx,vy=0,0
 grounded=false can_dash=true dashing=false facing=1
 hitstop=0 dash_left=0 dash_vx=0 dash_vy=0
 dead=false dtimer=0
 trail={}
 burst(px+3,py+3,6,7,6,1)
end

function touch()
 if py>=128 then die() return end
 local l,r=max(flr(px/8),0),min(flr((px+5)/8),15)
 local t,b=max(flr(py/8),0),min(flr((py+5)/8),15)
 for rr=t,b do
  for cc=l,r do
   local k=rr*16+cc
   if spk[k] then
    if vy>=0 then die() return end
   elseif gol[k] then
    if not win then
     win=true wint=0 vx=0 vy=0
     burst(cc*8+4,rr*8+4,18,7,14,2)
    end
   elseif bry[k] then
    bry[k]=nil score+=1
    burst(cc*8+4,rr*8+4,10,7,8,1.2)
   end
  end
 end
end

function upd_player(ix,iy,jp,dp)
 -- hitstop holds everything still and does not consume dash time
 if hitstop>0 then hitstop-=1 return end

 -- during a dash only the dash velocity applies
 if dash_left>0 then
  movex(dash_vx) movey(dash_vy)
  dash_left-=1
  if dash_left==0 then
   dashing=false
   vx=mid(-maxrun,dash_vx,maxrun)
   if dash_vy<=0 then vy=0 else vy=mid(0,dash_vy,maxfall) end
  end
  grounded=boxhit(px,py+1)
  if grounded then can_dash=true end
  touch()
  return
 end

 -- ground or air dash, 8 directions, facing when no direction is held
 if dp and can_dash then
  local dx,dy=ix,iy
  if dx==0 and dy==0 then dx=facing end
  dash_vx,dash_vy=dx*dashspd,dy*dashspd
  if dx~=0 and dy~=0 then
   dash_vx=dash_vx*diagf dash_vy=dash_vy*diagf
  end
  if dx~=0 then facing=dx end
  can_dash=false dashing=true
  hitstop=hitstop_n-1
  dash_left=dash_n
  vx=0 vy=0
  return
 end

 if ix~=0 then
  facing=ix
  vx=appr(vx,ix*maxrun,accel)
 else
  vx=appr(vx,0,decel)
 end
 vy=appr(vy,maxfall,grav)
 if jp and grounded then vy=jumpv end

 if movex(vx) then vx=0 end
 if movey(vy) then
  if vy>0 then grounded=true end
  vy=0
 end
 grounded=boxhit(px,py+1)
 if grounded then can_dash=true end
 touch()
end

-- attract-mode controller: phases advance on grounded state, ledge edges,
-- position and score, never on hard-coded coordinates
function edge_at(d)
 return grounded and not boxhit(px+d,py+1)
end

function demo_input()
 local ix,iy,jp,dp=0,0,false,false
 ptimer+=1
 if phase==1 then          -- introduction: run east to the lip
  ix=1
  if edge_at(1) then jp=true phase=2 ptimer=0 end
 elseif phase==2 then      -- ...and land on the step
  ix=1
  if grounded and ptimer>3 then phase=3 ptimer=0 end
 elseif phase==3 then      -- reversal: run back west to the lip
  ix=-1
  if edge_at(-1) then jp=true phase=4 ptimer=0 end
 elseif phase==4 then      -- dash up-left mid-jump
  ix=-1
  if ptimer>=5 then iy=-1 dp=true phase=5 ptimer=0 end
 elseif phase==5 then      -- ride it onto the ice shelf
  ix=-1
  if grounded and ptimer>3 then phase=6 ptimer=0 end
 elseif phase==6 then      -- east again, up to the high ledge
  ix=1
  if edge_at(1) then jp=true phase=7 ptimer=0 end
 elseif phase==7 then
  ix=1
  if ptimer>=5 then iy=-1 dp=true phase=8 ptimer=0 end
 elseif phase==8 then
  ix=1
  if grounded and ptimer>3 then phase=9 ptimer=0 end
 elseif phase==9 then      -- optional detour: shuffle under the high berry
  ix=-1
  if grounded and px<=35 then jp=true phase=10 ptimer=0 end
 elseif phase==10 then     -- dash straight up through it
  if ptimer>=5 then iy=-1 dp=true phase=11 ptimer=0 end
 elseif phase==11 then     -- back on the ledge with one berry
  if grounded and ptimer>3 and score>=1 then phase=12 ptimer=0 end
 elseif phase==12 then     -- climax: run to the lip of the four-column gap
  ix=1
  if edge_at(1) then jp=true phase=13 ptimer=0 end
 elseif phase==13 then     -- horizontal dash across it
  ix=1
  if ptimer>=6 then dp=true phase=14 ptimer=0 end
 elseif phase==14 then     -- land on the safe shelf
  ix=1
  if grounded and ptimer>3 then phase=15 ptimer=0 end
 elseif phase==15 then     -- approach the elevated flag
  ix=1
  if grounded and ptimer>6 and (px>=96 or vx==0) then jp=true phase=16 ptimer=0 end
 else
  ix=1
 end
 return ix,iy,jp,dp
end

function _init()
 build()
 extcmd("set_filename","opus5.gif")
 extcmd("rec_frames")
 t=0 anim=0 score=0 deaths=0
 win=false wint=0 saved=false
 demo=true gifok=true phase=1 ptimer=0
 sparks={} trail={} parts={}
 for i=1,18 do
  add(parts,{x=rnd(128),y=rnd(128),v=0.12+rnd(0.3),s=rnd(1),
             c=(i%5==0) and 12 or ((i%3==0) and 6 or 7)})
 end
 respawn()
 sparks={}
end

function _update()
 t+=1 anim+=1

 -- physical input is read first: it cancels autoplay and the gif for this run
 local human=false
 for b=0,5 do
  if btn(b) then human=true end
 end
 if demo and human then
  demo=false gifok=false
  win=false wint=0
  respawn()
 end

 local ix,iy,jp,dp=0,0,false,false
 if demo then
  ix,iy,jp,dp=demo_input()
 else
  if btn(0) then ix-=1 end
  if btn(1) then ix+=1 end
  if btn(2) then iy-=1 end
  if btn(3) then iy+=1 end
  jp=btnp(4) dp=btnp(5)
 end

 if win then
  -- physics and hazards frozen, drawing continues
  wint+=1
  if wint==45 and demo and gifok and not saved then
   saved=true
   extcmd("video",4,1)
  end
 elseif dead then
  dtimer+=1
  if dtimer>16 then respawn() end
 else
  upd_player(ix,iy,jp,dp)
  if demo and t>2600 then demo=false gifok=false end
 end

 upd_fx()
end

function upd_fx()
 for p in all(parts) do
  p.y+=p.v
  p.x+=sin(t/120+p.s)*0.25
  if p.y>128 then p.y=-1 p.x=rnd(128) end
 end
 for s in all(sparks) do
  s.x+=s.vx s.y+=s.vy s.vy+=0.09 s.l-=1
  if s.l<=0 then del(sparks,s) end
 end
 for tr in all(trail) do
  tr.l-=1
  if tr.l<=0 then del(trail,tr) end
 end
 if dash_left>0 then add(trail,{x=px,y=py,l=5}) end
end

function _draw()
 cls(0)
 draw_bg()
 for p in all(parts) do pset(p.x,p.y,p.c) end
 draw_terrain()
 draw_ents()
 if not dead then draw_player() end
 for s in all(sparks) do pset(s.x,s.y,s.c) end
 draw_hud()
end

function draw_bg()
 for m in all(bgm) do
  local x0,y0,x1,y1=m[1],m[2],m[3],m[4]
  rectfill(x0,y0,x1,y1,1)
  -- shear one end so the far silhouette reads as a wedge, not a rectangle
  local d=min(10,y1-y0)
  for i=0,d do
   if (x0+y0)%2==0 then
    line(x0+i,y0,x0+i,y0+d-i,0)
   else
    line(x1-i,y0,x1-i,y0+d-i,0)
   end
  end
  for x=x0+d,x1-d do
   if (x*7+y0)%9<2 then pset(x,y0,13) end
  end
 end
 for i in all(bgi) do
  rectfill(i[1],i[2],i[3],i[4],12)
  for y=i[2],i[4] do
   if (y*5)%7<2 then pset(mid(0,i[1]+((i[1]<64) and 4 or -4),127),y,7) end
  end
 end
 for d in all(bgd) do spr(14,d[1],d[2]) end
end

function draw_terrain()
 for r=1,15 do
  for c=0,15 do
   local k,x,y=r*16+c,c*8,r*8
   if sol[k] then
    local open=not sol[k-16]
    local s=8
    if ice[k] then s=10 end
    if open then s+=1 end
    spr(s,x,y)
    local h=(c*5+r*11)%7
    -- navy shading bands deep inside a mass, as in the reference rock
    if not open and r<15 and sol[k+16] and sol[k-1] and sol[k+1]
       and (h==1 or h==4) then
     rectfill(x,y+(h==1 and 0 or 3),x+7,y+(h==1 and 3 or 6),1)
    end
    if open then
     pset(x+h,y-1,7)
     if h<3 then pset(x+h+4,y-1,7) end
     if h==5 then pset(x+2,y-1,12) end
    end
    if r<15 and not sol[k+16] then
     line(x,y+7,x+7,y+7,1)
     if h==2 then line(x+3,y+8,x+3,y+9,12) end
     if h==6 then pset(x+5,y+8,1) end
    end
    if c>0 and not sol[k-1] then line(x,y+1,x,y+7,1) end
    if c<15 and not sol[k+1] then line(x+7,y+1,x+7,y+7,1) end
   elseif spk[k] then
    spr(7,x,y)
   end
  end
 end
end

function draw_ents()
 for r=1,15 do
  for c=0,15 do
   local k,x=r*16+c,c*8
   if bry[k] then
    spr(5+flr(anim/12)%2,x,r*8+sin(anim/60)*1.5)
   elseif gol[k] then
    spr(12+flr(anim/10)%2,x,r*8)
    pset(x+2,r*8+7,7)
   end
  end
 end
end

function draw_player()
 for tr in all(trail) do
  local c=6
  if tr.l>2 then c=7 end
  rectfill(tr.x,tr.y,tr.x+5,tr.y+5,c)
 end
 local s=1
 if not grounded then s=4
 elseif abs(vx)>0.2 then s=2+flr(anim/5)%2 end
 if not can_dash then pal(8,13) end
 spr(s,px-1,py-2,1,1,facing<0)
 pal()
end

function draw_hud()
 -- quiet title zone: display name over the cavern framing, with a shadow
 print("opus 5",3,2,0)
 print("opus 5",2,1,7)
 spr(5,101,-1)
 print("x"..score,111,3,0)
 print("x"..score,110,2,7)
 if win then
  rect(38,54,90,68,1)
  print("clear!",53,58,0)
  print("clear!",52,57,7)
  print("berry "..score.."/2",45,64,6)
 end
end
__gfx__
000000000088888000000000008888800888888000030b0000030b00000000005555555577777777cccccccc7777777700700000007000000000700000000000
00000000088888880088888008888888888888880000330000003300007000705565555577c77777cc7cc1cc777c77770078e0000078e0000077777000000000
00000000088ffff808888888088ffff8088ffff8028888200288882006770677515555557777cc77c777cccc77777c7700788e00007888e00777777700000000
0000000008f1ff18088ffff808f1ff1808f1ff180899888208997882067706775555565557755755c777cc7c7cc77cc7007888e00078888e1777777100000000
0000000000fffff008f1ff1800fffff007fffff70888898208888982667766775555515555555555cc7ccccccccccccc007888e0007888e01111111100000000
000000000033330000fffff000333300003333000288888202888882667667665655555555655155c1ccccccc777cc1c00788e000078e0000000000000000000
00000000003333000033330000333300003003000028882000288820666666665555556555555555cccc77cccc777ccc00700000007000000000000000000000
00000000007007000770007007000770070000700002820000028200566666655155565555155655cc7ccc1cccc7cc7c00700000007000000000000000000000
