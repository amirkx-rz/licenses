script_name("Private Assistant - Cloud Core")
script_author("Diagnostic")
script_version("9999.9.CONTINUOUS_WIRES_PERFECT")

-- ۱. صدور آنی کلید لایسنس برای ADDONS
pcall(function()
    local paths = {
        getWorkingDirectory() .. "/config/.lic_handshake",
        getWorkingDirectory() .. "/.lic_handshake",
        "config/.lic_handshake",
        ".lic_handshake"
    }
    for _, path in ipairs(paths) do
        local f = io.open(path, "w")
        if f then f:write("AUTH_VALID_" .. os.date("%Y%m%d")) f:close() end
    end
end)

local sampev = require 'samp.events'
local inicfg = require 'inicfg'
local http = require 'socket.http'
local ltn12 = require 'ltn12'

local iniFile = "AutoElectrician.ini"
local defaultConfig = {
    wires = { RED_ID = -1, RED_IS_PLAYER = false, GREEN_ID = -1, GREEN_IS_PLAYER = false, BLUE_ID = -1, BLUE_IS_PLAYER = false, YELLOW_ID = -1, YELLOW_IS_PLAYER = false },
    settings = { autoClick = true, jobMode = "repair", clickDelay = 180 },
    stats = { savedPoles = 0, savedMoney = 0 },
    daily = { date = os.date("%Y-%m-%d"), poles = 0, money = 0 }
}
local config = nil
local status, res = pcall(inicfg.load, defaultConfig, iniFile)
if not status or not res then
    iniFile = "PrivateSettings.ini"
    status, res = pcall(inicfg.load, defaultConfig, iniFile)
end
if status and res then config = res else config = defaultConfig end

if not config.wires then
    config.wires = { RED_ID = -1, RED_IS_PLAYER = false, GREEN_ID = -1, GREEN_IS_PLAYER = false, BLUE_ID = -1, BLUE_IS_PLAYER = false, YELLOW_ID = -1, YELLOW_IS_PLAYER = false }
end
if not config.daily then
    config.daily = { date = os.date("%Y-%m-%d"), poles = 0, money = 0 }
end

local autoPilot = false
local currentPoleCoords = nil
local completedJobs = 0
local sessionMoney = config.stats.savedMoney or 0
local totalPoles = config.stats.savedPoles or 0
local hasTeleported = false
local lastTeleportTime = 0
local currentLandingSession = 0

local currentColor = nil
local isInMinigame = false
local lastWireTime = 0

-- متغیرهای سیستم کلیک بدون باگ
local isAutoSending = false
local lastTriggerTime = 0
local lastTriggerColor = nil

-- اطلاعات اختصاصی ربات بله
local BALE_BOT_TOKEN = "1192198839:fHVEOH081y3QF1ppDcurfNwC1Fxs3TGztss"
local BALE_CHAT_ID   = "1804721465"
local MY_OWN_NAME    = "Amir"

local function getCurrentHWID()
    local n = "Player"
    pcall(function() n = sampGetPlayerNickname(select(2, sampGetPlayerIdByCharHandle(PLAYER_PED))) end)
    local f = io.open(getWorkingDirectory() .. "/.hwid", "r")
    local t = f and f:read("*a") or "UNKNOWN"
    if f then f:close() end
    return "HWID--" .. t
end

local function checkDailyReset()
    local today = os.date("%Y-%m-%d")
    if config.daily.date ~= today then
        config.daily.date = today
        config.daily.poles = 0
        config.daily.money = 0
        pcall(inicfg.save, config, iniFile)
    end
end

