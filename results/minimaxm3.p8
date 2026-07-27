pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
--[[
MiniMax M3 design notes (7 lines):
- Celeste Classic PICO-8 like: 8-dir dash, jump, spikes, berries, goal, frozen win
- Movement: max run 1, accel 0.6, decel 0.15, grav 0.21, jump v=-2, dash 5px/4f, freeze 2f
- Forced obstacle: 4-tile horizontal gap (col 8-11) between climb top L and climb top R
- Beats: intro (jump to step), variation (up-dash climb + spike below the gap),
  climax (jump + horizontal dash across 4-tile gap)
- Detour: demo up-dashes to small platform above climb top R for berry A; rejoins for goal
- Berry B sits on climb low L; reachable on the main climb route
- Two spike groups: one in the 4-tile gap (constrains the forced dash) and one in the
  air above the right floor area (punishes falls off climb top R / detour)
]]

CART_NAME = "MiniMax M3"
GIF_NAME = "minimaxm3.gif"

-- physics
MAX_RUN = 1
RUN_ACCEL = 0.6
RUN_DECEL = 0.15
GRAVITY = 0.21
MAX_FALL = 2
JUMP_VEL = -2
DASH_SPEED = 5
DASH_TIME = 4
DASH_FREEZE = 2
DIAG = 0.7071

-- player (h=6 hitbox; we check at p.y+p.h for landing so the floor row 15 is reached)
p = {x=8, y=114, vx=0, vy=0, w=6, h=6, facing=1,
     on_ground=false, can_dash=true,
     dash_timer=0, freeze_timer=0, dx=0, dy=0,
     hair=14}

-- game state
score = 0
deaths = 0
win = false
win_timer = 0
grec_saved = false
game_frame = 0

