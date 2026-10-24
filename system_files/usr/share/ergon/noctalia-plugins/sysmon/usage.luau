local YELLOW = "#f2c94c"

local function gib(mb)
  return string.format("%.1f GiB", mb / 1024)
end

function update()
  noctalia.setUpdateInterval(2000) -- the system monitor samples CPU and RAM every 2 s

  local isRam = noctalia.getConfig("stat") == "ram"
  barWidget.setGlyph(isRam and "memory" or "cpu-usage")

  local stats = noctalia.systemStats()
  if stats == nil then
    barWidget.setText("--")
    barWidget.setTooltip("System monitor is disabled")
    return
  end

  local pct = isRam and stats.ram.usagePercent or stats.cpu.usagePercent
  barWidget.setText(string.format("%d%%", math.floor(pct + 0.5)))

  local color = "on_surface"
  if pct >= noctalia.getConfig("critical_percent") then
    color = "error"
  elseif pct > noctalia.getConfig("warn_percent") then
    color = YELLOW
  end
  barWidget.setColor(color)
  barWidget.setGlyphColor(color)

  if isRam then
    barWidget.setTooltip({
      { "RAM", gib(stats.ram.usedMb) .. " / " .. gib(stats.ram.totalMb) },
      { "Swap", gib(stats.swap.usedMb) .. " / " .. gib(stats.swap.totalMb) },
    })
  else
    local rows = { { "CPU", string.format("%.0f%%", pct) } }
    if stats.cpu.tempC ~= nil then
      table.insert(rows, { "Temperature", string.format("%.0f°C", stats.cpu.tempC) })
    end
    if stats.loadAvg ~= nil then
      table.insert(rows, { "Load", string.format("%.2f %.2f %.2f", stats.loadAvg[1], stats.loadAvg[2], stats.loadAvg[3]) })
    end
    barWidget.setTooltip(rows)
  end
end
