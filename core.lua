script_name("Private Assistant - Cloud Core")
script_author("Diagnostic")
script_version("4000.0.SMART_ADMIN_ESCAPE")

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
if config.daily == nil or config.daily.date ~= todayDate then
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

-- اطلاعات ربات بله شما (دقیقاً ست شده)
local BALE_BOT_TOKEN = "1192198839:fHVEOH081y3QF1ppDcurfNwC1Fxs3TGztss"
local BALE_CHAT_ID   = "1804721465"

local font = nil
local activeSpectators = {}

function main()
    while not isSampAvailable() do wait(100) end
    while not sampIsLocalPlayerSpawned() do wait(200) end

    rawset(_G, "SpecNotification", true)
    rawset(_G, "OnlineNotification", true)
    rawset(_G, "AntiPublic", false)

    font = renderCreateFont("Arial", 11, 5)

    -- دستور روشن/خاموش ربات
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

    -- دستور آمار روزانه
    sampRegisterChatCommand("daily", function()
        local today = os.date("%Y-%m-%d")
        if config.daily.date ~= today then
            sampAddChatMessage("{00DDFF}[Daily Stats] {FFFFFF}Shoma emrooz hich dakali nazadid!", -1)
        else
            sampAddChatMessage(string.format("{00DDFF}[Daily Stats] {FFFFFF}Emrooz: {00FF00}%d Dakal {FFFFFF}| Daramad: {FFFF00}$%d", config.daily.poles, config.daily.money), -1)
        end
    end)

    sampAddChatMessage("{00FF00}[Private Core] {FFFFFF}Loaded! Cmd: {00FFFF}/bot {FFFFFF}| {00FFFF}/daily", -1)

    -- ترِد رندر اسپکتورها و ادمین‌ها
    lua_thread.create(function()
        while true do
            wait(0)
            if font and sampIsLocalPlayerSpawned() then
                local sw, sh = getScreenResolution()
                
                -- سمت چپ (فقط ادمین‌های اسپکتور)
                local specY = sh / 2
                renderFontDrawText(font, "--- Spectators ---", 10, specY - 18, 0xFF00FFFF)
                local hasSpec = false
                for name, time in pairs(activeSpectators) do
                    if os.clock() - time < 3.0 then 
                        renderFontDrawText(font, "⚠️ " .. name, 10, specY, 0xFFFF0000)
                        specY = specY + 16
                        hasSpec = true
                    else
                        activeSpectators[name] = nil
                    end
                end
                if not hasSpec then renderFontDrawText(font, "None", 10, specY, 0xFF00FF00) end
                
                -- سمت راست (ادمین‌های آنلاین)
                local yOffset = sh / 3
                renderFontDrawText(font, "--- Staff Online ---", sw - 170, yOffset, 0xFFFFAA00)
                yOffset = yOffset + 18
                local foundStaff = false
                for i = 0, sampGetMaxPlayerId(true) do
                    if sampIsPlayerConnected(i) then
                        local name = sampGetPlayerNickname(i)
                        if name and type(name) == "string" then
                            if name:find("%[A%]") or name:find("%[H%]") or name:find("Admin") then
                                renderFontDrawText(font, name .. " ["..i.."]", sw - 170, yOffset, 0xFFFF0000)
                                yOffset = yOffset + 16
                                foundStaff = true
                            end
                        end
                    end
                end
                if not foundStaff then renderFontDrawText(font, "Safe", sw - 170, yOffset, 0xFF00FF00) end
            end
        end
    end)

    -- ترِد تلپورت خودکار
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
                            wait(1500)
                            if autoPilot and isCharInAnyCar(PLAYER_PED) then
                                setCarForwardSpeed(car, 0.0)
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

function sampev.onSetCheckpoint(pos, rad) 
    if autoPilot then currentPoleCoords = pos; hasTeleported = false end 
end
function sampev.onSetRaceCheckpoint(t, pos, np, r) 
    if autoPilot then currentPoleCoords = pos; hasTeleported = false end 
end
function sampev.onDisableCheckpoint() currentPoleCoords = nil; hasTeleported = false end
function sampev.onDisableRaceCheckpoint() currentPoleCoords = nil; hasTeleported = false end