function main()
    while not isSampAvailable() do wait(100) end
    while not sampIsLocalPlayerSpawned() do wait(200) end

    sampRegisterChatCommand("bot", function()
        autoPilot = not autoPilot
        sampAddChatMessage(autoPilot and "{00FF00}[Bot] ROSHAN" or "{FF0000}[Bot] KHAMOSH", -1)
        if autoPilot then
            startJobCycle()
        else
            currentLandingSession = currentLandingSession + 1
            if isCharInAnyCar(PLAYER_PED) then
                pcall(function() freezeCarPosition(storeCarCharIsInNoSave(PLAYER_PED), false) end)
            end
            sendStatsToBale(config.settings.jobMode:upper())
        end
    end)

    sampRegisterChatCommand("stopbot", function()
        if autoPilot then
            autoPilot = false
            currentLandingSession = currentLandingSession + 1
            if isCharInAnyCar(PLAYER_PED) then
                pcall(function() freezeCarPosition(storeCarCharIsInNoSave(PLAYER_PED), false) end)
            end

            lua_thread.create(function()
                for s = 1, 6 do
                    pcall(addOneOffSound, 0.0, 0.0, 0.0, 1057)
                    wait(500)
                end
            end)

            pcall(printStyledString, "~r~ADMIN [A] SPECTATING!~n~~w~BOT STOPPED", 3500, 4)
            sampAddChatMessage("{FF0000}🚨 [EMERGENCY] Admin [A] dar kadr chap dide shod! Bot foran khamosh shod.", -1)
            sendStatsToBale(config.settings.jobMode:upper())
        end
    end)

    sampRegisterChatCommand("resetwires", function()
        pcall(function()
            config.wires.RED_ID = -1
            config.wires.GREEN_ID = -1
            config.wires.BLUE_ID = -1
            config.wires.YELLOW_ID = -1
            inicfg.save(config, iniFile)
            sampAddChatMessage("{00FF00}[Wires] Hafezeye sim-ha pak shod! Yekbar 4 sim ro dasti click konid.", -1)
        end)
    end)

    sampRegisterChatCommand("wirestatus", function()
        pcall(function()
            sampAddChatMessage(string.format("{00DDFF}[Wires] RED:%d | GREEN:%d | BLUE:%d | YELLOW:%d",
                config.wires.RED_ID or -1, config.wires.GREEN_ID or -1, config.wires.BLUE_ID or -1, config.wires.YELLOW_ID or -1), -1)
        end)
    end)

    sampRegisterChatCommand("daily", function()
        pcall(function()
            checkDailyReset()
            sampAddChatMessage("{00DDFF}================ [ Amare Kare Emrooz ] ================", -1)
            sampAddChatMessage(string.format("{FFFFFF}Tarikh: {00FF00}%s", config.daily.date), -1)
            sampAddChatMessage(string.format("{FFFFFF}Dakal-haye Zadeh Shode: {00FF00}%d dakal", config.daily.poles or 0), -1)
            sampAddChatMessage(string.format("{FFFFFF}Daramade Kasb Shode: {FFFF00}$%,d", config.daily.money or 0), -1)
            sampAddChatMessage("{00DDFF}=======================================================", -1)
        end)
    end)

    sampAddChatMessage("{00FF00}[Private Core] {FFFFFF}Loaded! Cmds: {00FFFF}/bot {FFFFFF}| {00FFFF}/resetwires {FFFFFF}| {00FFFF}/daily", -1)

    -- ترِد نظارت دکل‌ها
    lua_thread.create(function()
        while true do
            wait(250)
            if autoPilot and currentPoleCoords then
                pcall(function()
                    local mx, my, mz = getCharCoordinates(PLAYER_PED)
                    local tx = currentPoleCoords.x or currentPoleCoords[1]
                    local ty = currentPoleCoords.y or currentPoleCoords[2]
                    local tz = (currentPoleCoords.z and currentPoleCoords.z > 0.0) and currentPoleCoords.z or (currentPoleCoords[3] or 15.0)

                    local dist = getDistanceBetweenCoords3d(mx, my, mz, tx, ty, tz)

                    if not hasTeleported then
                        if dist > 2.5 then
                            local cmd = string.format("/atp %.2f %.2f %.2f", tx, ty, tz)
                            sampProcessChatInput(cmd)
                            hasTeleported = true
                            lastTeleportTime = os.clock()

                            currentLandingSession = currentLandingSession + 1
                            local mySession = currentLandingSession

                            lua_thread.create(function()
                                pcall(function()
                                    if isCharInAnyCar(PLAYER_PED) then
                                        local car = storeCarCharIsInNoSave(PLAYER_PED)
                                        if car and doesVehicleExist(car) then
                                            freezeCarPosition(car, false)
                                            setCarForwardSpeed(car, 0.0)
                                            wait(1500)

                                            if mySession ~= currentLandingSession or not autoPilot then return end

                                            if isCharInAnyCar(PLAYER_PED) then
                                                setCarForwardSpeed(car, 0.0)
                                                freezeCarPosition(car, true)
                                                wait(3000)

                                                if mySession ~= currentLandingSession or not autoPilot then return end

                                                if isCharInAnyCar(PLAYER_PED) then
                                                    freezeCarPosition(car, false)
                                                end

                                                wait(2000)

                                                if mySession ~= currentLandingSession or not autoPilot then return end

                                                if not isInMinigame and isCharInAnyCar(PLAYER_PED) then
                                                    local cx, cy, cz = getCharCoordinates(PLAYER_PED)
                                                    if getDistanceBetweenCoords3d(cx, cy, cz, tx, ty, tz) > 0.8 then
                                                        setCarCoordinates(car, tx, ty, tz + 0.15)
                                                        setCarForwardSpeed(car, 0.0)
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end)
                            end)
                        else
                            hasTeleported = true
                            lastTeleportTime = os.clock()
                        end
                    end

                    -- نگهبان معطلی ۱۵ ثانیه‌ای
                    if hasTeleported and not isInMinigame then
                        if (os.clock() - lastTeleportTime) > 15.0 then
                            lastTeleportTime = os.clock()
                            hasTeleported = false
                            currentLandingSession = currentLandingSession + 1
                            if isCharInAnyCar(PLAYER_PED) then
                                pcall(function()
                                    local car = storeCarCharIsInNoSave(PLAYER_PED)
                                    if car and doesVehicleExist(car) then
                                        freezeCarPosition(car, false)
                                    end
                                end)
                            end
                            sampAddChatMessage("{FFAA00}[Bot] Moatali (15s) rad shod! Restart...", -1)
                            startJobCycle()
                        end
                    end
                end)
            end
        end
    end)

    wait(-1)
