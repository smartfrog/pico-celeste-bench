pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
-- celeste-like platformer inspired by celeste classic
-- movement: run 1.5px/f, jump -2.8, gravity 0.25, max fall 3
-- dash: 4px/f for 8 frames, 8-dir, recharges on ground only
-- dash-required obstacle: 5-tile gap (40px) between start and middle platform

-- controls: btn(0) left, btn(1) right, btn(2) aim up, btn(3) aim down, btnp(4) jump, btnp(5) dash

run_spd=1.5
jump_v=-2.8
grav=0.25
max_fall=3
dash_spd=4
dash_dur=8
frz_dur=2

pl={x=16,y=97,vx=0,vy=0,face=1,gnd=false,can_dash=true,dash=0,frz=0}
score=0
win=false
parts={}
trail={}

map_d={
{0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
{0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,0},
{0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1},
{0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
{0,0,0,0,0,0,0,0,0,0,0,0,3,0,0,0},
{0,0,0,0,0,0,0,0,0,0,0,1,1,1,0,0},
{0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
{0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
{0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,0},
{0,0,0,0,0,0,0,0,0,0,3,0,0,0,0,0},
{0,0,0,0,0,0,0,0,0,1,1,1,0,0,0,0},
{0,0,0,0,0,0,0,0,0,0,0,0,0,2,2,0},
{0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,0},
{0,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0},
{0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
{1,1,1,1,1,0,0,0,0,0,0,0,0,1,1,1}
}

function _init()
end

function reset_pl()
  pl.x=16
  pl.y=97
  pl.vx=0
  pl.vy=0
  pl.can_dash=true
  pl.dash=0
  pl.frz=0
end

function solid(x,y)
  local tx=flr(x/8)
  local ty=flr(y/8)
  if tx<0 or tx>15 or ty<0 or ty>15 then return true end
  return map_d[ty+1][tx+1]==1
end

function _update()
  if win then return end

  if pl.frz>0 then
    pl.frz-=1
    return
  end

  if pl.dash>0 then
    pl.dash-=1
    add(trail,{x=pl.x+3,y=pl.y+3,l=10})

    pl.x+=pl.vx
    if solid(pl.x+1,pl.y+2) or solid(pl.x+5,pl.y+2) or solid(pl.x+1,pl.y+5) or solid(pl.x+5,pl.y+5) then
      if pl.vx>0 then
        pl.x=flr((pl.x+6)/8)*8-7
      elseif pl.vx<0 then
        pl.x=flr((pl.x+1)/8)*8+7
      end
      pl.vx=0
      pl.dash=0
    end

    pl.y+=pl.vy
    if solid(pl.x+2,pl.y+1) or solid(pl.x+5,pl.y+1) or solid(pl.x+2,pl.y+6) or solid(pl.x+5,pl.y+6) then
      if pl.vy>0 then
        pl.y=flr((pl.y+7)/8)*8-7
        pl.gnd=true
        pl.can_dash=true
      elseif pl.vy<0 then
        pl.y=flr(pl.y/8)*8+8
      end
      pl.vy=0
      pl.dash=0
    end

    if pl.y>128 then
      reset_pl()
    end
    return
  end

  local mx=0
  if btn(0) then mx=-1 pl.face=-1 end
  if btn(1) then mx=1 pl.face=1 end
  pl.vx=mx*run_spd

  pl.vy+=grav
  if pl.vy>max_fall then pl.vy=max_fall end

  if btnp(4) and pl.gnd then
    pl.vy=jump_v
    pl.gnd=false
  end

  if btnp(5) and pl.can_dash then
    local dx=0
    local dy=0
    if btn(0) then dx=-1 end
    if btn(1) then dx=1 end
    if btn(2) then dy=-1 end
    if btn(3) then dy=1 end
    if dx==0 and dy==0 then dx=pl.face end
    if dx!=0 and dy!=0 then
      dx=dx*0.707
      dy=dy*0.707
    end
    pl.vx=dx*dash_spd
    pl.vy=dy*dash_spd
    pl.dash=dash_dur
    pl.frz=frz_dur
    pl.can_dash=false
  end

  pl.x+=pl.vx
  if pl.vx>0 then
    if solid(pl.x+6,pl.y+2) or solid(pl.x+6,pl.y+5) then
      pl.x=flr((pl.x+6)/8)*8-7
      pl.vx=0
    end
  elseif pl.vx<0 then
    if solid(pl.x+1,pl.y+2) or solid(pl.x+1,pl.y+5) then
      pl.x=flr((pl.x+1)/8)*8+7
      pl.vx=0
    end
  end

  pl.y+=pl.vy
  pl.gnd=false
  if pl.vy>0 then
    if solid(pl.x+2,pl.y+7) or solid(pl.x+5,pl.y+7) then
      pl.y=flr((pl.y+7)/8)*8-7
      pl.vy=0
      pl.gnd=true
      pl.can_dash=true
    end
  elseif pl.vy<0 then
    if solid(pl.x+2,pl.y) or solid(pl.x+5,pl.y) then
      pl.y=flr(pl.y/8)*8+8
      pl.vy=0
    end
  end

  if pl.y>128 then
    reset_pl()
    return
  end

  for ty=flr((pl.y+1)/8),flr((pl.y+6)/8) do
    for tx=flr((pl.x+1)/8),flr((pl.x+6)/8) do
      if tx>=0 and tx<16 and ty>=0 and ty<16 then
        if map_d[ty+1][tx+1]==2 and pl.vy>=0 then
          for i=1,8 do
            add(parts,{x=pl.x+3,y=pl.y+3,vx=rnd(2)-1,vy=rnd(2)-1,l=20,c=8})
          end
          reset_pl()
          return
        end
      end
    end
  end

  for ty=flr(pl.y/8),flr((pl.y+7)/8) do
    for tx=flr(pl.x/8),flr((pl.x+7)/8) do
      if tx>=0 and tx<16 and ty>=0 and ty<16 then
        if map_d[ty+1][tx+1]==3 then
          map_d[ty+1][tx+1]=0
          score+=1
          for i=1,5 do
            add(parts,{x=tx*8+4,y=ty*8+4,vx=rnd(2)-1,vy=rnd(2)-1,l=15,c=10})
          end
        end
      end
    end
  end

  for ty=flr(pl.y/8),flr((pl.y+7)/8) do
    for tx=flr(pl.x/8),flr((pl.x+7)/8) do
      if tx>=0 and tx<16 and ty>=0 and ty<16 then
        if map_d[ty+1][tx+1]==4 then
          win=true
        end
      end
    end
  end

  for i=#trail,1,-1 do
    trail[i].l-=1
    if trail[i].l<=0 then del(trail,trail[i]) end
  end
  for i=#parts,1,-1 do
    parts[i].x+=parts[i].vx
    parts[i].y+=parts[i].vy
    parts[i].l-=1
    if parts[i].l<=0 then del(parts,parts[i]) end
  end

  if rnd(10)<1 then
    add(parts,{x=rnd(128),y=0,vx=rnd(0.5)-0.25,vy=rnd(0.5)+0.3,l=100,c=7})
  end
end

function _draw()
  cls(1)

  for i=1,20 do
    pset((i*37)%128,(i*53)%64,7)
  end

  for y=0,15 do
    for x=0,15 do
      local t=map_d[y+1][x+1]
      if t==1 then
        rectfill(x*8,y*8,x*8+7,y*8+7,13)
        rect(x*8,y*8,x*8+7,y*8+7,1)
      elseif t==2 then
        line(x*8+4,y*8,x*8,y*8+7,6)
        line(x*8+4,y*8,x*8+7,y*8+7,6)
        line(x*8,y*8+7,x*8+7,y*8+7,6)
      elseif t==3 then
        circfill(x*8+4,y*8+4,3,8)
        line(x*8+4,y*8,x*8+4,y*8+2,11)
      elseif t==4 then
        line(x*8+4,y*8,x*8+4,y*8+7,7)
        rectfill(x*8+4,y*8,x*8+7,y*8+3,8)
      end
    end
  end

  for t in all(trail) do
    pset(t.x,t.y,7)
  end

  for pt in all(parts) do
    pset(pt.x,pt.y,pt.c)
  end

  rectfill(pl.x+1,pl.y+3,pl.x+5,pl.y+6,12)
  rectfill(pl.x+2,pl.y+1,pl.x+4,pl.y+3,15)
  local hc=pl.can_dash and 8 or 2
  rectfill(pl.x+1,pl.y,pl.x+5,pl.y+1,hc)
  pset(pl.x+2,pl.y+7,5)
  pset(pl.x+4,pl.y+7,5)

  print("score:"..score,2,2,7)
  if win then
    print("clear!",48,60,10)
  end
end
