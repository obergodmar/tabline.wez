local wezterm = require('wezterm')

local last_update_time = 0
local last_result = ''
local last_linux_snapshot = nil

local function is_windows()
  return wezterm.target_triple:match('windows') ~= nil
end

local function is_linux()
  return wezterm.target_triple:match('linux') ~= nil
end

local function is_darwin()
  return wezterm.target_triple:match('darwin') ~= nil
end

local function trim(value)
  if not value then
    return nil
  end

  return value:gsub('^%s*(.-)%s*$', '%1')
end

local function format_cpu(value)
  return string.format('%.2f%%', value)
end

local function read_linux_cpu_snapshot()
  local file = io.open('/proc/stat', 'r')
  if not file then
    return nil
  end

  local line = file:read('*l')
  file:close()

  if not line then
    return nil
  end

  local user, nice, system, idle, iowait, irq, softirq, steal =
    line:match('^cpu%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s*(%d*)%s*(%d*)%s*(%d*)%s*(%d*)')

  if not user or not nice or not system or not idle then
    return nil
  end

  user = tonumber(user) or 0
  nice = tonumber(nice) or 0
  system = tonumber(system) or 0
  idle = tonumber(idle) or 0
  iowait = tonumber(iowait) or 0
  irq = tonumber(irq) or 0
  softirq = tonumber(softirq) or 0
  steal = tonumber(steal) or 0

  return {
    busy = user + nice + system + irq + softirq + steal,
    total = user + nice + system + idle + iowait + irq + softirq + steal,
  }
end

local function get_cpu_windows(opts)
  local success, result

  if opts.use_pwsh then
    success, result = wezterm.run_child_process {
      'powershell.exe',
      '-Command',
      'Get-CimInstance Win32_Processor | Select-Object -ExpandProperty LoadPercentage',
    }
    if not success or not result then
      return nil
    end

    return tonumber(result:match('%d+%.?%d*') or '0')
  end

  success, result = wezterm.run_child_process {
    'cmd.exe',
    '/C',
    'wmic cpu get loadpercentage',
  }
  if not success or not result then
    return nil
  end

  return tonumber(result:match('%d+'))
end

local function get_cpu_linux()
  local snapshot = read_linux_cpu_snapshot()
  if not snapshot then
    return nil
  end

  if not last_linux_snapshot then
    last_linux_snapshot = snapshot
    return nil
  end

  local busy_delta = snapshot.busy - last_linux_snapshot.busy
  local total_delta = snapshot.total - last_linux_snapshot.total

  last_linux_snapshot = snapshot

  if busy_delta < 0 or total_delta <= 0 then
    return nil
  end

  return busy_delta * 100 / total_delta
end

local function get_cpu_darwin()
  local success, result = wezterm.run_child_process {
    'bash',
    '-c',
    'ps -A -o %cpu | LC_NUMERIC=C awk \'{s+=$1} END {print s ""}\'',
  }
  if not success or not result then
    return nil
  end

  local cpu = tonumber(trim(result))
  if not cpu then
    return nil
  end

  success, result = wezterm.run_child_process {
    'sysctl',
    '-n',
    'hw.ncpu',
  }
  if not success or not result then
    return cpu
  end

  local num_cores = tonumber(trim(result))
  if not num_cores or num_cores <= 0 then
    return cpu
  end

  return cpu / num_cores
end

return {
  default_opts = {
    throttle = 3,
    icon = wezterm.nerdfonts.oct_cpu,
    use_pwsh = false,
  },

  update = function(_, opts)
    local current_time = os.time()
    if current_time - last_update_time < opts.throttle then
      return last_result
    end

    local cpu

    if is_windows() then
      cpu = get_cpu_windows(opts)
    elseif is_linux() then
      cpu = get_cpu_linux()
    elseif is_darwin() then
      cpu = get_cpu_darwin()
    end

    if cpu == nil then
      return last_result
    end

    last_result = format_cpu(cpu)
    last_update_time = current_time

    return last_result
  end,
}
