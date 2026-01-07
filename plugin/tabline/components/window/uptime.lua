local wezterm = require('wezterm')

-- platform: "unix" | "windows"
local function format_uptime(raw, platform)
  if not raw then
    return ''
  end

  -- normalize newlines & trim
  raw = raw:gsub('\r\n', '\n'):gsub('%s+$', '')

  if platform == 'windows' then
    local function pick(key)
      local v = raw:match('^%s*' .. key .. '%s*:%s*(%d+)%s*$')
      if v then
        return tonumber(v)
      end
      v = raw:match('\n%s*' .. key .. '%s*:%s*(%d+)')
      if v then
        return tonumber(v)
      end
      return 0
    end

    local days = pick('Days')
    local hours = pick('Hours')
    local minutes = pick('Minutes')
    local seconds = pick('Seconds')

    local parts = {}

    if days > 0 then
      parts[#parts + 1] = days .. 'd'
    end
    if hours > 0 then
      parts[#parts + 1] = hours .. 'h'
    end
    if minutes > 0 then
      parts[#parts + 1] = minutes .. 'm'
    end

    -- секунды показываем только если нет минут/часов/дней
    if #parts == 0 and seconds > 0 then
      parts[#parts + 1] = seconds .. 's'
    end

    return table.concat(parts, ' ')
  end

  -- extract uptime part
  raw = raw:match('up%s+(.*)')
  if not raw then
    return ''
  end

  raw = raw:gsub(',%s*%d+%s+users?.*', '')
  raw = raw:gsub('(%d+)%s+days?,?', '%1d ')

  raw = raw:gsub('(%d+)%s+hours?,?', '%1h ')
  raw = raw:gsub('(%d+)%s+minutes?,?', '%1m ')
  raw = raw:gsub('(%d+)%s+seconds?,?', '%1s ')

  raw = raw:gsub('(%d+):(%d+)', '%1h %2m')

  raw = raw:gsub('%s+', ' '):gsub('%s+$', '')

  return raw
end

return {
  default_opts = {
    icon = wezterm.nerdfonts.md_timer_sand,
  },

  update = function(_)
    local platform = wezterm.target_triple:match('windows') and 'windows' or 'unix'
    local success, result

    if platform == 'windows' then
      success, result = wezterm.run_child_process {
        'powershell.exe',
        '-NoProfile',
        '-Command',
        '(Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime',
      }
    else
      success, result = wezterm.run_child_process {
        'uptime',
      }
    end

    if success then
      return format_uptime(result, platform)
    end

    return ''
  end,
}