-- =================================================================
-- سیستم ترمز اضطراری فیلتر شده (فقط برای ادمین‌ها و هلپرها)
-- =================================================================
function sampev.onPlayerSync(playerId, data)
    if not sampIsLocalPlayerSpawned() then return end
    pcall(function()
        if sampIsPlayerConnected(playerId) then
            local mx, my, mz = getCharCoordinates(PLAYER_PED)
            local dist = getDistanceBetweenCoords3d(mx, my, mz, data.position.x, data.position.y, data.position.z)
            if dist < 2.0 then
                local hasPed, pedHandle = sampGetCharHandleBySampPlayerId(playerId)
                if not hasPed or (hasPed and doesCharExist(pedHandle) and not isCharOnScreen(pedHandle)) then
                    local specName = sampGetPlayerNickname(playerId)
                    if specName and specName ~= "" then
                        
                        -- فیلتر طلایی: آیا این شخص ادمین، هلپر یا ادمین پنهان است؟
                        if specName:find("%[A%]") or specName:find("%[H%]") or specName:find("Admin") then
                            activeSpectators[specName] = os.clock()
                            
                            -- ترمز دستی ربات فقط و فقط در صورتی کشیده می‌شود که شخص تگ [A] یا [H] داشته باشد!
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
-- ارسال آمار به پیام‌رسان بله
-- =================================================================
function sendStatsToBale(modeName, forceSend)
    if totalPoles > 0 or forceSend then
        lua_thread.create(function()
            local myName = "Player"
            pcall(function() myName = sampGetPlayerNickname(select(2, sampGetPlayerIdByCharHandle(PLAYER_PED))) end)
            
            local pCount = math.floor(totalPoles)
            local pMoney = math.floor(sessionMoney)
            local pMode  = modeName or "REPAIR"

            local rawText = string.format("📊 *Gozarshe Kar* (Electrician)\\n👤 Player: %s\\n🛠 Mode: %s\\n⚡️ Poles: %d\\n💰 Income: $%d", myName, pMode, pCount, pMoney)
            local body = '{"chat_id":"' .. BALE_CHAT_ID .. '","text":"' .. rawText .. '"}'
            local url = string.format("https://tapi.bale.ai/bot%s/sendMessage", BALE_BOT_TOKEN)
            
            local response_body = {}
            pcall(function()
                http.request({
                    url = url,
                    method = "POST",
                    headers = { ["content-type"] = "application/json", ["content-length"] = tostring(#body) },
                    source = ltn12.source.string(body),
                    sink = ltn12.sink.table(response_body)
                })
            end)

            if not forceSend then
                totalPoles = 0
                sessionMoney = 0
                config.stats.savedPoles = 0
                config.stats.savedMoney = 0
                pcall(inicfg.save, config, iniFile)
            end
        end)
    end
end

-- =================================================================
-- پایان دکل و ثبت در آمار روزانه و کلی
-- =================================================================
function sampev.onServerMessage(color, text)
    if not autoPilot then return end

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

        -- بروزرسانی آمار روزانه (/daily)
        local tDate = os.date("%Y-%m-%d")
        if config.daily.date ~= tDate then
            config.daily.date = tDate
            config.daily.poles = 0
            config.daily.money = 0
        end
        config.daily.poles = config.daily.poles + 1
        config.daily.money = config.daily.money + earnedThisPole

        config.stats.savedPoles = totalPoles
        config.stats.savedMoney = sessionMoney
        pcall(inicfg.save, config, iniFile)

        currentPoleCoords = nil
        hasTeleported = false

        sampAddChatMessage("[Bot] Dakal sabt shod! (" .. completedJobs .. "/4)", 0x00FF00)

        if completedJobs >= 4 then
            completedJobs = 0
            local prevMode = config.settings.jobMode
            config.settings.jobMode = (prevMode == "repair") and "rob" or "repair"
            sendStatsToBale(prevMode:upper(), false)
        end

        lua_thread.create(function() wait(2000); startJobCycle() end)
    end

    if text:find("یافت نشد") or text:find("هیچ") then
        config.settings.jobMode = (config.settings.jobMode == "repair") and "rob" or "repair"
        completedJobs = 0
        hasTeleported = false
        lua_thread.create(function() wait(2000); startJobCycle() end)
    end
end

-- =================================================================
-- دیالوگ‌ها
-- =================================================================
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
        if best ~= -1 then lua_thread.create(function() wait(200); sampSendDialogResponse(id, 1, best, "") end) end
    end
end

-- =================================================================
-- مینی‌گیم سیم‌ها
-- =================================================================
function triggerClick(color)
    local wireID = config.wires[color .. "_ID"]
    if not wireID or wireID == -1 then return end
    local isPlayer = config.wires[color .. "_IS_PLAYER"]
    
    lua_thread.create(function()
        wait(config.settings.clickDelay or 180)
        if isPlayer then sampSendClickPlayerTextDraw(wireID) else sampSendClickTextdraw(wireID) end
    end)
end

function handleColorCheck(text)
    local col = (text or ""):gsub("{.-}", ""):upper()
    local c = col:find("GREEN") and "GREEN" or col:find("RED") and "RED" or col:find("BLUE") and "BLUE" or col:find("YELLOW") and "YELLOW"
    if c then triggerClick(c) end
end

function sampev.onShowTextDraw(id, data) handleColorCheck(data.text)
    if config.wires["RED_ID"] == -1 then config.wires["RED_ID"]=id; config.wires["RED_IS_PLAYER"]=false; pcall(inicfg.save, config, iniFile) end
end
function sampev.onShowPlayerTextDraw(id, data) handleColorCheck(data.text) end
function sampev.onTextDrawSetString(id, text) handleColorCheck(text) end
function sampev.onPlayerTextDrawSetString(id, text) handleColorCheck(text) end
function sampev.onSendClickTextDraw(id)
    if not autoPilot then return end
    if config.wires["RED_ID"] == -1 then config.wires["RED_ID"]=id; config.wires["RED_IS_PLAYER"]=false; pcall(inicfg.save, config, iniFile) end
end
function sampev.onSendClickPlayerTextDraw(id)
    if not autoPilot then return end
    if config.wires["RED_ID"] == -1 then config.wires["RED_ID"]=id; config.wires["RED_IS_PLAYER"]=true; pcall(inicfg.save, config, iniFile) end
end

main()
