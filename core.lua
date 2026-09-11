script_name("Private Assistant - Cloud Core")
script_author("Diagnostic")
script_version("210.0.GOOGLE_SUCCESS")

local sampev = require 'samp.events'
local inicfg = require 'inicfg'

local iniFile = "AutoElectrician.ini"
local defaultConfig = {
    wires = { RED_ID = -1, RED_IS_PLAYER = false, GREEN_ID = -1, GREEN_IS_PLAYER = false, BLUE_ID = -1, BLUE_IS_PLAYER = false, YELLOW_ID = -1, YELLOW_IS_PLAYER = false },
    settings = { autoClick = true, jobMode = "repair", clickDelay = 180, isVIP = true },
    stats = { savedPoles = 0, savedMoney = 0 }
}
local config = nil
local status, res = pcall(inicfg.load, defaultConfig, iniFile)
if not status or not res then
    iniFile = "PrivateSettings.ini"
    status, res = pcall(inicfg.load, defaultConfig, iniFile)
end
if status and res then config = res else config = defaultConfig end

local autoPilot = false
local currentPoleCoords = nil
local completedJobs = 0
local sessionMoney = config.stats.savedMoney or 0
local totalPoles = config.stats.savedPoles or 0
local hasTeleported = false

local font = nil
local activeSpectators = {}

local currentColor = nil
local isAutoClicking = false
local isInMinigame = false
local lastWireTime = 0

-- =================================================================
-- تابع اصلی (Main)
-- =================================================================
function main()
    while not isSampAvailable() do wait(100) end
    while not sampIsLocalPlayerSpawned() do wait(200) end

    font = renderCreateFont("Arial", 11, 5)

    sampRegisterChatCommand("bot", function()
        autoPilot = not autoPilot
        sampAddChatMessage(autoPilot and "{00FF00}[Bot] ROSHAN" or "{FF0000}[Bot] KHAMOSH", -1)
        if autoPilot then
            startJobCycle()
        else
            if isCharInAnyCar(PLAYER_PED) then
                freezeCarPosition(storeCarCharIsInNoSave(PLAYER_PED), false)
            end
            sendStatsToGoogle(config.settings.jobMode:upper(), false)
        end
    end)

    sampRegisterChatCommand("unfreeze", function()
        if isCharInAnyCar(PLAYER_PED) then
            local car = storeCarCharIsInNoSave(PLAYER_PED)
            freezeCarPosition(car, false)
            sampAddChatMessage("{00FF00}[Car] Ghofle mashin baz shod.", -1)
        end
    end)

    -- دستور تست فوری ارسال به فرم جدید گوگل
    sampRegisterChatCommand("testform", function()
        sampAddChatMessage("{00DDFF}[Test] Dar hale ersal amare test be Google Form...", -1)
        sendStatsToGoogle("TEST_MANUAL", true)
    end)

    sampAddChatMessage("{00FF00}[Private Core] {FFFFFF}Loaded! Cmds: {00FFFF}/bot {FFFFFF}| {00FFFF}/testform {FFFFFF}| {00FFFF}/unfreeze", -1)

    -- ترِد ۱: رندر ادمین‌ها و اسپکتورها
    lua_thread.create(function()
        while true do
            wait(0)
            if font and sampIsLocalPlayerSpawned() then
                local sw, sh = getScreenResolution()
                
                -- اسپکتور
                local specY = sh / 2
                renderFontDrawText(font, "--- Spectators ---", 10, specY - 18, 0xFF00FFFF)
                local hasSpec = false
                for name, time in pairs(activeSpectators) do
                    if os.clock() - time < 3.0 then 
                        renderFontDrawText(font, ">> " .. name, 10, specY, 0xFFFF0000)
                        specY = specY + 16
                        hasSpec = true
                    else
                        activeSpectators[name] = nil
                    end
                end
                if not hasSpec then renderFontDrawText(font, "None", 10, specY, 0xFF00FF00) end
                
                -- استف آنلاین [A] و [H] (سمت راست)
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

    -- ترِد ۲: فرود هوشمند و تلپورت
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
                            wait(1000)
                            if autoPilot and isCharInAnyCar(PLAYER_PED) then
                                setCarForwardSpeed(car, 0.0)
                                freezeCarPosition(car, true)
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

-- =================================================================
-- چک‌پوینت‌ها و اسپکتور
-- =================================================================
function sampev.onSetCheckpoint(pos, rad) 
    if autoPilot then 
        currentPoleCoords = pos 
        hasTeleported = false 
    end 
end

function sampev.onSetRaceCheckpoint(t, pos, np, r) 
    if autoPilot then 
        currentPoleCoords = pos 
        hasTeleported = false 
    end 
end

function sampev.onDisableCheckpoint() currentPoleCoords = nil; hasTeleported = false end
function sampev.onDisableRaceCheckpoint() currentPoleCoords = nil; hasTeleported = false end

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
                        activeSpectators[specName] = os.clock()
                    end
                end
            end
        end
    end)
end

