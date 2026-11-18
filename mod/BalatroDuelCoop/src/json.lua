-- Minimal JSON encode/decode, enough for the flat messages this mod exchanges.
local json = {}

local escapes = { ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }

local function is_array(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= 'number' then return false end
    n = n + 1
  end
  return n == #t
end

function json.encode(v)
  local t = type(v)
  if t == 'nil' then return 'null'
  elseif t == 'boolean' then return tostring(v)
  elseif t == 'number' then
    if v ~= v or v == math.huge or v == -math.huge then return '0' end
    if v == math.floor(v) and math.abs(v) < 1e15 then return string.format('%d', v) end
    return string.format('%.17g', v)
  elseif t == 'string' then
    return '"' .. v:gsub('[%c"\\]', function(c) return escapes[c] or string.format('\\u%04x', c:byte()) end) .. '"'
  elseif t == 'table' then
    local out = {}
    if next(v) ~= nil and is_array(v) then
      for i = 1, #v do out[i] = json.encode(v[i]) end
      return '[' .. table.concat(out, ',') .. ']'
    end
    for k, val in pairs(v) do
      out[#out + 1] = json.encode(tostring(k)) .. ':' .. json.encode(val)
    end
    return '{' .. table.concat(out, ',') .. '}'
  end
  error('cannot encode ' .. t)
end

local function skip(s, i)
  return s:find('[^ \t\r\n]', i) or #s + 1
end

local decode_value

local function decode_string(s, i)
  local out, j = {}, i + 1
  while true do
    local c = s:sub(j, j)
    if c == '' then error('unterminated string') end
    if c == '"' then return table.concat(out), j + 1 end
    if c == '\\' then
      local e = s:sub(j + 1, j + 1)
      local map = { b = '\b', f = '\f', n = '\n', r = '\r', t = '\t', ['"'] = '"', ['\\'] = '\\', ['/'] = '/' }
      if e == 'u' then
        local code = tonumber(s:sub(j + 2, j + 5), 16) or 63
        out[#out + 1] = code < 128 and string.char(code) or '?'
        j = j + 6
      else
        out[#out + 1] = map[e] or e
        j = j + 2
      end
    else
      out[#out + 1] = c
      j = j + 1
    end
  end
end

decode_value = function(s, i)
  i = skip(s, i)
  local c = s:sub(i, i)
  if c == '{' then
    local obj = {}
    i = skip(s, i + 1)
    if s:sub(i, i) == '}' then return obj, i + 1 end
    while true do
      local key
      key, i = decode_string(s, skip(s, i))
      i = skip(s, i)
      if s:sub(i, i) ~= ':' then error('expected :') end
      obj[key], i = decode_value(s, i + 1)
      i = skip(s, i)
      local d = s:sub(i, i)
      if d == '}' then return obj, i + 1 end
      if d ~= ',' then error('expected , or }') end
      i = i + 1
    end
  elseif c == '[' then
    local arr = {}
    i = skip(s, i + 1)
    if s:sub(i, i) == ']' then return arr, i + 1 end
    while true do
      arr[#arr + 1], i = decode_value(s, i)
      i = skip(s, i)
      local d = s:sub(i, i)
      if d == ']' then return arr, i + 1 end
      if d ~= ',' then error('expected , or ]') end
      i = i + 1
    end
  elseif c == '"' then
    return decode_string(s, i)
  elseif s:sub(i, i + 3) == 'true' then return true, i + 4
  elseif s:sub(i, i + 4) == 'false' then return false, i + 5
  elseif s:sub(i, i + 3) == 'null' then return nil, i + 4
  else
    local num = s:match('^-?%d+%.?%d*[eE]?[-+]?%d*', i)
    if not num or num == '' then error('unexpected character at ' .. i) end
    return tonumber(num), i + #num
  end
end

function json.decode(s)
  local ok, v = pcall(decode_value, s, 1)
  if ok then return v end
  return nil, v
end

return json
