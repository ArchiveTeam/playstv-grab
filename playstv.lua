dofile("table_show.lua")
dofile("urlcode.lua")
JSON = (loadfile "JSON.lua")()

local item_type = os.getenv('item_type')
local item_value = os.getenv('item_value')
local item_dir = os.getenv('item_dir')
local warc_file_base = os.getenv('warc_file_base')

local url_count = 0
local tries = 0
local downloaded = {}
local addedtolist = {}
local abortgrab = false

local ids = {}
local allowed_urls = {}
local discovered = {}

for s in string.gmatch(item_value, "([^;]+)") do
    ids[s] = true
end

for ignore in io.open("ignore-list", "r"):lines() do
  downloaded[ignore] = true
end

load_json_file = function(file)
  if file then
    return JSON:decode(file)
  else
    return nil
  end
end

read_file = function(file)
  if file then
    local f = assert(io.open(file))
    local data = f:read("*all")
    f:close()
    return data
  else
    return ""
  end
end

allowed = function(url, parenturl)
  if string.match(url, "'+")
      or string.match(url, "[<>\\%*%$;%^%[%],%(%){}]")
      or string.match(url, "^https?://[^/]*plays%.tv/game/")
      or string.match(url, "^https?://[^/]*plays%.tv/video/[0-9a-f]+/?.+[%?&]page=[0-9]")
      or not (
        string.match(url, "^https?://[^/]*plays%.tv/")
        or string.match(url, "^https?://[^/]*akamaihd%.net/")
        or string.match(url, "^https?://[^/]*playscdn%.tv/")
      ) then
    return false
  end

  local match = string.match(url, "^https?://[^/]*plays%.tv/video/([0-9a-f]+)")
  if match ~= nil then
    discovered["video:" .. match] = true
  end

  local tested = {}
  for s in string.gmatch(url, "([^/]+)") do
    if tested[s] == nil then
      tested[s] = 0
    end
    if tested[s] == 6 then
      return false
    end
    tested[s] = tested[s] + 1
  end

  if allowed_urls[url] then
    return true
  end

  if (string.match(url, "^https?://[^/]*akamaihd%.net/")
      or string.match(url, "^https?://[^/]*playscdn%.tv/"))
      and not (item_type == "video" and string.match(url, "%.mp4$")) then
    return true
  end

  local match = nil
  if item_type == "user" then
    match = "([0-9a-zA-Z%-_]+)"
  elseif item_type == "video" then
    match = "([0-9a-f]+)"
  end
  for s in string.gmatch(url, match) do
    if ids[s] then
      return true
    end
  end

  return false
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  local url = urlpos["url"]["url"]
  local html = urlpos["link_expect_html"]

  if string.match(url, "[<>\\%*%$;%^%[%],%(%){}\"]") then
    return false
  end
  
  return false
end

wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}
  local html = nil
  
  downloaded[url] = true

  local function check(urla, force)
    local origurl = url
    local url = string.match(urla, "^([^#]+)")
    local url_ = string.gsub(string.match(url, "^(.-)%.?$"), "&amp;", "&")
    if force then
      allowed_urls[url_] = true
    end
    local match = string.match(url, "^https?://[^/]*plays%.tv/u/([0-9a-zA-Z%-_]+)")
    if match then
      check("https://plays.tv/playsapi/usersys/v1/user/" .. match, true)
    end
    if (downloaded[url_] ~= true and addedtolist[url_] ~= true)
        and allowed(url_, origurl) then
      table.insert(urls, { url=url_ })
      addedtolist[url_] = true
      addedtolist[url] = true
    end
  end

  local function checknewurl(newurl, force)
    if string.match(newurl, "%s+") then
      for s in string.gmatch(newurl, "([^%s]+)") do
        checknewurl(s, force)
      end
    elseif string.match(newurl, "^https?:////") then
      check(string.gsub(newurl, ":////", "://"), force)
    elseif string.match(newurl, "^https?://") then
      check(newurl, force)
    elseif string.match(newurl, "^https?:\\/\\?/") then
      check(string.gsub(newurl, "\\", ""), force)
    elseif string.match(newurl, "^\\/\\/") then
      check(string.match(url, "^(https?:)") .. string.gsub(newurl, "\\", ""), force)
    elseif string.match(newurl, "^//") then
      check(string.match(url, "^(https?:)") .. newurl, force)
    elseif string.match(newurl, "^\\/") then
      check(string.match(url, "^(https?://[^/]+)") .. string.gsub(newurl, "\\", ""), force)
    elseif string.match(newurl, "^/") then
      check(string.match(url, "^(https?://[^/]+)") .. newurl, force)
    elseif string.match(newurl, "^%./") then
      checknewurl(string.match(newurl, "^%.(.+)"), force)
    end
  end

  local function checknewshorturl(newurl, force)
    if string.match(newurl, "^%?") then
      check(string.match(url, "^(https?://[^%?]+)") .. newurl, force)
    elseif not (string.match(newurl, "^https?:\\?/\\?//?/?")
        or string.match(newurl, "^[/\\]")
        or string.match(newurl, "^%./")
        or string.match(newurl, "^[jJ]ava[sS]cript:")
        or string.match(newurl, "^[mM]ail[tT]o:")
        or string.match(newurl, "^vine:")
        or string.match(newurl, "^android%-app:")
        or string.match(newurl, "^ios%-app:")
        or string.match(newurl, "^%${")) then
      check(string.match(url, "^(https?://.+/)") .. newurl, force)
    end
  end

  local function check_scroll_url(params)
    local newurl = "https://plays.tv/ws/module?"
    for k, v in pairs(params) do
      newurl = newurl .. k .. "=" .. v .. "&"
    end
    check(newurl .. "format=application%2Fjson&id=UserVideosMod")
  end

  if (allowed(url, nil)
      or string.match(url, "^https?://[^/]*plays%.tv/playsapi/usersys/v1/user/"))
      and status_code == 200 and not (
        string.match(url, "^https?://[^/]*akamaihd%.net/")
        or string.match(url, "^https?://[^/]*playscdn%.tv/")
        or string.match(url, "%?_t=")
    ) then
    html = read_file(file)
    if string.match(url, "^https?://[^/]*plays%.tv/playsapi/usersys/v1/user/") then
      local data = load_json_file(html)
      if data["id"] == nil or data["username"] == nil then
        io.stdout:write("Could not get ID and/or username.")
        io.stdout:flush()
        abortgrab = true
      end
      discovered["user:" .. data["id"]] = true
      if not ids[data["id"]] then
        return urls
      end
      ids[data["id"]] = true
      ids[data["username"]] = true
      check("https://plays.tv/playsapi/usersys/v1/user/" .. data["username"])
      check("https://plays.tv/playsapi/usersys/v1/user/" .. data["id"])
      check("https://plays.tv/ws/orbital/profile/" .. data["id"])
      check("https://plays.tv/ws/orbital/profile/" .. data["id"] .. "?_orbitalapp=1")
      check("https://plays.tv/u/" .. data["username"])
    elseif string.match(url, "^https?://[^/]*plays%.tv/playsapi/feedsys/v1/media/") then
      local data = load_json_file(html)
      if data["feedId"] == nil then
        io.stdout:write("Could not get feedId.")
        io.stdout:flush()
        abortgrab = true
      end
      check("https://plays.tv/video/" .. data["feedId"])
    elseif string.match(url, "^https?://[^/]*plays%.tv/u/[^/]+$")
        or string.match(url, "^https?://[^/]*plays%.tv/u/[^/]+/videos")
        or string.match(url, "^https?://[^/]*plays%.tv/u/[^/]+/featuring") then
      local user_id = string.match(html, '{"target_user_id":"([0-9a-f]+)","action":"report"}')
      if user_id == nil then
        io.stdout:write("Could not find target_user_id.")
        io.stdout:flush()
        abortgrab = true
      end
      ids[user_id] = true
      local data = string.match(html, "<div%s+class=\"mod%s+mod%-user%-videos[^\"]+activity%-feed\"[^>]+data%-conf='({[^}]+})'")
      if data ~= nil then
        check_scroll_url(load_json_file(data))
      end
    elseif string.match(url, "^https?://[^/]*plays%.tv/ws/module") then
      local data = load_json_file(html)
      if #data["body"] == 0 then
        return urls
      end
      check_scroll_url(data["config"])
      html = data["body"]
    elseif string.match(url, "^https?://[^/]*plays%.tv/u/[^/]+/follow...%?page=[0-9]+$") then
      local user = string.match(url, "/u/([^/]+)/")
      local new = false
      check(string.gsub(url, "[0-9]+$", "1"))
      for s in string.gmatch(html, "/u/([0-9a-zA-Z%-_]+)") do
        if s ~= user then
          new = true
        end
      end
      if not new then
        return urls
      end
    elseif string.match(url, "^https?://[^/]*plays%.tv/video/[0-9a-f]+") then
      local video_data = string.match(html, "<video%s+poster[^>]+>(.-)</video>")
      if video_data == nil then
        io.stdout:write("Video data not found.")
        io.stdout:flush()
        abortgrab = true
      end
      local selected_res = 0
      local selected_url = nil
      for source in string.gmatch(video_data, "<source%s+([^>]+)>") do
        local res = tonumber(string.match(source, 'res="([0-9]+)"'))
        local newurl = string.match(source, 'src="([^"]+)"')
        if res <= 720 and res > selected_res then
          selected_url = newurl
          selected_res = res
        end
      end
      if selected_url == nil then
        io.stdout:write("Could not find video URL.")
        io.stdout:flush()
        abortgrab = true
      end
      checknewurl(selected_url, true)
    end
    for newurl in string.gmatch(string.gsub(html, "&quot;", '"'), '([^"]+)') do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(string.gsub(html, "&#039;", "'"), "([^']+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, ">%s*([^<%s]+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, "[^%-]href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, '[^%-]href="([^"]+)"') do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, ":%s*url%(([^%)]+)%)") do
      checknewurl(newurl)
    end
  end

  return urls
end

wget.callbacks.httploop_result = function(url, err, http_stat)
  status_code = http_stat["statcode"]
  
  url_count = url_count + 1
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. "  \n")
  io.stdout:flush()

  if status_code == 404 and item_type == "video"
      and string.match(url["url"], "^https?://[^/]*akamaihd%.net/") then
    io.stdout:write("Content is not available.")
    io.stdout:flush()
    abortgrab = true
  end

  --[[if item_type == "user"
      and string.match(url["url"], "^https?://[^/]*plays%.tv/playsapi/usersys/v1/user/[0-9a-f]+$") then
    ids[string.match(url["url"], "([0-9a-f]+)$")] = true
  elseif item_type == "video"
      and string.match(url["url"], "^https?://[^/]*plays%.tv/playsapi/feedsys/v1/media/[0-9a-f]+$") then
    ids[string.match(url["url"], "([0-9a-f]+)$")] = true
  end]]

  if status_code >= 300 and status_code <= 399 then
    local newloc = string.match(http_stat["newloc"], "^([^#]+)")
    if string.match(newloc, "^//") then
      newloc = string.match(url["url"], "^(https?:)") .. string.match(newloc, "^//(.+)")
    elseif string.match(newloc, "^/") then
      newloc = string.match(url["url"], "^(https?://[^/]+)") .. newloc
    elseif not string.match(newloc, "^https?://") then
      newloc = string.match(url["url"], "^(https?://.+/)") .. newloc
    end
    if downloaded[newloc] == true or addedtolist[newloc] == true or not allowed(newloc, url["url"]) then
      tries = 0
      return wget.actions.EXIT
    end
  end
  
  if status_code >= 200 and status_code <= 399 then
    downloaded[url["url"]] = true
    downloaded[string.gsub(url["url"], "https?://", "http://")] = true
  end

  if abortgrab == true then
    io.stdout:write("ABORTING...\n")
    return wget.actions.ABORT
  end
  
  if status_code >= 500
      or (status_code >= 400 and status_code ~= 404)
      or status_code  == 0 then
    io.stdout:write("Server returned "..http_stat.statcode.." ("..err.."). Sleeping.\n")
    io.stdout:flush()
    local maxtries = 10
    if not allowed(url["url"], nil) then
        maxtries = 2
    end
    if tries > maxtries then
      io.stdout:write("\nI give up...\n")
      io.stdout:flush()
      tries = 0
      if allowed(url["url"], nil) then
        return wget.actions.ABORT
      else
        return wget.actions.EXIT
      end
    else
      os.execute("sleep " .. math.floor(math.pow(2, tries)))
      tries = tries + 1
      return wget.actions.CONTINUE
    end
  end

  tries = 0

  local sleep_time = 0

  if sleep_time > 0.001 then
    os.execute("sleep " .. sleep_time)
  end

  return wget.actions.NOTHING
end

wget.callbacks.finish = function(start_time, end_time, wall_time, numurls, total_downloaded_bytes, total_download_time)
  local file = io.open(item_dir..'/'..warc_file_base..'_data.txt', 'w')
  for gfy, _ in pairs(discovered) do
    file:write(gfy .. "\n")
  end
  file:close()
end

wget.callbacks.before_exit = function(exit_status, exit_status_string)
  if abortgrab == true then
    return wget.exits.IO_FAIL
  end
  return exit_status
end
