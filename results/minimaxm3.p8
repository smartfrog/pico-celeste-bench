pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
--[[
  Celeste Classic traits: 8-dir dash (3px/5f + 3f freeze), coyote-less
  platforming, ground-restored dash, dash trail, spike kill + respawn.
  Constants: acc 0.2, dec 0.25, max_x 1, grav 0.21, max_y 2,
  jmp -2 for 6 frames, dash 3px/f for 5f + 3f freeze, hitbox 5x5.
  Dash-forcing obstacle: 4-tile (32px) ground gap, beyond the
  ~31px run-jump but inside the ~46px jump+dash reach.
]]

GRAV = 0.21
MAX_X = 1
ACC = 0.2
DEC = 0.25
MAX_Y = 2
JMP_V = -2
JMP_DUR = 6
DASH_SPD = 3
DASH_TIME = 5
DASH_FRZ = 3
HBW = 5
HBH = 5

LVL = {
  {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,0},
  {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,0},
  {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0,0,0,1,1,0,0,0,0},
  {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0,0,0,1,1,0,0,0,0},
  {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
  {1,1,1,1,1,0,0,0,0,1,1,1,1,1,1,1}
}

SPIKES = {
  {13, 14},
  {14, 14}
}

GOAL_T = {13, 1}

BERRIES = {
  {84, 80},
  {104, 32}
}

P = nil
WIN = false
SCORE = 0
FR = 0
TRAIL = {}
PARTS = {}
BG_PARTS = {}

function _init()
  srand(1)
  reset()
end

function reset()
  P = {
    x = 8, y = 115,
    vx = 0, vy = 0,
    can_dash = true,
    dashing = 0,
    frozen = 0,
    jmp_count = 0,
    facing = 1,
    on_ground = false,
    dead = false,
    berries = {false, false}
  }
  WIN = false
  SCORE = 0
  FR = 0
  TRAIL = {}
  PARTS = {}
  BG_PARTS = {}
  for i = 1, 40 do
    add(PARTS, {
      x = rnd(128),
      y = rnd(128),
      vy = 0.04 + rnd(0.08),
      vx = -0.03 - rnd(0.04),
      c = 7
    })
  end
  for i = 1, 8 do
    add(BG_PARTS, {
      x = rnd(128),
      y = rnd(80),
      s = 1 + flr(rnd(2)),
      c = 1
    })
  end
end

function solid_at(tx, ty)
  if tx < 0 or tx > 15 or ty < 0 or ty > 15 then return false end
  return LVL[ty + 1][tx + 1] == 1
end

function pixel_solid(px, py)
  local x0 = flr(px / 8)
  local y0 = flr(py / 8)
  local x1 = flr((px + HBW - 1) / 8)
  local y1 = flr((py + HBH - 1) / 8)
  if solid_at(x0, y0) then return true end
  if solid_at(x1, y0) then return true end
  if solid_at(x0, y1) then return true end
  if solid_at(x1, y1) then return true end
  if x0 ~= x1 and y0 ~= y1 then
    if solid_at(x1, y0) then return true end
    if solid_at(x0, y1) then return true end
  end
  return false
end

function _update()
  if WIN then
    update_parts()
    FR += 1
    return
  end
  if P.dead then
    reset()
    return
  end
  FR += 1
  update_player()
  update_parts()
  check_spikes()
  check_berries()
  check_goal()
end

function update_player()
  if P.frozen > 0 then
    P.frozen -= 1
    return
  end

  if btn(0) then P.facing = -1 end
  if btn(1) then P.facing = 1 end

  if P.dashing > 0 then
    P.dashing -= 1
  end

  if P.dashing > 0 then
    -- dash in progress: no input, no gravity
  else
    local target = 0
    if btn(0) then target = -MAX_X end
    if btn(1) then target = MAX_X end
    if P.vx < target then
      P.vx = min(target, P.vx + ACC)
    elseif P.vx > target then
      P.vx = max(target, P.vx - DEC)
    end
    P.vy = min(MAX_Y, P.vy + GRAV)
  end

  if btnp(4) and P.on_ground then
    P.vy = JMP_V
    P.jmp_count = JMP_DUR
    P.can_dash = true
  end
  if P.jmp_count > 0 and btn(4) then
    P.vy = JMP_V
    P.jmp_count -= 1
  else
    P.jmp_count = 0
  end

  if btnp(5) and P.can_dash then
    do_dash()
  end

  move_axis("x", P.vx)
  P.on_ground = false
  move_axis("y", P.vy)
  if check_ground() then
    P.on_ground = true
    P.can_dash = true
  end

  if P.dashing > 0 then
    add(TRAIL, {x = P.x + 2, y = P.y + 2, life = 4})
  end

  for t in all(TRAIL) do
    t.life -= 1
    if t.life <= 0 then del(TRAIL, t) end
  end
end

function do_dash()
  local dx, dy = 0, 0
  if btn(0) then dx -= 1 end
  if btn(1) then dx += 1 end
  if btn(2) then dy -= 1 end
  if btn(3) then dy += 1 end
  if dx == 0 and dy == 0 then
    dx = P.facing
  end
  local len = sqrt(dx * dx + dy * dy)
  if len > 0 then
    dx = dx * DASH_SPD / len
    dy = dy * DASH_SPD / len
  end
  P.vx = dx
  P.vy = dy
  P.dashing = DASH_TIME
  P.frozen = DASH_FRZ
  P.can_dash = false
end

function pixel_solid_at(px, py)
  if px < 0 or px > 127 or py < 0 or py > 127 then return false end
  return solid_at(flr(px / 8), flr(py / 8))
end

function check_ground()
  for dx = 0, HBW - 1 do
    if pixel_solid_at(P.x + dx, P.y + HBH) then
      return true
    end
  end
  return false
end

function move_axis(axis, v)
  if v == 0 then return end
  local steps = max(1, ceil(abs(v)))
  local s = v / steps
  for i = 1, steps do
    if axis == "x" then
      local nx = P.x + s
      if pixel_solid(nx, P.y) then
        P.vx = 0
        return
      else
        P.x = nx
      end
    else
      local ny = P.y + s
      if pixel_solid(P.x, ny) then
        if v > 0 then
          local ty = flr((ny + HBH - 1) / 8)
          P.y = ty * 8 - HBH
        end
        P.vy = 0
        return
      else
        P.y = ny
      end
    end
  end
end

function check_spikes()
  for s in all(SPIKES) do
    local sx = s[1] * 8
    local sy = s[2] * 8
    if P.x < sx + 8 and P.x + HBW > sx + 1 and
       P.y < sy + 8 and P.y + HBH > sy + 3 then
      P.dead = true
      return
    end
  end
end

function check_berries()
  for i = 1, #BERRIES do
    if not P.berries[i] then
      local b = BERRIES[i]
      if P.x < b[1] + 8 and P.x + HBW > b[1] and
         P.y < b[2] + 8 and P.y + HBH > b[2] then
        P.berries[i] = true
        SCORE += 1
      end
    end
  end
end

function check_goal()
  local gx = GOAL_T[1] * 8
  local gy = GOAL_T[2] * 8
  if P.x < gx + 8 and P.x + HBW > gx and
     P.y < gy + 10 and P.y + HBH > gy then
    WIN = true
  end
end

function update_parts()
  for p in all(PARTS) do
    p.y += p.vy
    p.x += p.vx
    if p.y > 130 then
      p.y = -2
      p.x = rnd(128)
    end
    if p.x < -2 then p.x = 130 end
  end
  for p in all(BG_PARTS) do
    p.x -= 0.02
    if p.x < -4 then
      p.x = 130
      p.y = rnd(80)
    end
  end
end

function _draw()
  cls(1)
  draw_bg_parts()
  draw_terrain()
  draw_goal()
  draw_berries()
  draw_trail()
  draw_parts()
  draw_player()
  draw_ui()
  if WIN then draw_clear() end
end

function draw_bg_parts()
  for p in all(BG_PARTS) do
    rectfill(p.x, p.y, p.x + p.s, p.y + p.s, 1)
  end
end

function draw_terrain()
  for ty = 0, 15 do
    for tx = 0, 15 do
      if LVL[ty + 1][tx + 1] == 1 then
        local px = tx * 8
        local py = ty * 8
        local top = (ty == 0) or (LVL[ty][tx + 1] ~= 1)
        if top then
          rectfill(px, py, px + 7, py + 1, 11)
          rectfill(px, py + 1, px + 7, py + 2, 3)
          rectfill(px, py + 2, px + 7, py + 7, 5)
          pset(px, py, 0)
          pset(px + 7, py, 0)
          pset(px + 1, py + 1, 7)
          pset(px + 2, py + 1, 7)
          pset(px + 5, py + 1, 7)
        else
          rectfill(px, py, px + 7, py + 7, 5)
          pset(px, py, 6)
          pset(px + 7, py, 6)
        end
        if py > 120 then
          pset(px + 1, py + 6, 1)
          pset(px + 4, py + 6, 1)
        end
      end
    end
  end

  for s in all(SPIKES) do
    local sx = s[1] * 8
    local sy = s[2] * 8
    for i = 0, 2 do
      local x0 = sx + 1 + i * 3
      line(x0, sy + 8, x0 + 1, sy + 1, 8)
      line(x0 + 1, sy + 1, x0 + 2, sy + 8, 8)
      pset(x0 + 1, sy + 1, 9)
      pset(x0 + 1, sy + 2, 9)
    end
  end
end

function draw_goal()
  local gx = GOAL_T[1] * 8
  local gy = GOAL_T[2] * 8
  rectfill(gx + 3, gy + 1, gx + 4, gy + 8, 7)
  pset(gx + 3, gy + 1, 0)
  rectfill(gx + 4, gy + 1, gx + 7, gy + 5, 14)
  rectfill(gx + 4, gy + 4, gx + 7, gy + 5, 11)
  pset(gx + 4, gy + 1, 0)
  pset(gx + 5, gy + 5, 8)
  pset(gx + 6, gy + 5, 8)
end

function draw_berries()
  for i = 1, #BERRIES do
    if not P.berries[i] then
      local b = BERRIES[i]
      pset(b[1] + 3, b[2] + 0, 11)
      pset(b[1] + 4, b[2] + 0, 11)
      pset(b[1] + 2, b[2] + 1, 11)
      pset(b[1] + 5, b[2] + 1, 11)
      rectfill(b[1] + 2, b[2] + 2, b[1] + 5, b[2] + 7, 8)
      pset(b[1] + 1, b[2] + 3, 8)
      pset(b[1] + 6, b[2] + 3, 8)
      pset(b[1] + 1, b[2] + 4, 8)
      pset(b[1] + 6, b[2] + 4, 8)
      pset(b[1] + 1, b[2] + 5, 8)
      pset(b[1] + 6, b[2] + 5, 8)
      pset(b[1] + 2, b[2] + 4, 7)
      pset(b[1] + 5, b[2] + 4, 7)
      pset(b[1] + 3, b[2] + 6, 7)
      pset(b[1] + 4, b[2] + 6, 7)
    end
  end
end

function draw_trail()
  for t in all(TRAIL) do
    local c = 7
    if t.life < 3 then c = 6 end
    pset(t.x - 1, t.y, c)
    pset(t.x + 2, t.y, c)
    pset(t.x, t.y - 1, c)
    pset(t.x + 1, t.y - 1, c)
    pset(t.x, t.y + 2, c)
    pset(t.x + 1, t.y + 2, c)
    pset(t.x, t.y, c)
    pset(t.x + 1, t.y + 1, c)
  end
end

function draw_parts()
  for p in all(PARTS) do
    pset(p.x, p.y, p.c)
    pset(p.x + 1, p.y, p.c)
  end
end

function draw_player()
  local px = P.x - 1
  local py = P.y - 1
  local hair = 8
  if P.can_dash and not P.dashing then hair = 11 end
  if P.dashing > 0 then hair = 7 end
  pset(px, py, hair)
  pset(px + 1, py, hair)
  pset(px + 4, py, hair)
  pset(px + 5, py, hair)
  pset(px, py + 1, hair)
  pset(px + 5, py + 1, hair)
  pset(px, py + 2, hair)
  pset(px + 5, py + 2, hair)
  rectfill(px + 1, py + 1, px + 4, py + 2, 15)
  if P.facing > 0 then
    pset(px + 3, py + 2, 0)
  else
    pset(px + 2, py + 2, 0)
  end
  rectfill(px, py + 3, px + 5, py + 3, 12)
  rectfill(px, py + 4, px + 5, py + 4, 12)
  rectfill(px + 1, py + 5, px + 4, py + 5, 5)
  rectfill(px, py + 5, px + 5, py + 5, 5)
  pset(px, py + 4, 12)
  pset(px + 5, py + 4, 12)
  pset(px + 1, py + 6, 5)
  pset(px + 2, py + 6, 5)
  pset(px + 3, py + 6, 5)
  pset(px + 4, py + 6, 5)
end

function draw_ui()
  print("score:" .. SCORE, 2, 2, 7)
  if P.can_dash then
    print("dash:ok", 92, 2, 11)
  else
    print("dash:--", 92, 2, 5)
  end
end

function draw_clear()
  rectfill(28, 50, 100, 78, 0)
  rect(28, 50, 100, 78, 7)
  print("clear!", 56, 56, 7)
  print("score " .. SCORE, 48, 64, 14)
end
