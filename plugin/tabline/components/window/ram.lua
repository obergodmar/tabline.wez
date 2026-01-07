local wezterm = require('wezterm')

local last_update_time = 0
local last_result = ''

local function is_windows()
  return wezterm.target_triple:match('windows') ~= nil
end

local function is_linux()
  return wezterm.target_triple:match('linux') ~= nil
end

local function is_darwin()
  return wezterm.target_triple:match('darwin') ~= nil
end

local function format_gb(value_gb)
  return string.format('%.2f GB', value_gb)
end

-- Powershell output parsing: we print two numbers: "<total_kb> <free_kb>"
local function parse_pwsh_total_free_kb(out)
  local total_kb, free_kb = out:match('(%d+)%s+(%d+)')
  return tonumber(total_kb), tonumber(free_kb)
end

-- WMIC output parsing. We'll try to handle both "key=value" and tabular formats.
local function parse_wmic_total_free_kb(out)
  -- Prefer /VALUE format if present:
  local total_kb = out:match('TotalVisibleMemorySize=(%d+)')
  local free_kb = out:match('FreePhysicalMemory=(%d+)')
  if total_kb and free_kb then
    return tonumber(total_kb), tonumber(free_kb)
  end

  -- Fallback for tabular output:
  -- Usually looks like:
  -- TotalVisibleMemorySize  FreePhysicalMemory
  -- 16777216               1234567
  local nums = {}
  for n in out:gmatch('(%d+)') do
    nums[#nums + 1] = tonumber(n)
  end
  -- Heuristic: first is total, second is free
  return nums[1], nums[2]
end

local function get_ram_used_windows(opts)
  local success, result

  if opts.use_pwsh then
    -- Both values are KB on Win32_OperatingSystem
    success, result = wezterm.run_child_process {
      'powershell.exe',
      '-NoProfile',
      '-Command',
      '(Get-CimInstance Win32_OperatingSystem | ForEach-Object { "$($_.TotalVisibleMemorySize) $($_.FreePhysicalMemory)" })',
    }
    if not success or not result then
      return nil
    end

    local total_kb, free_kb = parse_pwsh_total_free_kb(result)
    if not total_kb or not free_kb then
      return nil
    end

    local used_kb = math.max(0, total_kb - free_kb)
    local used_gb = used_kb / 1024 / 1024
    return format_gb(used_gb)
  end

  -- WMIC branch
  -- Force /VALUE output so parsing is stable.
  success, result = wezterm.run_child_process {
    'cmd.exe',
    '/C',
    'wmic OS get TotalVisibleMemorySize,FreePhysicalMemory /Value',
  }
  if not success or not result then
    return nil
  end

  local total_kb, free_kb = parse_wmic_total_free_kb(result)
  if not total_kb or not free_kb then
    return nil
  end

  local used_kb = math.max(0, total_kb - free_kb)
  local used_gb = used_kb / 1024 / 1024
  return format_gb(used_gb)
end

local function get_ram_used_linux()
  local success, result = wezterm.run_child_process {
    'bash',
    '-c',
    'free -m | LC_NUMERIC=C awk \'NR==2{printf "%.2f", $3/1000 }\'',
  }

  if not success or not result then
    return nil
  end

  return format_gb(tonumber(result) or 0)
end

local function get_ram_used_darwin()
  local success, result = wezterm.run_child_process { 'vm_stat' }
  if not success or not result then
    return nil
  end

  local page_size = tonumber(result:match('page size of (%d+) bytes')) or 0
  local anonymous_pages = tonumber(result:match('Anonymous pages:%s+(%d+).')) or 0
  local pages_purgeable = tonumber(result:match('Pages purgeable:%s+(%d+).')) or 0
  local wired_memory = tonumber(result:match('Pages wired down:%s+(%d+).')) or 0
  local compressed_memory = tonumber(result:match('Pages occupied by compressor:%s+(%d+).')) or 0

  local app_memory = math.max(0, anonymous_pages - pages_purgeable)
  local used_bytes = (app_memory + wired_memory + compressed_memory) * page_size
  local used_gb = used_bytes / 1024 / 1024 / 1024

  return format_gb(used_gb)
end

return {
  default_opts = {
    throttle = 3,
    icon = wezterm.nerdfonts.cod_server,
    use_pwsh = false,
  },

  update = function(_, opts)
    local current_time = os.time()
    if current_time - last_update_time < opts.throttle then
      return last_result
    end

    local ram

    if is_windows() then
      ram = get_ram_used_windows(opts)
    elseif is_linux() then
      ram = get_ram_used_linux()
    elseif is_darwin() then
      ram = get_ram_used_darwin()
    end

    if not ram then
      return ''
    end

    last_update_time = current_time
    last_result = ram

    return ram
  end,
}