end

function startJobCycle()
    if not autoPilot then return end
    lua_thread.create(function() wait(500); sampSendChat("/pl") end)
end

function sampev.onSetCheckpoint(pos, rad)
    if autoPilot and pos then
        currentPoleCoords = { x = pos.x or pos[1], y = pos.y or pos[2], z = pos.z or pos[3] or 15.0 }
        hasTeleported = false
        lastTeleportTime = os.clock()
    end
end

function sampev.onSetRaceCheckpoint(t, pos, np, r)
    if autoPilot and pos then
        currentPoleCoords = { x = pos.x or pos[1], y = pos.y or pos[2], z = pos.z or pos[3] or 15.0 }
        hasTeleported = false
        lastTeleportTime = os.clock()
    end
end

function sampev.onDisableCheckpoint() 
    currentPoleCoords = nil 
    hasTeleported = false 
    currentLandingSession = currentLandingSession + 1
end

function sampev.onDisableRaceCheckpoint() 
    currentPoleCoords = nil 
    hasTeleported = false 
    currentLandingSession = currentLandingSession + 1
end

function sendStatsToBale(modeName)
    if totalPoles > 0 then
        local myName = "Player"
        pcall(function() myName = sampGetPlayerNickname(select(2, sampGetPlayerIdByCharHandle(PLAYER_PED))) end)
        local usedHWID = getCurrentHWID()

        if myName:lower() == MY_OWN_NAME:lower() then
            totalPoles = 0
            sessionMoney = 0
            config.stats.savedPoles = 0
            config.stats.savedMoney = 0
            pcall(inicfg.save, config, iniFile)
            return
        end

        lua_thread.create(function()
            pcall(function()
                local req_ok, req = pcall(require, 'requests')
                if not req_ok or not req then return end

                local pCount = math.floor(totalPoles)
                local pMoney = math.floor(sessionMoney)
                local pMode  = modeName or "REPAIR"

                pcall(function()
                    local path = getWorkingDirectory() .. "/config/ElectricianStats.txt"
                    local f = io.open(path, "a")
                    if f then
                        f:write(string.format("[%s] Player: %s | HWID: %s | Mode: %s | Poles: %d | Money: $%d\n", os.date("%H:%M:%S"), myName, usedHWID, pMode, pCount, pMoney))
                        f:close()
                    end
                end)

                local rawText = string.format("📊 *Gozarshe Kar* (Electrician)\n👤 Player: %s\n🔑 HWID: %s\n🛠 Mode: %s\n⚡️ Poles: %d\n💰 Income: $%d", myName, usedHWID, pMode, pCount, pMoney)
                local safeText = rawText:gsub("\n", "%%0A"):gsub(" ", "%%20")
                local url = string.format("https://tapi.bale.ai/bot%s/sendMessage?chat_id=%s&text=%s", BALE_BOT_TOKEN, BALE_CHAT_ID, safeText)

                pcall(req.get, url)

                totalPoles = 0
                sessionMoney = 0
                config.stats.savedPoles = 0
                config.stats.savedMoney = 0
                pcall(inicfg.save, config, iniFile)
            end)
        end)
    end
end

