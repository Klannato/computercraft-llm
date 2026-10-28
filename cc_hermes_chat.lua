-- cc_hermes_chat.lua
-- Hermes-style chat client for ComputerCraft (terminal computer -> turtle via rednet).
-- Keeps multi-turn conversation, calls an OpenAI-compatible LLM, optionally
-- executes ```lua blocks on the connected turtle.
--
-- Usage:
--   cc_hermes_chat                -- opens chat on this computer; no turtle required
--   cc_hermes_chat <ch>           -- also connect to turtle on channel <ch>
--   cc_hermes_chat <ch> ollama    -- use local Ollama instead of gateway
--
-- In-chat commands:
--   /help        show commands
--   /clear       clear conversation history
--   /status      ping turtle
--   /exec <code> run code on turtle directly
--   /quit        exit

local args = {...}
local channel = tonumber(args[1])
local backend = args[2] or "gateway"

settings.define("hermes.base_url", {description="LLM base URL", default="https://openrouter.ai/api/v1", type="string"})
settings.define("hermes.model",     {description="LLM model id", default="meta-llama/llama-3.1-8b-instruct:free", type="string"})
settings.define("hermes.api_key",   {description="API key", default="", type="string"})
settings.define("hermes.system",    {description="System prompt", default="You are Hermes, a helpful assistant running inside a ComputerCraft turtle terminal. Be concise. When the user asks you to do something physical with the turtle, reply with a short explanation followed by a single ```lua ... ``` block containing executable ComputerCraft Lua. Only use turtle.*, print, sleep, math, string, table, os, shell.run. Never use load/loadstring/dofile/loadfile.", type="string"})
settings.save()

local BASE_URL = settings.get("hermes.base_url")
local MODEL     = settings.get("hermes.model")
local API_KEY   = settings.get("hermes.api_key")
local SYSTEM    = settings.get("hermes.system")

-- Auto-load API key from disk if not in settings (file: apikey.txt on this computer)
if (not API_KEY or API_KEY == "") and fs.exists("apikey.txt") then
    local f = fs.open("apikey.txt", "r")
    if f then
        API_KEY = f.readAll():gsub("%s+", "")
        f.close()
        settings.set("hermes.api_key", API_KEY)
        settings.save()
    end
end

if backend == "ollama" then
    BASE_URL = "http://localhost:11434/v1"
    MODEL = "qwen2.5"
    API_KEY = ""
end

local modem = peripheral.find("modem")
if not modem then error("No modem attached. Attach a wireless modem.") end
rednet.open(peripheral.getName(modem))

local function jstr(s)
    s = tostring(s)
    s = s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
    return '"' .. s .. '"'
end

local function http_post_json(url, body, headers)
    headers = headers or {}
    headers["Content-Type"] = "application/json"
    if API_KEY ~= "" then headers["Authorization"] = "Bearer " .. API_KEY end
local resp, err = http.post(url, body, headers)
if not resp then return nil, err or "no response" end
    local text = resp.readAll(); resp.close()
    return text
end

local function llm_chat(messages)
    local url = BASE_URL .. "/chat/completions"
    local parts = {}
    for _, m in ipairs(messages) do
        parts[#parts+1] = '{"role":' .. jstr(m.role) .. ',"content":' .. jstr(m.content) .. '}'
    end
    local body = '{"model":' .. jstr(MODEL) .. ',"messages":[' .. table.concat(parts, ",") .. '],"stream":false}'
    local text, err = http_post_json(url, body)
    if not text then return nil, err end
    local content = text:match('"content"%s*:%s*"(.-)"%s*[,}]')
    if not content then return nil, "parse fail: " .. text:sub(1,200) end
    content = content:gsub("\\n", "\n"):gsub("\\t", "\t"):gsub('\\"', '"'):gsub("\\\\", "\\")
    return content
end

local function extract_code(s)
    local out = {}
    for block in s:gmatch("```[a-zA-Z]*%s*(.-)```") do
        out[#out+1] = block
    end
    return out
end

local turtleId = nil
local PROTO = "hermes-cc"

local function ping(ch)
    rednet.send(ch, {action="ping"}, PROTO)
    local id, msg = rednet.receive(PROTO, 3)
    if id == ch and type(msg) == "table" and msg.status == "pong" then return true end
    return false
end

local function exec_on_turtle(code)
    if not turtleId then print("Not connected."); return end
    rednet.send(turtleId, {action="exec", code=code}, PROTO)
    local id, msg = rednet.receive(PROTO, 15)
    if not id then print("Timeout waiting for turtle."); return end
    if type(msg) ~= "table" then print("Bad reply: " .. tostring(msg)); return end
    if msg.output and msg.output ~= "" then print(msg.output) end
    if not msg.success then print("ERROR: " .. tostring(msg.error or "unknown")) end
end

local function connect(ch)
    if not ping(ch) then
        print("No turtle responding on channel " .. ch)
        return false
    end
    turtleId = ch
    print("Connected to turtle on channel " .. ch)
    return true
end

-- Chat runs on this computer; turtle connection is optional.
-- Start disconnected unless a channel was given on the command line.
if channel then
    if not connect(channel) then
        print("Continuing without connection; /connect <ch> later.")
    end
else
    print("No turtle connected. Use /connect <ch> to hook a turtle.")
end

local history = {}
local function system_msg() return {role="system", content=SYSTEM} end

print("API key loaded: " .. (API_KEY ~= "" and (API_KEY:sub(1,8) .. "...") or "NONE"))
print("Hermes CC chat. /help for commands. Backend=" .. backend .. " model=" .. MODEL)

local function process_line(line)
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line == "" then return end

    if line:sub(1,1) == "/" then
        local cmd, rest = line:match("^/(%S+)%s*(.*)$")
        cmd = (cmd or ""):lower()
        if cmd == "quit" or cmd == "exit" then
            error("__quit__")
        elseif cmd == "help" then
            print("/help /clear /status /exec <code> /connect <ch> /quit")
        elseif cmd == "clear" then
            history = {}; print("History cleared.")
        elseif cmd == "status" then
            if turtleId and ping(turtleId) then print("turtle OK on " .. turtleId) else print("no turtle") end
        elseif cmd == "connect" then
            local ch = tonumber(rest); if ch then connect(ch) else print("usage: /connect <ch>") end
        elseif cmd == "exec" then
            if rest ~= "" then exec_on_turtle(rest) else print("usage: /exec <code>") end
        else
            print("Unknown command: " .. cmd)
        end
        return
    end

    local msgs = {system_msg()}
    for _, m in ipairs(history) do msgs[#msgs+1] = m end
    msgs[#msgs+1] = {role="user", content=line}

    write("... thinking ...\n")
    local reply, err = llm_chat(msgs)
    if not reply then
        print("LLM error: " .. tostring(err)); return
    end
    print("\n" .. reply .. "\n")

    history[#history+1] = {role="user", content=line}
    history[#history+1] = {role="assistant", content=reply}

    local blocks = extract_code(reply)
    if #blocks > 0 and turtleId then
        write("Execute " .. #blocks .. " code block(s) on turtle? [y/N] ")
        local ans = read()
        if ans and ans:lower():sub(1,1) == "y" then
            for i, b in ipairs(blocks) do
                print("--- block " .. i .. " ---")
                exec_on_turtle(b)
            end
        end
    end
end

while true do
    write("> ")
    local line = read()
    if line == nil then break end
    local ok, qerr = pcall(process_line, line)
    if not ok then
        if qerr == "__quit__" then break end
        print("Error: " .. tostring(qerr))
    end
end

print("Bye.")
