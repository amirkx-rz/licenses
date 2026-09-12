script_name("Private Assistant - Cloud Core")
script_author("Diagnostic")
script_version("1005.0.NOTHING_FOUND_SWITCH")

local sampev = require 'samp.events'
local inicfg = require 'inicfg'
local http = require 'socket.http'
local ltn12 = require 'ltn12'

local iniFile = "AutoElectrician.ini"
local defaultConfig = {
    wires = { RED_ID = -1, RED_IS_PLAYER = false, GREEN_ID = -1, GREEN_IS_PLAYER = false, BLUE_ID = -1, BLUE_IS_PLAYER = false, YELLOW_ID = -1, YELLOW_IS_PLAYER = false },
    settings = { autoClick = true, jobMode = "repair", clickDelay = 180 },
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

local currentColor = nil
local isAutoClicking = false
local isInMinigame = false
local lastWireTime = 0

-- اطلاعات اختصاصی ربات بله شما
local BALE_BOT_TOKEN = "1192198839:fHVEOH081y3QF1ppDcurfNwC1Fxs3TGztss"
local BALE_CHAT_ID   = "1804721465"

-- =================================================================
-- تابع اصلی (Main)
-- =================================================================
function main()
    while not isSampAvailable() do wait(100) end
    while not sampIsLocalPlayerSpawned() do wait(200) end

    -- صدور مجوز امنیتی برای نمایش ویجت‌های فابریک آرت در ADDONS.lua
    pcall(function()
        local f = io.open(getWorkingDirectory() .. "/config/.lic_handshake", "w")
        if f then
            f:write("AUTH_VALID_" .. os.date("%Y%m%d"))
            f:close()
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

    sampAddChatMessage("{00FF00}[Private Core] {FFFFFF}Loaded! Cmd: {00FFFF}/bot", -1)

    -- ترِد نظارت خودکار و فرود هوشمند (1.5 ثانیه فرود + 3 ثانیه فریز)
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
                            
                            -- ۱.۵ ثانیه مهلت برای نشستن چرخ‌ها روی زمین
                            wait(1500)
                            
                            if autoPilot and isCharInAnyCar(PLAYER_PED) then
                                setCarForwardSpeed(car, 0.0)
                                -- ۳ ثانیه فریز کامل روی دکل
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

-- =================================================================
-- ثبت چک‌پوینت‌ها
-- =================================================================
function sampev.onSetCheckpoint(pos, rad) 
    if autoPilot then currentPoleCoords = pos; hasTeleported = false end 
end

function sampev.onSetRaceCheckpoint(t, pos, np, r) 
    if autoPilot then currentPoleCoords = pos; hasTeleported = false end 
end

function sampev.onDisableCheckpoint() currentPoleCoords = nil; hasTeleported = false end
function sampev.onDisableRaceCheckpoint() currentPoleCoords = nil; hasTeleported = false end

-- =================================================================
-- ارسال آمار به پیام‌رسان بله
-- =================================================================
function sendStatsToBale(modeName)
    if totalPoles > 0 then
        lua_thread.create(function()
            local myName = "Player"
            pcall(function() myName = sampGetPlayerNickname(select(2, sampGetPlayerIdByCharHandle(PLAYER_PED))) end)
            
            local pCount = math.floor(totalPoles)
            local pMoney = math.floor(sessionMoney)
            local pMode  = modeName or "REPAIR"

            -- ذخیره نسخه پشتیبان در فایل متنی
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
                local _, getCode = http.request(getUrl)
                code = getCode or code
            end

            if code == 200 then
                sampAddChatMessage("{00FF00}[Bale] {FFFFFF}Amar ba movafaghiyat be Bale ersal shod!", -1)
            end

            totalPoles = 0
            sessionMoney = 0
            config.stats.savedPoles = 0
            config.stats.savedMoney = 0
            pcall(inicfg.save, config, iniFile)
        end)
    end
end

-- =================================================================
-- خواندن پیام‌های سرور و سوئیچ هوشمند در صورت دریافت Nothing found
-- =================================================================
function sampev.onServerMessage(color, text)
    if not autoPilot then return end
    local lowerText = text:lower()

    local earned = text:match("Earned: %$(%d+)")
    if earned then sessionMoney = tonumber(earned) end

    -- ۱. ثبت موفق دکل
    if text:find("All wires got fixed successfully") or text:find("successfully stole the metal in this station") then
        completedJobs = completedJobs + 1
        totalPoles = totalPoles + 1
        
        if not earned then
            local isRob = (config.settings.jobMode == "rob")
            local isVipActive = (_G.REMOTE_IS_VIP == true)
            sessionMoney = sessionMoney + (isRob and (isVipActive and 21600 or 10800) or (isVipActive and 23400 or 11700))
        end

        config.stats.savedPoles = totalPoles
        config.stats.savedMoney = sessionMoney
        pcall(inicfg.save, config, iniFile)

        currentPoleCoords = nil
        hasTeleported = false

        sampAddChatMessage("[Bot] Dakal sabt shod! (" .. completedJobs .. "/4)", 0x00FF00)

        -- بعد از ۴ دکل مود عوض می‌شود
        if completedJobs >= 4 then
            completedJobs = 0
            local prevMode = config.settings.jobMode
            config.settings.jobMode = (prevMode == "repair") and "rob" or "repair"
            sendStatsToBale(prevMode:upper())
        end

        lua_thread.create(function() wait(2000); startJobCycle() end)
        return
    end

    -- ۲. سوئیچ فوری در صورت عدم وجود دکل (Nothing found)
    if lowerText:find("nothing found") or lowerText:find("not found") or text:find("یافت نشد") or text:find("هیچ") then
        local prevMode = config.settings.jobMode
        config.settings.jobMode = (prevMode == "repair") and "rob" or "repair"
        completedJobs = 0
        hasTeleported = false
        currentPoleCoords = nil

        if isCharInAnyCar(PLAYER_PED) then
            freezeCarPosition(storeCarCharIsInNoSave(PLAYER_PED), false)
        end

        sampAddChatMessage(string.format("{FFAA00}[Bot] Dakali peyda nashod! Taghir mode be: {00FF00}%s", config.settings.jobMode:upper()), -1)
        lua_thread.create(function() 
            wait(2500) 
            startJobCycle() 
        end)
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
        
        if best ~= -1 then 
            lua_thread.create(function() wait(200); sampSendDialogResponse(id, 1, best, "") end) 
        else
            -- اگر لیست خالی بود، دیالوگ را ببند و سوئیچ کن
            lua_thread.create(function()
                wait(200)
                sampSendDialogResponse(id, 0, 0, "")
                local prevMode = config.settings.jobMode
                config.settings.jobMode = (prevMode == "repair") and "rob" or "repair"
                completedJobs = 0
                hasTeleported = false
                currentPoleCoords = nil
                sampAddChatMessage(string.format("{FFAA00}[Bot] Liste dakal-ha khali ast! Taghir mode be: {00FF00}%s", config.settings.jobMode:upper()), -1)
                wait(2500)
                startJobCycle()
            end)
        end
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
    local col = detectColorFromText(text)
    if col then
        isInMinigame = true
        lastWireTime = os.clock()
        currentColor = col
        triggerClick(col)
    end
end

function cleanText(text)
    if not text then return "" end
    return text:gsub("{.-}", ""):gsub("~.-~", ""):upper()
end

function detectColorFromText(text)
    text = cleanText(text)
    if text:find("GREEN") then return "GREEN"
    elseif text:find("RED") then return "RED"
    elseif text:find("BLUE") then return "BLUE"
    elseif text:find("YELLOW") then return "YELLOW" end
    return nil
end

function saveLearnedID(color, id, isPlayer)
    config.wires[color .. "_ID"] = id
    config.wires[color .. "_IS_PLAYER"] = isPlayer
    pcall(inicfg.save, config, iniFile)
    sampAddChatMessage(string.format("[Electrician] Saved {" .. (color == "RED" and "FF0000" or color == "GREEN" and "00FF00" or color == "BLUE" and "0088FF" or "FFFF00") .. "}%s {FFFFFF}!", color), -1)
end

function sampev.onShowTextDraw(id, data) handleColorCheck(data.text) end
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
