local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

-- Cấu hình API Endpoint của Web Dashboard
local API_URL = "http://localhost:3000/api/update-stats"
local UPDATE_INTERVAL = 15 -- Đồng bộ mỗi 15 giây

-- Lấy hàm HTTP Request an toàn
local env = (type(getgenv) == "function" and getgenv()) or _G
local httpRequest = (type(env.syn) == "table" and env.syn.request)
    or (type(env.http) == "table" and env.http.request)
    or env.http_request
    or (type(env.fluxus) == "table" and env.fluxus.request)
    or env.request
    or request

if type(httpRequest) ~= "function" then
    warn("[Tracker] Executor của bạn không hỗ trợ HTTP Request!")
    return
end

local matchStats = {
    wins = 0,
    losses = 0,
    lastResult = "Playing",
    matchTime = "00:00",
    countedCurrentMatch = false
}

local function formatSeconds(sec)
    sec = math.floor(tonumber(sec) or 0)
    local mins = math.floor(sec / 60)
    local secs = sec % 60
    return string.format("%02d:%02d", mins, secs)
end

local function updateMatchStatus()
    local mapConfig = Workspace:FindFirstChild("_MAP_CONFIG")
    local isLobby = mapConfig and mapConfig:FindFirstChild("IsLobby") and mapConfig.IsLobby.Value

    if isLobby then
        matchStats.lastResult = "Lobby"
        matchStats.matchTime = "00:00"
        matchStats.countedCurrentMatch = false
        return
    end

    local pGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not pGui then return end

    local resultsUI = pGui:FindFirstChild("ResultsUI")
    if resultsUI and resultsUI.Enabled then
        for _, label in ipairs(resultsUI:GetDescendants()) do
            if label:IsA("TextLabel") and label.Visible and label.Text ~= "" then
                local txt = label.Text:upper()
                if txt:find("VICTORY") or txt:find("WIN") then
                    matchStats.lastResult = "Victory"
                    if not matchStats.countedCurrentMatch then
                        matchStats.wins = matchStats.wins + 1
                        matchStats.countedCurrentMatch = true
                    end
                elseif txt:find("DEFEAT") or txt:find("FAILED") or txt:find("LOSE") then
                    matchStats.lastResult = "Defeat"
                    if not matchStats.countedCurrentMatch then
                        matchStats.losses = matchStats.losses + 1
                        matchStats.countedCurrentMatch = true
                    end
                end
                if txt:match("^%d%d?:%d%d$") then
                    matchStats.matchTime = txt
                end
            end
        end
        return
    else
        matchStats.lastResult = "Playing"
        matchStats.countedCurrentMatch = false
    end

    local foundTime = nil
    for _, label in ipairs(pGui:GetDescendants()) do
        if label:IsA("TextLabel") and label.Visible and label.Text:match("^%d%d?:%d%d$") then
            foundTime = label.Text
            break
        end
    end

    if foundTime then
        matchStats.matchTime = foundTime
    elseif Workspace:FindFirstChild("_wave_time") then
        matchStats.matchTime = formatSeconds(Workspace._wave_time.Value)
    end
end

local function getMapLocation()
    local mapConfig = Workspace:FindFirstChild("_MAP_CONFIG")
    if mapConfig then
        local isLobby = mapConfig:FindFirstChild("IsLobby") and mapConfig.IsLobby.Value
        if isLobby then return "Lobby" end

        local wave = Workspace:FindFirstChild("_wave_num") and Workspace._wave_num.Value or 0
        local mapName = nil

        for _, child in ipairs(mapConfig:GetChildren()) do
            if child:IsA("StringValue") and tostring(child.Value) ~= "" and tostring(child.Value) ~= "nil" then
                mapName = tostring(child.Value)
                break
            end
        end

        if not mapName then
            local attrs = mapConfig:GetAttributes()
            for _, v in pairs(attrs) do
                if type(v) == "string" and v ~= "" and v ~= "nil" then
                    mapName = v
                    break
                end
            end
        end

        if not mapName then
            local pGui = LocalPlayer:FindFirstChild("PlayerGui")
            if pGui then
                for _, label in ipairs(pGui:GetDescendants()) do
                    if label:IsA("TextLabel") and label.Visible and label.Text ~= "" then
                        local txt = label.Text:gsub("\n", " ")
                        if txt:find("Act ") or txt:find("Infinite") or txt:find("Raid") or txt:find("Normal") or txt:find("Nightmare") then
                            if #txt < 45 then
                                mapName = txt
                                break
                            end
                        end
                    end
                end
            end
        end

        return (mapName or "In-Game") .. " · Wave " .. tostring(wave)
    end
    return "Lobby"
