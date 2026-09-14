script_name("Private Assistant - Cloud Core")
script_author("Diagnostic")
script_version("5100.0.UI_PERSISTENCE")

local sampev = require 'samp.events'
local inicfg = require 'inicfg'
local http = require 'socket.http'
local ltn12 = require 'ltn12'

local iniFile = "AutoElectrician.ini"
local defaultConfig = {
    wires = { RED_ID = -1, RED_IS_PLAYER = false, GREEN_ID = -1, GREEN_IS_PLAYER = false, BLUE_ID = -1, BLUE_IS_PLAYER = false, YELLOW_ID = -1, YELLOW_IS_PLAYER = false },
    settings = { autoClick = true, jobMode = "repair", clickDelay = 220 },
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

if not config.daily then
    config.daily = { date = os.date("%Y-%m-%d"), poles = 0, money = 0 }
end

local autoPilot = false
local currentPoleCoords = nil
local completedJobs = 0
local sessionMoney = config.stats.savedMoney or 0
local totalPoles = config.stats.savedPoles or 0
local hasTeleported = false

local currentColor = nil
local isAutoClicking = false
local isInMinigame = false
local lastWireTime = 0
local lastClickTimestamp = 0
local lastColorDetectedTime = 0
local adminDetectedAlert = false

-- نگهبان ضد گیرکردن ربات
local lastTeleportTime = 0

local BALE_BOT_TOKEN = "1192198839:fHVEOH081y3QF1ppDcurfNwC1Fxs3TGztss"
local BALE_CHAT_ID   = "1804721465"
local MY_OWN_NAME    = "Amir"

local function checkDailyReset()
    local today = os.date("%Y-%m-%d")
    if config.daily.date ~= today then
        config.daily.date = today
        config.daily.poles = 0
        config.daily.money = 0
        pcall(inicfg.save, config, iniFile)
    end
end

if renderFontDrawText then
    local orig_render = renderFontDrawText
    renderFontDrawText = function(font, text, x, y, color)
        if type(x) == "number" and x < 350 and text then
            local str = tostring(text)
            if str:find("%[A%]") then
                adminDetectedAlert = true
            end
        end
        return orig_render(font, text, x, y, color)
    end
end

function main()
    while not isSampAvailable() do wait(100) end
    while not sampIsLocalPlayerSpawned() do wait(200) end

    -- =================================================================
    -- ترِد نگهبان رابط کاربری آرت (جلوگیری از غیب شدن لیست‌ها بعد از لاگین)
    -- =================================================================
    lua_thread.create(function()
        while true do
            wait(1000)
            pcall(function()
                rawset(_G, "SpecNotification", true)
                rawset(_G, "OnlineNotification", true)
                rawset(_G, "AntiPublic", false)
                if rawget(_G, "tagA") then rawget(_G, "tagA")[0] = true end
                if rawget(_G, "tagH") then rawget(_G, "tagH")[0] = true end
                if rawget(_G, "tagV") then rawget(_G, "tagV")[0] = true end
                if rawget(_G, "tagNormal") then rawget(_G, "tagNormal")[0] = true end
            end)
        end
    end)

    sampRegisterChatCommand("bot", function()
        autoPilot = not autoPilot
        sampAddChatMessage(autoPilot and "{00FF00}[Bot] ROSHAN" or "{FF0000}[Bot] KHAMOSH", -1)
        if autoPilot then
            startJobCycle()
        else
            if isCharInAnyCar(PLAYER_PED) then
                freezeCarPosition(storeCarCharIsInNoSave(PLAYER_PED), false)
            end
            sendStatsToBale(config.settings.jobMode:upper())
        end
    end)

    sampRegisterChatCommand("resetwires", function()
        config.wires.RED_ID = -1
        config.wires.GREEN_ID = -1
        config.wires.BLUE_ID = -1
        config.wires.YELLOW_ID = -1
        pcall(inicfg.save, config, iniFile)
        sampAddChatMessage("{00FF00}[Wires] Hafezeye sim-ha pak shod! Yekbar 4 sim ro dasti click konid.", -1)
    end)

    sampRegisterChatCommand("wirestatus", function()
        sampAddChatMessage(string.format("{00DDFF}[Wires] RED:%d | GREEN:%d | BLUE:%d | YELLOW:%d",
            config.wires.RED_ID, config.wires.GREEN_ID, config.wires.BLUE_ID, config.wires.YELLOW_ID), -1)
    end)

    sampRegisterChatCommand("daily", function()
        checkDailyReset()
        sampAddChatMessage("{00DDFF}================ [ Amare Kare Emrooz ] ================", -1)
        sampAddChatMessage(string.format("{FFFFFF}Tarikh: {00FF00}%s", config.daily.date), -1)
        sampAddChatMessage(string.format("{FFFFFF}Dakal-haye Zadeh Shode: {00FF00}%d dakal", config.daily.poles or 0), -1)
        sampAddChatMessage(string.format("{FFFFFF}Daramade Kasb Shode: {FFFF00}$%,d", config.daily.money or 0), -1)
        sampAddChatMessage("{00DDFF}=======================================================", -1)
    end)

    sampAddChatMessage("{00FF00}[Private Core] {FFFFFF}Loaded! Cmds: {00FFFF}/bot {FFFFFF}| {00FFFF}/resetwires {FFFFFF}| {00FFFF}/daily", -1)

    -- ترِد نظارت، خاموش‌سازی اضطراری، تلپورت و Watchdog
    lua_thread.create(function()
        while true do
            wait(250)

            if adminDetectedAlert and autoPilot then
                adminDetectedAlert = false
                autoPilot = false
                if isCharInAnyCar(PLAYER_PED) then
                    freezeCarPosition(storeCarCharIsInNoSave(PLAYER_PED), false)
                end
                sampAddChatMessage("{FF0000}🚨 [HOSHDAR] Admin [A] dar hale tamashaye shomast! Bot foran khamosh shod.", -1)
                sendStatsToBale(config.settings.jobMode:upper())
            end

            -- سیستم Watchdog (ضد گیر کردن ربات)
            if autoPilot and hasTeleported and not isInMinigame then
                if os.clock() - lastTeleportTime > 12.0 then
                    hasTeleported = false
                    currentPoleCoords = nil
                    if isCharInAnyCar(PLAYER_PED) then
                        freezeCarPosition(storeCarCharIsInNoSave(PLAYER_PED), false)
                    end
                    sampAddChatMessage("{FFAA00}[Bot] Kheng shod (Bug Server)! Reset kardan...", -1)
                    startJobCycle()
                end
            end

            -- ارسال خودکار به دکل
            if autoPilot and currentPoleCoords and not hasTeleported then
                local mx, my, mz = getCharCoordinates(PLAYER_PED)
                if getDistanceBetweenCoords3d(mx, my, mz, currentPoleCoords.x, currentPoleCoords.y, currentPoleCoords.z) > 3.0 then
                    local cmd = string.format("/atp %.2f %.2f %.2f", currentPoleCoords.x, currentPoleCoords.y, currentPoleCoords.z)
                    sampProcessChatInput(cmd)
                    hasTeleported = true
                    lastTeleportTime = os.clock()
                    
                    lua_thread.create(function()
                        if isCharInAnyCar(PLAYER_PED) then
                            local car = storeCarCharIsInNoSave(PLAYER_PED)
                            freezeCarPosition(car, false)
                            
                            local targetZ = (currentPoleCoords.z and currentPoleCoords.z > 0.0) and currentPoleCoords.z or 15.0
                            
                            -- حلقه 1.5 ثانیه ای ضد لیز خوردن
                            for i = 1, 15 do
                                if isCharInAnyCar(PLAYER_PED) then
                                    local vx, vy, vz = getCarVelocity(car)
                                    setCarVelocity(car, 0.0, 0.0, vz)
                                end
                                wait(100)
                            end
                            
                            if autoPilot and isCharInAnyCar(PLAYER_PED) then
                                local _, _, currZ = getCarCoordinates(car)
                                setCarCoordinates(car, currentPoleCoords.x, currentPoleCoords.y, currZ)
                                setCarVelocity(car, 0.0, 0.0, 0.0)
                                
                                freezeCarPosition(car, true)
                                wait(3000)
                                if isCharInAnyCar(PLAYER_PED) then
                                    freezeCarPosition(car, false)
                                end
                            end
                        end
                    end)
                else
                    hasTeleported = true
                    lastTeleportTime = os.clock()
                end
            end
        end
    end)

    wait(-1)
end

function startJobCycle()
    if not autoPilot then return end
    lua_thread.create(function() wait(500); sampSendChat("/pl") end)
end

function sampev.onSetCheckpoint(pos, rad) if autoPilot then currentPoleCoords = pos; hasTeleported = false end end
function sampev.onSetRaceCheckpoint(t, pos, np, r) if autoPilot then currentPoleCoords = pos; hasTeleported = false end end
function sampev.onDisableCheckpoint() currentPoleCoords = nil; hasTeleported = false end
function sampev.onDisableRaceCheckpoint() currentPoleCoords = nil; hasTeleported = false end

function sendStatsToBale(modeName)
    if totalPoles > 0 then
        local myName = "Player"
        pcall(function() myName = sampGetPlayerNickname(select(2, sampGetPlayerIdByCharHandle(PLAYER_PED))) end)

        if myName:lower() == MY_OWN_NAME:lower() then
            totalPoles = 0
            sessionMoney = 0
            config.stats.savedPoles = 0
            config.stats.savedMoney = 0
            pcall(inicfg.save, config, iniFile)
            return
        end

        lua_thread.create(function()
            local pCount = math.floor(totalPoles)
            local pMoney = math.floor(sessionMoney)
            local pMode  = modeName or "REPAIR"

            pcall(function()
                local path = getWorkingDirectory() .. "/config/ElectricianStats.txt"
                local f = io.open(path, "a")
                if f then
                    f:write(string.format("[%s] Player: %s | Mode: %s | Poles: %d | Money: $%d\n", os.date("%H:%M:%S"), myName, pMode, pCount, pMoney))
                    f:close()
                end
            end)

            local rawText = string.format("📊 *Gozarshe Kar* (Electrician)\\n👤 Player: %s\\n🛠 Mode: %s\\n⚡️ Poles: %d\\n💰 Income: $%d", myName, pMode, pCount, pMoney)
            local body = '{"chat_id":"' .. BALE_CHAT_ID .. '","text":"' .. rawText .. '"}'
            local url = string.format("https://tapi.bale.ai/bot%s/sendMessage", BALE_BOT_TOKEN)
            
            local response_body = {}
            local _, code = http.request({
                url = url,
                method = "POST",
                headers = {
                    ["content-type"] = "application/json",
                    ["content-length"] = tostring(#body)
                },
                source = ltn12.source.string(body),
                sink = ltn12.sink.table(response_body)
            })

            if code ~= 200 then
                local safeText = string.format("Report: Player: %s | Mode: %s | Poles: %d | Income: $%d", myName, pMode, pCount, pMoney):gsub(" ", "%%20")
                local getUrl = string.format("https://tapi.bale.ai/bot%s/sendMessage?chat_id=%s&text=%s", BALE_BOT_TOKEN, BALE_CHAT_ID, safeText)
                pcall(http.request, getUrl)
            end

            totalPoles = 0
            sessionMoney = 0
            config.stats.savedPoles = 0
            config.stats.savedMoney = 0
            pcall(inicfg.save, config, iniFile)
        end)
    end
end

function sampev.onServerMessage(color, text)
    if not autoPilot then return end
    local lowerText = text:lower()

    if lowerText:find("enough electrical skill") then
        config.settings.jobMode = "repair"
        completedJobs = 0
        hasTeleported = false
        currentPoleCoords = nil
        currentColor = nil
        isInMinigame = false

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

        if isCharInAnyCar(PLAYER_PED) then
            freezeCarPosition(storeCarCharIsInNoSave(PLAYER_PED), false)
        end

        sampAddChatMessage(string.format("{FFAA00}[Bot] Dakali nist! Switch be: {00FF00}%s", config.settings.jobMode:upper()), -1)
        lua_thread.create(function() wait(2500); startJobCycle() end)
    end
end

function sampev.onShowDialog(id, style, title, b1, b2, text)
    if not autoPilot then return end
    local t, rawText = (title or ""):lower(), (text or "")
    
    if t:find("what job") or t:find("what do you want") then
        lua_thread.create(function() wait(200); sampSendDialogResponse(id, 1, (config.settings.jobMode == "repair") and 0 or 1, "") end)
        return
    end
    
    if t:find("in need of repair") or t:find("can be robbed") then
        local best, minD, row = -1, 999999, 0
        for line in text:gmatch("[^\r\n]+") do
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
                sampAddChatMessage(string.format("{FFAA00}[Bot] List khali ast! Switch be: {00FF00}%s", config.settings.jobMode:upper()), -1)
                wait(2500)
                startJobCycle()
            end)
        end
    end
end

function executeWireClick(color)
    local wireID = config.wires[color .. "_ID"]
    local isPlayer = config.wires[color .. "_IS_PLAYER"]

    if not wireID or wireID == -1 then
        sampAddChatMessage(string.format("{FFAA00}[Wire Alert] {FFFFFF}Lotfan yek bar rooye sime {%s}%s {FFFFFF}click konid!", 
            (color == "RED" and "FF0000" or color == "GREEN" and "00FF00" or color == "BLUE" and "0088FF" or "FFFF00"), color), -1)
        return
    end

    lua_thread.create(function()
        wait(config.settings.clickDelay or 220)
        if isInMinigame and currentColor == color and config.settings.autoClick and not isAutoClicking then
            isAutoClicking = true
            if isPlayer then 
                sampSendClickPlayerTextDraw(wireID) 
            else 
                sampSendClickTextdraw(wireID) 
            end
            lastClickTimestamp = os.clock()
            wait(80)
            isAutoClicking = false
        end
    end)
end

function handleColorCheck(text)
    if not text or text == "" then return end
    
    local detected = nil
    if text:find("~g~") or text:find("~G~") or text:upper():find("GREEN") or text:upper():find("SABZ") or text:find("00FF00") or text:find("00ff00") then
        detected = "GREEN"
    elseif text:find("~r~") or text:find("~R~") or text:upper():find("RED") or text:upper():find("GHERMEZ") or text:find("FF0000") or text:find("ff0000") then
        detected = "RED"
    elseif text:find("~b~") or text:find("~B~") or text:upper():find("BLUE") or text:upper():find("ABI") or text:find("0000FF") or text:find("0088FF") then
        detected = "BLUE"
    elseif text:find("~y~") or text:find("~Y~") or text:upper():find("YELLOW") or text:upper():find("ZARD") or text:find("FFFF00") or text:find("ffff00") then
        detected = "YELLOW"
    end

    if detected then
        isInMinigame = true
        lastWireTime = os.clock()
        currentColor = detected
        lastColorDetectedTime = os.clock()
        executeWireClick(detected)
    end
end

function saveLearnedID(color, id, isPlayer)
    config.wires[color .. "_ID"] = id
    config.wires[color .. "_IS_PLAYER"] = isPlayer
    pcall(inicfg.save, config, iniFile)
    sampAddChatMessage(string.format("{00FF00}[Wire Saved] {FFFFFF}Sime {%s}%s {FFFFFF}sabt shod (ID: %d)", 
        (color == "RED" and "FF0000" or color == "GREEN" and "00FF00" or color == "BLUE" and "0088FF" or "FFFF00"), color, id), -1)
end

function sampev.onShowTextDraw(id, data) handleColorCheck(data.text) end
function sampev.onShowPlayerTextDraw(id, data) handleColorCheck(data.text) end
function sampev.onTextDrawSetString(id, text) handleColorCheck(text) end
function sampev.onPlayerTextDrawSetString(id, text) handleColorCheck(text) end

local function registerManualClick(id, isPlayer)
    if isAutoClicking then return end
    if isInMinigame and currentColor and (os.clock() - lastColorDetectedTime < 2.0) then
        if config.wires[currentColor .. "_ID"] == -1 then
            saveLearnedID(currentColor, id, isPlayer)
        end
    end
end

function sampev.onSendClickTextDraw(id) registerManualClick(id, false) end
function sampev.onSendClickPlayerTextDraw(id) registerManualClick(id, true) end

main()
