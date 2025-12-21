local wezterm = require('wezterm')

local function format_uptime(raw)
  if not raw then
    return ''
  end

  -- remove trailing spaces/newlines
  raw = raw:gsub('%s+$', '')
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
    local success, result

    if wezterm.target_triple:match('windows') then
      success, result = wezterm.run_child_process {
        'powershell.exe',
        '-NoProfile',
        '-Command',
        [[
          $u=(Get-Date)-(Get-CimInstance Win32_OperatingSystem).LastBootUpTime
          "{0}{1}{2}" -f `
            ($u.Days  ? "$($u.Days)d "  : ""), `
            ($u.Hours ? "$($u.Hours)h " : ""), `
            ("$($u.Minutes)m")
        ]],
      }

      if success then
        return result:gsub('%s+$', '')
      end
    else
      success, result = wezterm.run_child_process {
        'uptime',
      }

      if success then
        return format_uptime(result)
      end
    end

    return ''
  end,
}