end

local function collectGameData()
    updateMatchStatus()

    local stats = LocalPlayer:FindFirstChild("_stats")
    local currentXp = (stats and stats:FindFirstChild("player_xp") and tonumber(stats.player_xp.Value)) or 0

    local data = {
        username = LocalPlayer.Name,
        userId = LocalPlayer.UserId,
        gems = stats and stats:FindFirstChild("gem_amount") and stats.gem_amount.Value or 0,
        gold = stats and stats:FindFirstChild("gold_amount") and stats.gold_amount.Value or 0,
        xp = currentXp,
        summerPearls = stats and stats:FindFirstChild("_resourceSummerPearls") and stats._resourceSummerPearls.Value or 0,
        location = getMapLocation(),
        matchTime = matchStats.matchTime,
        matchResult = matchStats.lastResult,
        wins = matchStats.wins,
        losses = matchStats.losses,
        items = {},
        units = {}
    }

    local getGcFunc = env.getgc or getgc
    if type(getGcFunc) == "function" then
        for _, v in ipairs(getGcFunc(true)) do
            if type(v) == "table" then
                if rawget(v, "gem_amount") ~= nil and type(rawget(v, "inventory")) == "table" then
                    local traitTokens = rawget(v, "trait_reroll_tokens") or 0
                    if traitTokens > 0 then
                        table.insert(data.items, { name = "Trait Reroll Token", count = traitTokens, category = "Token" })
                    end

                    local curseTokens = rawget(v, "curse_reroll_tokens") or 0
                    if curseTokens > 0 then
                        table.insert(data.items, { name = "Curse Reroll Token", count = curseTokens, category = "Token" })
                    end

                    local normalItems = v.inventory.normal_items
                    if type(normalItems) == "table" then
                        for itemName, itemVal in pairs(normalItems) do
                            local count = type(itemVal) == "table" and (itemVal.amount or itemVal.count or 1) or itemVal
                            if type(count) == "number" and count > 0 then
                                table.insert(data.items, { name = tostring(itemName), count = count, category = "Normal" })
                            end
                        end
                    end

                    local uniqueItems = v.inventory.unique_items
                    if type(uniqueItems) == "table" then
                        for uuid, itemInfo in pairs(uniqueItems) do
                            if type(itemInfo) == "table" then
                                local itemName = tostring(itemInfo.item_id or itemInfo.id or itemInfo.name or uuid)
                                table.insert(data.items, { name = itemName, count = 1, category = "Unique" })
                            end
                        end
                    end
                end

                if type(rawget(v, "owned_units")) == "table" and rawget(v, "capacity") ~= nil then
                    for uuid, unitInfo in pairs(v.owned_units) do
                        if type(unitInfo) == "table" then
                            table.insert(data.units, {
                                id = tostring(unitInfo.unit_id or unitInfo.name or "Unknown"),
                                level = unitInfo.level or 1,
                                trait = unitInfo.trait or "None"
                            })
                        end
                    end
                end
            end
        end
    end

    return data
end

-- Vòng lặp gửi dữ liệu lên Web Dashboard
task.spawn(function()
    print("[Tracker] Đã kết nối thành công ->", API_URL)
    while true do
        local success, err = pcall(function()
            local payload = collectGameData()
            local res = httpRequest({
                Url = API_URL,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = HttpService:JSONEncode(payload)
            })
            print("[Tracker] Trạng thái gửi:", res and res.StatusCode or "Không có phản hồi")
        end)

        if not success then
            warn("[Tracker] Lỗi đồng bộ:", err)
        end

        task.wait(UPDATE_INTERVAL)
    end
end)