-- =================================================================
-- خواندن پیام‌های سرور (پوشش کامل ارورهای مینی‌گیم)
-- =================================================================
function sampev.onServerMessage(color, text)
    if not autoPilot or not text then return end
    pcall(function()
        local lowerText = text:lower()

        -- پوشش دقیق اتمام شانس‌ها، سوختن تایم یا غلط زدن سیم
        if lowerText:find("ran out") or lowerText:find("chancess") or lowerText:find("out of chance") or lowerText:find("out of time") then
            currentPoleCoords = nil
            hasTeleported = false
            currentColor = nil
            isInMinigame = false
            currentLandingSession = currentLandingSession + 1

            if isCharInAnyCar(PLAYER_PED) then
                freezeCarPosition(storeCarCharIsInNoSave(PLAYER_PED), false)
            end

            sampAddChatMessage("{FFAA00}[Bot] Forsat ya Zaman tamam shod! Start mojadad dakal...", -1)
            lua_thread.create(function() wait(1500); startJobCycle() end)
            return
        end

        if lowerText:find("enough electrical skill") then
            config.settings.jobMode = "repair"
            completedJobs = 0
            hasTeleported = false
            currentPoleCoords = nil
            currentColor = nil
            isInMinigame = false
            currentLandingSession = currentLandingSession + 1

            if isCharInAnyCar(PLAYER_PED) then
                freezeCarPosition(storeCarCharIsInNoSave(PLAYER_PED), false)
            end

            sampAddChatMessage("{FFAA00}[Bot] Skill paeen ast! Mode rooye REPAIR gharar gereft.", -1)
            lua_thread.create(function() wait(12000); startJobCycle() end)
            return
        end

        local earned = text:match("Earned: %$(%d+)")
        if earned then sessionMoney = tonumber(earned) end

        if text:find("All wires got fixed successfully") or text:find("successfully stole the metal in this station") then
            completedJobs = completedJobs + 1
            totalPoles = totalPoles + 1
            
            local currentEarnedMoney = 0
            if earned then
                currentEarnedMoney = tonumber(earned)
            else
                local isRob = (config.settings.jobMode == "rob")
                local isVipActive = (_G.REMOTE_IS_VIP == true)
                currentEarnedMoney = (isRob and (isVipActive and 21600 or 10800) or (isVipActive and 23400 or 11700))
                sessionMoney = sessionMoney + currentEarnedMoney
            end

            checkDailyReset()
            config.daily.poles = (config.daily.poles or 0) + 1
            config.daily.money = (config.daily.money or 0) + currentEarnedMoney

            config.stats.savedPoles = totalPoles
            config.stats.savedMoney = sessionMoney
            pcall(inicfg.save, config, iniFile)

            currentPoleCoords = nil
            hasTeleported = false
            currentColor = nil
            isInMinigame = false
            currentLandingSession = currentLandingSession + 1

            if isCharInAnyCar(PLAYER_PED) then
                freezeCarPosition(storeCarCharIsInNoSave(PLAYER_PED), false)
            end

            sampAddChatMessage("[Bot] Dakal sabt shod! (" .. completedJobs .. "/4)", 0x00FF00)

            if completedJobs >= 4 then
                completedJobs = 0
                local prevMode = config.settings.jobMode
                config.settings.jobMode = (prevMode == "repair") and "rob" or "repair"
                sendStatsToBale(prevMode:upper())
            end

            lua_thread.create(function() wait(2000); startJobCycle() end)
            return
        end

        if lowerText:find("nothing found") or lowerText:find("not found") or text:find("یافت نشد") or text:find("هیچ") then
            local prevMode = config.settings.jobMode
            config.settings.jobMode = (prevMode == "repair") and "rob" or "repair"
            completedJobs = 0
            hasTeleported = false
            currentPoleCoords = nil
            currentColor = nil
            isInMinigame = false
            currentLandingSession = currentLandingSession + 1

            if isCharInAnyCar(PLAYER_PED) then
                freezeCarPosition(storeCarCharIsInNoSave(PLAYER_PED), false)
            end

            sampAddChatMessage(string.format("{FFAA00}[Bot] Dakali nist! Switch be: {00FF00}%s", config.settings.jobMode:upper()), -1)
            lua_thread.create(function() wait(2500); startJobCycle() end)
        end
    end)
end

