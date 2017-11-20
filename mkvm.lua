local args = {...}
local MKVIM_DEBUG = false

local function debug(...)
  if MKVIM_DEBUG then
    for i,v in pairs({...}) do
      print(v)
      local fi = fs.open("debug.log", "a")
      fi.write(v.."\n")
      fi.close()
    end
  end
end

local function resolve(path)
  local resolved = "/"..shell.resolve(path)
  debug(path.." resolved to "..resolved)
  return resolved
end

local default_mounts = {"rw:/:/vms/%NAME%","r:/rom:/rom"}
local default_bios_path = "/bios.lua"

local help  = "Usage: "..shell.getRunningProgram().." <name> [flags]\nFlags:\n"

local flags = {
  ["--vfs-mount"] = {
    help = [[The virtual file system mounts. Default: ]]..table.concat(default_mounts, ", "),
    alias = {"-vfs", "-m", "-mount"},
    count = 1,
    multiple = true,
    default = default_mounts
  },
  ["--boot"] = {
    help = [[The boot file. Default: ]]..default_bios_path,
    alias = {"-b"},
    count = 1,
    default = default_bios_path
  },
  ["--command"] = {
    help = [[The startup command.]],
    alias = {"-c"},
    count = 1
  },
  ["--disable-net"] = {
    help = [[Disables networking (http, socket).]],
    alias = {"-n"}
  },
  ["--enable-rs"] = {
    help = [[Enables redstone passthrough.]],
    alias = {"-R"}
  },
  ["--enable-per"] = {
    help = [[Enables peripheral passthrough.]],
    alias = {"-P"}
  },
  ["--enable-disk"] = {
    help = [[Enables disk drive passthrough.]],
    alias = {"-D"}
  },
  ["--output"] = {
    help = [[The location to output the launcher file. Default: ./%NAME%.lua]],
    alias = {"-o"},
    count = 1,
    default = "./%NAME%.lua"
  }
}

local function format_help()
  local str = help
  for k, v in pairs(flags) do
    str = str..k..", "..table.concat(v.alias,", ").." "..v.help.."\n"
  end
  return str
end

local function find_flag(flag)
  for k,v in pairs(flags) do
    if k == flag then
      return k
    else
      for k2,v2 in pairs(v.alias) do
        if v2 == flag then
          return k
        end
      end
    end
  end
end

local substitute_variable

local function substitute_variable(item, var, val)
  local function sub(a, b, c)
    local d = a:gsub("%%"..b.."%%", c)
    if a:find("%%"..b.."%%") then
      debug(a.." -> "..d)
    end
    return d
  end

  if type(item) == "string" then
    return sub(item, var, val)
  elseif type(item) == "table" then
    for k, v in pairs(item) do
      item[k] = substitute_variable(v, var, val)
    end

    return item
  end
end

local function parse_args(args)
  local parsed = {}
  local consume = 0
  local consuming = ""

  for i,v in ipairs(args) do
    if i == 1 then
      parsed["name"] = v
    elseif consume > 0 then
      v = substitute_variable(v, "NAME", parsed["name"])
      if flags[consuming].count > 1 or flags[consuming].multiple then
        table.insert(parsed[consuming], v)
      else
        parsed[consuming] = v
      end
      consume = consume - 1
    else
      local flag = find_flag(v)
      if flags[flag].count then
        consume = flags[flag].count
        consuming = flag
        if not parsed[flag] and (flags[flag].count > 1 or flags[flag].multiple) then
          parsed[flag] = {}
        end
      else
        parsed[flag] = true
      end
    end
  end

  for k,v in pairs(flags) do
    if not parsed[k] and v.default then
      v.default = substitute_variable(v.default, "NAME", parsed["name"])
      parsed[k] = v.default
    end
  end

  return parsed
end

local function yes_or_no(msg)
  write(msg.." (Y/n) ")
  term.setCursorBlink(true)
  local ev, key = os.pullEvent("key")
  term.setCursorBlink(false)
  print()

  if key == keys.enter or key == keys.y then
    return true
  else
    return false
  end
end

local function ask_for_directory(dir)
  if not fs.exists(dir) then
    local q = yes_or_no("Directory "..dir.." does not exist. Would you like to create it?")
    if q then
      fs.makeDir(dir)
    else
      error("Directory "..dir.." not created.")
    end
  end
end

local function ask_for_file(name, paths, dl)
  local found
  for i,v in ipairs(paths) do
    if fs.exists(v) then
      found = true
      return v
    end
  end
  if not found then
    local q = yes_or_no(name.." does not exist. Would you like to download it?")
    if q then
      shell.run(unpack(dl))
      return resolve(name)
    else
      error(path.." not created.")
    end
  end
end

ask_for_directory(resolve("/vms"))

local ccbox_path = ask_for_file("ccbox.lua", {resolve("ccbox.lua"), resolve("ccbox"), resolve("/ccbox.lua"), resolve("/ccbox")}, {"pastebin", "get", "PheuiSP1", "ccbox.lua"})

if #args < 1 or args[1] == "?" or args[1] == "help" or args[1] == "-?" or args[1] == "-help" or args[1] == "--?" or args[1] == "--help" then
  error(format_help())
end

local pargs = parse_args(args)
ask_for_file(pargs["--boot"], {pargs["--boot"]}, {"wget","https://raw.githubusercontent.com/dan200/ComputerCraft/master/src/main/resources/assets/computercraft/lua/bios.lua",pargs["--boot"]})

debug(textutils.serialize(pargs))

local name = pargs["name"]
pargs["name"] = nil
ask_for_directory(resolve("/vms/"..name))

local mounts = pargs["--vfs-mount"]
pargs["--vfs-mount"] = nil
local output = resolve(pargs["--output"])
pargs["--output"] = nil

debug(textutils.serialize(pargs))

local vmargs = {}

table.insert(vmargs, ccbox_path)

for k,v in pairs(pargs) do
  table.insert(vmargs, k)
  table.insert(vmargs, v)
end

for i,v in ipairs(mounts) do
  table.insert(vmargs, v)
end

debug(textutils.serialize(vmargs))

local fi = fs.open(output, "w")
fi.write("-- Generated by mkvm, a program by Justync7\n")
fi.write("shell.run(unpack("..textutils.serialize(vmargs).."))")
fi.close()

print("Saved VM launcher to "..output)