-- =================================================================
-- ارسال ۱۰۰٪ قطعی به گوگل فرم با لینک کامل و submit=Submit
-- =================================================================
function sendStatsToGoogle(modeName, forceSend)
    if (totalPoles > 0 or forceSend) then
        lua_thread.create(function()
            local req_ok, req = pcall(require, 'requests')
            if not req_ok or not req then
                sampAddChatMessage("{FF0000}[Google Error] Library 'requests' peyda nashod!", -1)
                return
            end

            local myName = "Player"
            pcall(function() myName = sampGetPlayerNickname(select(2, sampGetPlayerIdByCharHandle(PLAYER_PED))) end)
            local encodedName = myName:gsub(" ", "%%20")

            local pCount = math.floor(totalPoles > 0 and totalPoles or 1)
            local pMoney = math.floor(sessionMoney > 0 and sessionMoney or 11700)
            local pMode  = modeName or "REPAIR"

            -- لینک اختصاصی فرم جدید شما با تاییدیه نهایی submit
            local targetUrl = string.format("https://docs.google.com/forms/d/e/1FAIpQLSfpVJWUlEvUzyMx0u_HiDmzsRWgwJsZ3jKdNZQNYOLX-0JCiQ/formResponse?entry.1736615999=%s&entry.1046148207=%s&entry.1890193960=%d&entry.1983979013=%d&submit=Submit",
                encodedName, pMode, pCount, pMoney)

            local ok, response = pcall(req.get, targetUrl)

            if ok and response then
                sampAddChatMessage(string.format("{00FF00}[Google Form] {FFFFFF}Ersal shod! Status: %s", tostring(response.status_code)), -1)
            else
                sampAddChatMessage("{FF0000}[Google Form] {FFFFFF}Khata dar ersal! Internet ra check konid.", -1)
            end
            
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
-- تایید سرور و مدیریت کار
-- =================================================================
function sampev.onServerMessage(color, text)
    if not autoPilot then return end

    local earned = text:match("Earned: %$(%d+)")
    if earned then sessionMoney = tonumber(earned) end

    if text:find("All wires got fixed") or text:find("successfully stole the metal") then
        completedJobs = completedJobs + 1
        totalPoles = totalPoles + 1
        
        if not earned then
            local isRob = (config.settings.jobMode == "rob")
            sessionMoney = sessionMoney + (isRob and (config.settings.isVIP and 21600 or 10800) or (config.settings.isVIP and 23400 or 11700))
        end

        config.stats.savedPoles = totalPoles
        config.stats.savedMoney = sessionMoney
        pcall(inicfg.save, config, iniFile)

        currentPoleCoords = nil
        hasTeleported = false

        if isCharInAnyCar(PLAYER_PED) then
            freezeCarPosition(storeCarCharIsInNoSave(PLAYER_PED), false)
        end

        sampAddChatMessage("[Bot] Dakal sabt shod! (" .. completedJobs .. "/4)", 0x00FF00)

        if completedJobs >= 4 then
            completedJobs = 0
            local prevMode = config.settings.jobMode
            config.settings.jobMode = (prevMode == "repair") and "rob" or "repair"
            sendStatsToGoogle(prevMode:upper(), false)
        end

        lua_thread.create(function() wait(2000); startJobCycle() end)
    end

    if text:find("یافت نشد") or text:find("هیچ") then
        config.settings.jobMode = (config.settings.jobMode == "repair") and "rob" or "repair"
        completedJobs = 0
        hasTeleported = false
        if isCharInAnyCar(PLAYER_PED) then
            freezeCarPosition(storeCarCharIsInNoSave(PLAYER_PED), false)
        end
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
-- حل خودکار مینی‌گیم سیم‌ها
-- =================================================================
function triggerClick(color)
    local wireID = config.wires[color .. "_ID"]
    local isPlayer = config.wires[color .. "_IS_PLAYER"]
    if not wireID or wireID == -1 then return end

    lua_thread.create(function()
        wait(config.settings.clickDelay or 180)
        if currentColor == color and config.settings.autoClick then
            isAutoClicking = true
            if isPlayer then
                sampSendClickPlayerTextDraw(wireID)
            else
                sampSendClickTextdraw(wireID)
            end
            isAutoClicking = false
        end
    end)
end

function handleColorCheck(text)
    local col = detectColorFromText(text)
    if col then
        isInMinigame = true
        lastWireTime = os.clock()
        currentColor = col
        triggerClick(col)
    end
end

function detectColorFromText(text)
    if not text then return nil end
    local clean = text:gsub("{.-}", ""):gsub("~.-~", ""):upper()
    if clean:find("GREEN") or clean:find("SABZ") then return "GREEN"
    elseif clean:find("RED") or clean:find("GHERMEZ") then return "RED"
    elseif clean:find("BLUE") or clean:find("ABI") then return "BLUE"
    elseif clean:find("YELLOW") or clean:find("ZARD") then return "YELLOW" end
    return nil
end

function saveLearnedID(color, id, isPlayer)
    config.wires[color .. "_ID"] = id
    config.wires[color .. "_IS_PLAYER"] = isPlayer
    pcall(inicfg.save, config, iniFile)
    sampAddChatMessage("[Electrician] Saved {" .. (color == "RED" and "FF0000" or color == "GREEN" and "00FF00" or color == "BLUE" and "0088FF" or "FFFF00") .. "}" .. color .. "{FFFFFF}!", -1)
end

function sampev.onShowTextDraw(id, data) handleColorCheck(data.text) end
function sampev.onShowPlayerTextDraw(id, data) handleColorCheck(data.text) end
function sampev.onTextDrawSetString(id, text) handleColorCheck(text) end
function sampev.onPlayerTextDrawSetString(id, text) handleColorCheck(text) end

function sampev.onSendClickTextDraw(id)
    if isAutoClicking or not config.settings.autoClick then return end
    if currentColor and config.wires[currentColor .. "_ID"] == -1 then
        saveLearnedID(currentColor, id, false)
    end
end

function sampev.onSendClickPlayerTextDraw(id)
    if isAutoClicking or not config.settings.autoClick then return end
    if currentColor and config.wires[currentColor .. "_ID"] == -1 then
        saveLearnedID(currentColor, id, true)
    end
end

main()