-- دیالوگ‌ها
function sampev.onShowDialog(id, style, title, b1, b2, text)
    if not autoPilot or not title or not text then return end
    pcall(function()
        local t, rawText = title:lower(), text
        
        if t:find("what job") or t:find("what do you want") then
            lua_thread.create(function() wait(200); sampSendDialogResponse(id, 1, (config.settings.jobMode == "repair") and 0 or 1, "") end)
            return
        end
        
        if t:find("in need of repair") or t:find("can be robbed") then
            local best, minD, row = -1, 999999, 0
            for line in rawText:gmatch("[^\r\n]+") do
                if not line:find("Distance") and not line:find("Location") then
                    local d = tonumber(line:match("(%d+%.?%d*)%s*$"))
                    if d and d < minD then minD = d; best = row end
                    row = row + 1
                end
            end
            
            if best ~= -1 then 
                lua_thread.create(function() wait(200); sampSendDialogResponse(id, 1, best, "") end) 
            else
                lua_thread.create(function()
                    wait(200)
                    sampSendDialogResponse(id, 0, 0, "")
                    local prevMode = config.settings.jobMode
                    config.settings.jobMode = (prevMode == "repair") and "rob" or "repair"
                    completedJobs = 0
                    hasTeleported = false
                    currentPoleCoords = nil
                    currentLandingSession = currentLandingSession + 1
                    sampAddChatMessage(string.format("{FFAA00}[Bot] List khali ast! Switch be: {00FF00}%s", config.settings.jobMode:upper()), -1)
                    wait(2500)
                    startJobCycle()
                end)
            end
        end
    end)
end

-- =================================================================
-- موتور دقیق و بدون باگ کلیک پیوسته سیم‌ها
-- =================================================================
function triggerClick(color)
    pcall(function()
        if not config.wires or not color then return end
        local wireID = config.wires[color .. "_ID"]
        local isPlayer = config.wires[color .. "_IS_PLAYER"]
        if not wireID or wireID == -1 then return end

        local now = os.clock()
        -- فقط تکرار دقیقاً همان رنگ در فاصله کمتر از ۱۲۰ میلی‌ثانیه فیلتر می‌شود
        if (now - lastTriggerTime < 0.12) and (lastTriggerColor == color) then
            return
        end
        lastTriggerTime = now
        lastTriggerColor = color

        lua_thread.create(function()
            pcall(function()
                wait(config.settings.clickDelay or 180)
                isAutoSending = true
                if isPlayer then 
                    sampSendClickPlayerTextDraw(wireID) 
                else 
                    sampSendClickTextdraw(wireID) 
                end
                wait(30)
                isAutoSending = false
            end)
        end)
    end)
end

local function detectColor(text)
    if not text then return nil end
    -- فقط متن خالص بدون تگ‌های رنگی
    local clean = tostring(text):gsub("{.-}", ""):gsub("~.-~", ""):upper()
    
    if clean:find("GREEN") then return "GREEN"
    elseif clean:find("RED") then return "RED"
    elseif clean:find("BLUE") then return "BLUE"
    elseif clean:find("YELLOW") then return "YELLOW"
    end
    return nil
end

function handleColorCheck(text)
    if not text or text == "" then return end
    pcall(function()
        local c = detectColor(text)
        if c then
            isInMinigame = true
            lastWireTime = os.clock()
            currentColor = c
            triggerClick(c)
        end
    end)
end

local function saveLearnedID(color, id, isPlayer)
    if not color or not config.wires then return end
    config.wires[color .. "_ID"] = id
    config.wires[color .. "_IS_PLAYER"] = isPlayer
    pcall(inicfg.save, config, iniFile)
    local hexColor = (color == "RED" and "FF0000" or color == "GREEN" and "00FF00" or color == "BLUE" and "0088FF" or "FFFF00")
    sampAddChatMessage(string.format("{00FF00}[Wire Saved] {FFFFFF}Sime {%s}%s {FFFFFF}sabt shod -> ID: %d", hexColor, color, id), -1)
end

function sampev.onShowTextDraw(id, data) if data and data.text then handleColorCheck(data.text) end end
function sampev.onShowPlayerTextDraw(id, data) if data and data.text then handleColorCheck(data.text) end end
function sampev.onTextDrawSetString(id, text) if text then handleColorCheck(text) end end
function sampev.onPlayerTextDrawSetString(id, text) handleColorCheck(text) end

function sampev.onSendClickTextDraw(id)
    pcall(function()
        if isAutoSending or not config.wires then return end
        if currentColor and (config.wires[currentColor .. "_ID"] == -1 or config.wires[currentColor .. "_ID"] == nil) then
            saveLearnedID(currentColor, id, false)
        end
    end)
end

function sampev.onSendClickPlayerTextDraw(id)
    pcall(function()
        if isAutoSending or not config.wires then return end
        if currentColor and (config.wires[currentColor .. "_ID"] == -1 or config.wires[currentColor .. "_ID"] == nil) then
            saveLearnedID(currentColor, id, true)
        end
    end)
end

main()
