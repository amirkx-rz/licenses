script_name("Private Assistant - Cloud Core")
script_author("Diagnostic")
script_version("FINAL_STABLE_EDITION")

local sampev = require 'samp.events'
local inicfg = require 'inicfg'
local http = require 'socket.http'
local ltn12 = require 'ltn12'

local iniFile = "AutoElectrician.ini"
local defaultConfig = {
    wires = { RED_ID = -1, RED_IS_PLAYER = false, GREEN_ID = -1, GREEN_IS_PLAYER = false, BLUE_ID = -1, BLUE_IS_PLAYER = false, YELLOW_ID = -1, YELLOW_IS_PLAYER = false },
    settings = { autoClick = true, jobMode = "repair", clickDelay = 180, isVIP = true },
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

-- آپدیت تاریخ روزانه
local todayDate = os.date("%Y-%m-%d")
if not config.daily or config.daily.date ~= todayDate then
    config.daily = { date = todayDate, poles = 0, money = 0 }
    pcall(inicfg.save, config, iniFile)
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
local hasLowSkill = false

-- اطلاعات ربات بله
local BALE_BOT_TOKEN = "1192198839:fHVEOH081y3QF1ppDcurfNwC1Fxs3TGztss"
local BALE_CHAT_ID   = "ADAD_CHAT_ID_RA_INJA_BEGOZAR" -- <<<< عدد چت آیدی خودت را بگذار

-- =================================================================
-- تابع اصلی (Main)
-- =================================================================
function main()
    while not isSampAvailable() do wait(100) end
    while not sampIsLocalPlayerSpawned() do wait(200) end

    sampRegisterChatCommand("bot", function()
        autoPilot = not autoPilot
        sampAddChatMessage(autoPilot and "{00FF00}[Bot] ROSHAN" or "{FF0000}[Bot] KHAMOSH", -1)
        if autoPilot then
            startJobCycle()
        else
            if isCharInAnyCar(PLAYER_PED) then
                freezeCarPosition(storeCarCharIsInNoSave(PLAYER_PED), false)
            end
            sendStatsToBale(config.settings.jobMode:upper(), false)
        end
    end)

    sampRegisterChatCommand("daily", function()
        local today = os.date("%Y-%m-%d")
        if not config.daily or config.daily.date ~= today then
            sampAddChatMessage("{00DDFF}[Daily Stats] {FFFFFF}Shoma emrooz hich dakali nazadid!", -1)
        else
            sampAddChatMessage(string.format("{00DDFF}[Daily Stats] {FFFFFF}Emrooz: {00FF00}%d Dakal {FFFFFF}| Daramad: {FFFF00}$%d", config.daily.poles, config.daily.money), -1)
        end
    end)

    sampRegisterChatCommand("unfreeze", function()
        if isCharInAnyCar(PLAYER_PED) then
            freezeCarPosition(storeCarCharIsInNoSave(PLAYER_PED), false)
            sampAddChatMessage("{00FF00}[Car] Ghofle mashin baz shod.", -1)
        end
    end)

    sampRegisterChatCommand("resetwires", function()
        config.wires.RED_ID = -1; config.wires.GREEN_ID = -1; config.wires.BLUE_ID = -1; config.wires.YELLOW_ID = -1
        pcall(inicfg.save, config, iniFile)
        sampAddChatMessage("{00FF00}[Wires] Hafeze pak shod! Yekbar dasti click konid.", -1)
    end)

    sampAddChatMessage("{00FF00}[Private Core] {FFFFFF}Loaded! Cmds: {00FFFF}/bot {FFFFFF}| {00FFFF}/daily {FFFFFF}| {00FFFF}/resetwires", -1)

    -- ترِد تلپورت خودکار با فرمول فریز درخواستی
    lua_thread.create(function()
        while true do
            wait(250)
            if autoPilot and currentPoleCoords and not hasTeleported then
                local mx, my, mz = getCharCoordinates(PLAYER_PED)
                if getDistanceBetweenCoords3d(mx, my, mz, currentPoleCoords.x, currentPoleCoords.y, currentPoleCoords.z) > 3.0 then
                    local cmd = string.format("/atp %.2f %.2f %.2f", currentPoleCoords.x, currentPoleCoords.y, currentPoleCoords.z)
                    sampProcessChatInput(cmd)
                    hasTeleported = true
                    
                    lua_thread.create(function()
                        if isCharInAnyCar(PLAYER_PED) then
                            local car = storeCarCharIsInNoSave(PLAYER_PED)
                            freezeCarPosition(car, false)
                            setCarForwardSpeed(car, 0.0)
                            
                            wait(1500) -- مهلت نشستن روی زمین
                            
                            if autoPilot and isCharInAnyCar(PLAYER_PED) then
                                setCarForwardSpeed(car, 0.0)
                                freezeCarPosition(car, true)
                                wait(3000) -- فریز ایمن
                                if isCharInAnyCar(PLAYER_PED) then
                                    freezeCarPosition(car, false)
                                end
                            end
                        end
                    end)
                else
                    hasTeleported = true
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

-- =================================================================
-- رادار مخفی ادمین (توقف اضطراری)
-- =================================================================
function sampev.onPlayerSync(playerId, data)
    if not sampIsLocalPlayerSpawned() then return end
    pcall(function()
        if sampIsPlayerConnected(playerId) then
            local mx, my, mz = getCharCoordinates(PLAYER_PED)
            local dist = getDistanceBetweenCoords3d(mx, my, mz, data.position.x, data.position.y, data.position.z)
            
            if dist < 30.0 then
                local hasPed, pedHandle = sampGetCharHandleBySampPlayerId(playerId)
                if not hasPed or (hasPed and doesCharExist(pedHandle) and not isCharOnScreen(pedHandle)) then
                    local specName = sampGetPlayerNickname(playerId)
                    if specName and specName ~= "" then
                        -- فقط در صورتی که ادمین/هلپر باشد
                        if specName:find("%[A%]") or specName:find("%[H%]") or specName:find("Admin") then
                            if autoPilot then
                                autoPilot = false
                                if isCharInAnyCar(PLAYER_PED) then
                                    freezeCarPosition(storeCarCharIsInNoSave(PLAYER_PED), false)
                                end
                                sampAddChatMessage("{FF0000}⚠️ [DANGER] {FFFFFF}Admin/Helper (" .. specName .. ") dar hale spectate ast! Bot KHAMOSH shod.", -1)
                                sendStatsToBale("EMERGENCY_STOP", true)
                            end
                        end
                    end
                end
            end
        end
    end)
end

-- =================================================================
-- ارسال آمار به بله
-- =================================================================
function sendStatsToBale(modeName, forceSend)
    if totalPoles > 0 or forceSend then
        lua_thread.create(function()
            local myName = "Player"
            pcall(function() myName = sampGetPlayerNickname(select(2, sampGetPlayerIdByCharHandle(PLAYER_PED))) end)
            
            local pCount = math.floor(totalPoles)
            local pMoney = math.floor(sessionMoney)
            local pMode  = modeName or "REPAIR"

            pcall(function()
                local path = getWorkingDirectory() .. "/config/ElectricianStats.txt"
                local f = io.open(path, "a")
                if f then f:write(string.format("[%s] Player: %s | Mode: %s | Poles: %d | Money: $%d\n", os.date("%H:%M:%S"), myName, pMode, pCount, pMoney)); f:close() end
            end)

            local rawText = string.format("📊 *Gozarshe Kar* (Electrician)\\n👤 Player: %s\\n🛠 Mode: %s\\n⚡️ Poles: %d\\n💰 Income: $%d", myName, pMode, pCount, pMoney)
            local body = '{"chat_id":"' .. BALE_CHAT_ID .. '","text":"' .. rawText .. '"}'
            local url = string.format("https://tapi.bale.ai/bot%s/sendMessage", BALE_BOT_TOKEN)
            
            local response_body = {}
            pcall(function()
                http.request({
                    url = url, method = "POST",
                    headers = { ["content-type"] = "application/json", ["content-length"] = tostring(#body) },
                    source = ltn12.source.string(body), sink = ltn12.sink.table(response_body)
                })
            end)

            if not forceSend then
                totalPoles = 0; sessionMoney = 0; config.stats.savedPoles = 0; config.stats.savedMoney = 0
                pcall(inicfg.save, config, iniFile)
            end
        end)
    end
end

-- =================================================================
-- خواندن سرور و دیالوگ‌ها
-- =================================================================
function sampev.onServerMessage(color, text)
    if not autoPilot then return end
    local lowerText = text:lower()

    if lowerText:find("enough electrical skill") then
        hasLowSkill = true
        config.settings.jobMode = "repair"
        completedJobs = 0; hasTeleported = false; currentPoleCoords = nil; currentColor = nil; isInMinigame = false
        if isCharInAnyCar(PLAYER_PED) then freezeCarPosition(storeCarCharIsInNoSave(PLAYER_PED), false) end
        sampAddChatMessage("{FFAA00}[Bot] Skill paeen ast! Mode rooye REPAIR ghofl shod.", -1)
        lua_thread.create(function() wait(12000); startJobCycle() end)
        return
    end

    local earned = text:match("Earned: %$(%d+)")
    if earned then sessionMoney = tonumber(earned) end

    if text:find("All wires got fixed successfully") or text:find("successfully stole the metal in this station") then
        completedJobs = completedJobs + 1
        totalPoles = totalPoles + 1
        
        local earnedThisPole = 0
        if not earned then
            local isRob = (config.settings.jobMode == "rob")
            local isVipActive = (_G.REMOTE_IS_VIP == true)
            earnedThisPole = (isRob and (isVipActive and 21600 or 10800) or (isVipActive and 23400 or 11700))
            sessionMoney = sessionMoney + earnedThisPole
        else
            earnedThisPole = tonumber(earned)
        end

        local tDate = os.date("%Y-%m-%d")
        if not config.daily or config.daily.date ~= tDate then 
            config.daily = {date = tDate, poles = 0, money = 0}
        end
        config.daily.poles = config.daily.poles + 1
        config.daily.money = config.daily.money + earnedThisPole

        config.stats.savedPoles = totalPoles
        config.stats.savedMoney = sessionMoney
        pcall(inicfg.save, config, iniFile)

        currentPoleCoords = nil
        hasTeleported = false
        currentColor = nil
        isInMinigame = false

        if isCharInAnyCar(PLAYER_PED) then freezeCarPosition(storeCarCharIsInNoSave(PLAYER_PED), false) end

        sampAddChatMessage("[Bot] Dakal sabt shod! (" .. completedJobs .. "/4)", 0x00FF00)

        if completedJobs >= 4 then
            completedJobs = 0
            local prevMode = config.settings.jobMode
            if hasLowSkill then
                config.settings.jobMode = "repair"
                sendStatsToBale("REPAIR", false)
                sampAddChatMessage("{FFAA00}[Bot] Sabr baraye raf'e cooldown...", -1)
                lua_thread.create(function() wait(12000); startJobCycle() end)
            else
                config.settings.jobMode = (prevMode == "repair") and "rob" or "repair"
                sendStatsToBale(prevMode:upper(), false)
                lua_thread.create(function() wait(2000); startJobCycle() end)
            end
        else
            lua_thread.create(function() wait(2000); startJobCycle() end)
        end
        return
    end

    if lowerText:find("nothing found") or lowerText:find("not found") or text:find("یافت نشد") or text:find("هیچ") then
        completedJobs = 0
        hasTeleported = false
        currentPoleCoords = nil
        currentColor = nil
        isInMinigame = false

        if isCharInAnyCar(PLAYER_PED) then freezeCarPosition(storeCarCharIsInNoSave(PLAYER_PED), false) end

        if hasLowSkill then
            config.settings.jobMode = "repair"
            sampAddChatMessage("{FFAA00}[Bot] Dakali nist! Sabr baraye cooldown...", -1)
            lua_thread.create(function() wait(12000); startJobCycle() end)
        else
            local prevMode = config.settings.jobMode
            config.settings.jobMode = (prevMode == "repair") and "rob" or "repair"
            sampAddChatMessage(string.format("{FFAA00}[Bot] Dakali nist! Switch be: {00FF00}%s", config.settings.jobMode:upper()), -1)
            lua_thread.create(function() wait(2500); startJobCycle() end)
        end
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
            lua_thread.create(function() wait(200); sampSendDialogResponse(id, 0, 0, "")
                if hasLowSkill then
                    config.settings.jobMode = "repair"
                    completedJobs = 0
                    sampAddChatMessage("[Electrician] Dakali nist! Sabr baraye cooldown...", -1)
                    wait(12000)
                else
                    local oldMode = config.settings.jobMode
                    config.settings.jobMode = (oldMode == "repair") and "rob" or "repair"
                    completedJobs = 0
                    sampAddChatMessage("[Electrician] List khali! Switch shod be: {00FF00}" .. config.settings.jobMode:upper(), -1)
                    wait(1800)
                end
                if autoPilot then startJobCycle() end
            end)
        end
    end
end

-- =================================================================
-- مینی‌گیم سیم‌ها
-- =================================================================
function triggerClick(color)
    local wireID = config.wires[color .. "_ID"]
    local isPlayer = config.wires[color .. "_IS_PLAYER"]
    if not wireID or wireID == -1 then return end

    lua_thread.create(function()
        wait(config.settings.clickDelay or 220)
        if isInMinigame and currentColor == color and config.settings.autoClick and not isAutoClicking then
            isAutoClicking = true
            if isPlayer then sampSendClickPlayerTextDraw(wireID) else sampSendClickTextdraw(wireID) end
            lastClickTimestamp = os.clock()
            wait(80)
            isAutoClicking = false
        end
    end)
end

function handleColorCheck(text)
    if not text or text == "" then return end
    local detected = nil
    if text:find("~g~") or text:find("~G~") or text:upper():find("GREEN") or text:upper():find("SABZ") or text:find("00FF00") or text:find("00ff00") then detected = "GREEN"
    elseif text:find("~r~") or text:find("~R~") or text:upper():find("RED") or text:upper():find("GHERMEZ") or text:find("FF0000") or text:find("ff0000") then detected = "RED"
    elseif text:find("~b~") or text:find("~B~") or text:upper():find("BLUE") or text:upper():find("ABI") or text:find("0000FF") or text:find("0088FF") then detected = "BLUE"
    elseif text:find("~y~") or text:find("~Y~") or text:upper():find("YELLOW") or text:upper():find("ZARD") or text:find("FFFF00") or text:find("ffff00") then detected = "YELLOW" end

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
    sampAddChatMessage(string.format("{00FF00}[Wire] {FFFFFF}Sime {%s}%s {FFFFFF}sabt shod (ID: %d)", 
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