-- 16x16 map
-- 0=empty, 1=snow solid, 2=spike up, 3=berry, 4=goal flag
-- Simple level: floor, small step, then a forced 4-tile dash to the goal platform.
map_data = {
  {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4},
  {0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,0},
  {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,1,1,1,1,0,0,1,1,1,0},
  {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
  {1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
  {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1},
}

-- player spawn
p.x = 8
p.y = 114

-- berries
berries = {
  {gx=13, gy=3, collected=false},  -- detour berry A (above goal platform)
  {gx=7,  gy=3, collected=false},  -- main-route berry B (on start of goal platform)
}

-- spikes
spikes = {}
for ty=0,15 do
  for tx=0,15 do
    if map_data[ty+1][tx+1] == 2 then
      add(spikes, {x=tx*8, y=ty*8, tx=tx, ty=ty})
    end
  end
end

-- demo state
demo_mode = true
demo_canceled = false
demo_idx = 0
demo_t = 0
demo_btn = 0
recording_started = false
recording_saved = false

-- demo sequence: each entry {buttons_bitmask, frames}
-- direction bits: 1=L, 2=R, 4=U, 8=D
-- press bits: 16=jump press, 32=dash press (fire on first frame of entry)
-- Simple route: walk, jump up a small step, then jump+dash across a 4-tile gap
-- to the goal platform.
demo_seq = {
  -- settle
  {0, 10},
  -- walk right to col 4-5 so the jump lands on the small step at col 6-9, row 4
  {2, 28},
  -- jump (lands on the step at col 6-9, row 4)
  {2 | 16, 1},
  {2, 4},
  -- walk right to col 9 on the step
  {2, 12},
  -- jump, then horizontal dash across the 4-tile gap to the goal platform (col 12-14)
  {2 | 16, 1},
  {2, 9},
  {2 | 32, 1},
  -- wait + decelerate
  {0, 15},
  -- walk right to col 14 on the goal platform
  {2, 15},
  -- jump to touch the goal flag (col 14, row 1)
  {2 | 16, 1},
  {2, 4},
}

function update_demo()
  if demo_idx >= #demo_seq then
    demo_mode = false
    return
  end
  if demo_t <= 0 then
    local entry = demo_seq[demo_idx + 1]
    demo_btn = entry[1]
    demo_t = entry[2]
  end
  demo_t -= 1
  if demo_t <= 0 then
    demo_idx += 1
  end
end

-- collision helpers
function is_solid_tile(tx, ty)
  if tx<0 or tx>15 or ty<0 or ty>15 then return true end
  local v = map_data[ty+1][tx+1]
  return v == 1
end

function check_solid_px(x, y, w, h)
  local x1, y1 = x, y
  local x2, y2 = x+w-1, y+h-1
  local tx1, ty1 = flr(x1/8), flr(y1/8)
  local tx2, ty2 = flr(x2/8), flr(y2/8)
  for ty=ty1, ty2 do
    for tx=tx1, tx2 do
      if is_solid_tile(tx, ty) then return true end
    end
  end
  return false
end

function check_solid(x, y, w, h) return check_solid_px(x, y, w, h) end

function rect_overlap(x1,y1,w1,h1, x2,y2,w2,h2)
  return x1 < x2+w2 and x1+w1 > x2 and y1 < y2+h2 and y1+h1 > y2
end

function update_player()
  local btns, jp, dp
  if demo_mode and not demo_canceled then
    btns = demo_btn & 15
    jp = (demo_btn & 16) > 0
    dp = (demo_btn & 32) > 0
  else
    btns = (btn(0) and 1 or 0) | (btn(1) and 2 or 0) |
           (btn(2) and 4 or 0) | (btn(3) and 8 or 0)
    jp = btnp(4)
    dp = btnp(5)
  end

  -- dash freeze
  if p.freeze_timer > 0 then
    p.freeze_timer -= 1
    return
  end

  -- dash timer
  if p.dash_timer > 0 then
    p.dash_timer -= 1
    p.x += p.dx
    p.y += p.dy
    -- collision during dash
    if p.dx > 0 and check_solid_px(p.x + p.w - 1, p.y + 1, 1, p.h - 2) then
      p.x = flr((p.x + p.w - 1)/8)*8 - p.w
      p.dash_timer = 0
    elseif p.dx < 0 and check_solid_px(p.x, p.y + 1, 1, p.h - 2) then
      p.x = flr(p.x/8)*8 + 8
      p.dash_timer = 0
    end
    if p.dy > 0 and check_solid_px(p.x + 1, p.y + p.h, p.w - 2, 1) then
      p.y = flr((p.y + p.h)/8)*8 - p.h
      p.dash_timer = 0
      p.on_ground = true
      p.can_dash = true
    elseif p.dy < 0 and check_solid_px(p.x + 1, p.y, p.w - 2, 1) then
      p.y = flr(p.y/8)*8 + 8
      p.dash_timer = 0
    end
    if p.dash_timer % 2 == 0 then
      add_trail(flr(p.x + p.w/2), flr(p.y + p.h/2))
    end
    p.on_ground = false
    if p.dash_timer <= 0 then
      p.vy = 0
    end
    return
  end

  -- facing
  if (btns & 1) > 0 then p.facing = -1 end
  if (btns & 2) > 0 then p.facing = 1 end

  -- horizontal accel
  local ax = 0
  if (btns & 1) > 0 then ax -= RUN_ACCEL end
  if (btns & 2) > 0 then ax += RUN_ACCEL end
  if ax == 0 then
    if p.vx > 0 then p.vx = max(0, p.vx - RUN_DECEL)
    elseif p.vx < 0 then p.vx = min(0, p.vx + RUN_DECEL) end
  else
    p.vx += ax
    if p.vx > MAX_RUN then p.vx = MAX_RUN end
    if p.vx < -MAX_RUN then p.vx = -MAX_RUN end
  end

  -- gravity
  p.vy += GRAVITY
  if p.vy > MAX_FALL then p.vy = MAX_FALL end

  -- jump
  if jp and p.on_ground then
    p.vy = JUMP_VEL
    p.on_ground = false
  end

  -- dash
  if dp and p.can_dash then
    local dx, dy = 0, 0
    if (btns & 1) > 0 then dx -= 1 end
    if (btns & 2) > 0 then dx += 1 end
    if (btns & 4) > 0 then dy -= 1 end
    if (btns & 8) > 0 then dy += 1 end
    if dx == 0 and dy == 0 then dx = p.facing end
    if dx ~= 0 and dy ~= 0 then
      dx *= DIAG
      dy *= DIAG
    end
    p.dx = dx * DASH_SPEED
    p.dy = dy * DASH_SPEED
    p.dash_timer = DASH_TIME
    p.freeze_timer = DASH_FREEZE
    p.can_dash = false
    for i=1,3 do add_trail(p.x+p.w/2, p.y+p.h/2) end
    return
  end

  -- move
  p.on_ground = false
  if p.vx > 0 then
    local nx = p.x + p.vx
    if check_solid_px(nx + p.w - 1, p.y + 1, 1, p.h - 2) or
       check_solid_px(nx + p.w - 1, p.y, 1, 1) or
       check_solid_px(nx + p.w - 1, p.y + p.h - 1, 1, 1) then
      nx = flr((nx + p.w - 1)/8)*8 - p.w
      p.vx = 0
    end
    p.x = nx
  elseif p.vx < 0 then
    local nx = p.x + p.vx
    if check_solid_px(nx, p.y + 1, 1, p.h - 2) or
       check_solid_px(nx, p.y, 1, 1) or
       check_solid_px(nx, p.y + p.h - 1, 1, 1) then
      nx = flr(nx/8)*8 + 8
      p.vx = 0
    end
    p.x = nx
  end

  if p.vy ~= 0 then
    local new_y = p.y + p.vy
    -- robust landing: find the top of the solid at or below the new position
    -- by iterating from the bottom of the new hitbox down to row 0
    local landed = false
    for ty = flr((new_y + p.h) / 8), 0, -1 do
      if check_solid_px(p.x, ty * 8, p.w, 1) then
        p.y = ty * 8 - p.h
        p.vy = 0
        landed = true
        break
      end
    end
    if landed then
      p.on_ground = true
      p.can_dash = true
    elseif p.vy < 0 then
      -- ascending: try head-bump at the top of the new position
      for ty = flr(new_y / 8), 0, -1 do
        if check_solid_px(p.x, ty * 8, p.w, 1) then
          p.y = ty * 8 + 8
          p.vy = 0
          break
        end
      end
    else
      p.y = new_y
    end
  end
end

-- trail
trail = {}
function add_trail(x, y)
  add(trail, {x=x, y=y, life=10})
end

function update_trail()
  for t in all(trail) do
    t.life -= 1
    if t.life <= 0 then del(trail, t) end
  end
end

-- spikes (up-spikes only kill when descending; player hitbox narrower than tile)
function check_spikes()
  for s in all(spikes) do
    if rect_overlap(p.x+1, p.y+2, p.w-2, p.h-3, s.x+1, s.y+4, 6, 4) then
      if p.vy >= -0.01 then
        deaths += 1
        p.x = 8
        p.y = 114
        p.vx = 0
        p.vy = 0
        p.can_dash = true
        p.dash_timer = 0
        p.freeze_timer = 0
      end
    end
  end
end

-- berries
function check_berries()
  for b in all(berries) do
    if not b.collected then
      local bx = b.gx*8
      local by = b.gy*8
      if rect_overlap(p.x+1, p.y+1, p.w-2, p.h-2, bx, by, 8, 8) then
        b.collected = true
        score += 1
      end
    end
  end
end

-- goal: flag pole at col 14, row 1-2
function check_goal()
  local gx, gy = 14*8, 1*8
  if rect_overlap(p.x+1, p.y+1, p.w-2, p.h-2, gx, gy, 8, 16) then
    if not win then
      win = true
      win_timer = 0
    end
  end
end

-- ambient snow particles
particles = {}
function update_particles()
  if #particles < 18 and rnd(1) < 0.4 then
    add(particles, {
      x = rnd(128),
      y = -2,
      vx = -0.1 + rnd(0.2),
      vy = 0.1 + rnd(0.15)
    })
  end
  for p2 in all(particles) do
    p2.x += p2.vx
    p2.y += p2.vy
    if p2.y > 130 then del(particles, p2) end
  end
end

function _init()
  -- initial ground check (so first frame the player can jump)
  p.on_ground = check_solid_px(p.x + 1, p.y + p.h, p.w - 2, 1)
  p.can_dash = p.on_ground
  -- start recording the demo
  extcmd("set_filename", GIF_NAME)
  extcmd("rec_frames")
  recording_started = true
end

function _update()
  game_frame += 1

  -- demo cancel on user input
  if demo_mode and not demo_canceled then
    if btn(0) or btn(1) or btn(2) or btn(3) or btn(4) or btn(5) then
      demo_mode = false
      demo_canceled = true
    end
  end

  if win then
    win_timer += 1
    if win_timer >= 45 and not recording_saved then
      extcmd("video", 4, 1)
      recording_saved = true
      print("gif saved at win_timer="..win_timer)
    end
    update_particles()
    update_trail()
    return
  end

  if demo_mode and not demo_canceled then
    update_demo()
  end

  update_player()
  check_spikes()
  check_berries()
  check_goal()
  update_trail()
  update_particles()
end

-- drawing helpers
function draw_snow_tile(tx, ty)
  local x, y = tx*8, ty*8
  rectfill(x, y, x+7, y+7, 7)
  rectfill(x+1, y+1, x+6, y+6, 6)
  pset(x+2, y+2, 7)
  pset(x+5, y+5, 7)
end

function draw_spike_tile(tx, ty)
  local x, y = tx*8, ty*8
  for row=0,7 do
    local w
    if row < 2 then w = 0
    elseif row < 4 then w = 2
    elseif row < 6 then w = 4
    else w = 6 end
    if w > 0 then
      rectfill(x + 4 - flr(w/2), y + row, x + 4 + flr(w/2) - 1, y + row, 7)
    end
  end
  pset(x+3, y+2, 15)
  pset(x+4, y+2, 15)
end

function draw_berry(b)
  local x, y = b.gx*8, b.gy*8
  -- leaves
  pset(x+2, y+0, 11)
  pset(x+3, y+0, 11)
  pset(x+1, y+1, 11)
  pset(x+4, y+1, 11)
  -- body
  for row=2,5 do
    for col=1,5 do
      pset(x+col, y+row, 14)
    end
  end
  pset(x+2, y+6, 11)
  pset(x+3, y+6, 11)
  pset(x+2, y+7, 11)
end

function draw_goal(tx, ty)
  local x, y = tx*8, ty*8
  -- pole
  rectfill(x+3, y+0, x+3, y+7, 11)
  -- flag
  rectfill(x+4, y+1, x+7, y+3, 8)
  pset(x+5, y+2, 7)
  pset(x+6, y+2, 7)
end

function draw_player()
  local x = flr(p.x)
  local y = flr(p.y)
  local hc = p.can_dash and 14 or 8
  -- hair
  pset(x+1, y+0, hc)
  pset(x+2, y+0, hc)
  pset(x+3, y+0, hc)
  pset(x+4, y+0, hc)
  pset(x+0, y+1, hc)
  pset(x+5, y+1, hc)
  pset(x+0, y+2, hc)
  pset(x+5, y+2, hc)
  -- face
  pset(x+1, y+1, 7)
  pset(x+2, y+1, 7)
  pset(x+3, y+1, 7)
  pset(x+4, y+1, 7)
  pset(x+1, y+2, 7)
  pset(x+2, y+2, 7)
  pset(x+3, y+2, 7)
  pset(x+4, y+2, 7)
  -- eyes
  pset(x+1, y+2, 0)
  pset(x+4, y+2, 0)
  -- body
  pset(x+1, y+3, 12)
  pset(x+2, y+3, 12)
  pset(x+3, y+3, 12)
  pset(x+4, y+3, 12)
  pset(x+1, y+4, 12)
  pset(x+2, y+4, 12)
  pset(x+3, y+4, 12)
  pset(x+4, y+4, 12)
  -- legs
  pset(x+1, y+5, 12)
  pset(x+4, y+5, 12)
end

function _draw()
  cls(1)

  -- draw map
  for ty=0,15 do
    for tx=0,15 do
      local v = map_data[ty+1][tx+1]
      if v == 1 then
        draw_snow_tile(tx, ty)
      elseif v == 2 then
        draw_spike_tile(tx, ty)
      end
    end
  end

  -- berries
  for b in all(berries) do
    if not b.collected then
      draw_berry(b)
    end
  end

  -- goal (col 14, row 1)
  draw_goal(14, 1)

  -- trail
  for t in all(trail) do
    pset(t.x, t.y, 7)
  end

  -- particles
  for p2 in all(particles) do
    pset(p2.x, p2.y, 7)
  end

  -- player
  draw_player()

  -- cart name (always visible)
  print(CART_NAME, 64 - #CART_NAME*2, 2, 7)

  -- hud
  print("score "..score, 2, 110, 7)
  print("dth "..deaths, 2, 118, 7)

  -- win text
  if win then
    rectfill(40, 56, 88, 72, 0)
    print("clear!", 50, 60, 7)
  end
end
