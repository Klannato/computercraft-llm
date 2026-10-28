-- cc_turtle_server.lua
-- Run on the TURTLE. Listens on a rednet channel (default 65) and executes
-- code sent by cc_hermes_chat.lua. Handles ping/status/exec.
--
-- Usage:  cc_turtle_server [channel]

local args = {...}
local channel = tonumber(args[1]) or 65
local PROTO = "hermes-cc"

local modem = peripheral.find("modem")
if not modem then error("No modem on turtle.") end
rednet.open(peripheral.getName(modem))
rednet.host(PROTO, "turtle-" .. os.getComputerID())

-- sandboxed env for exec
local function make_env()
    local env = {
        turtle = turtle, print = print, math = math, string = string,
        table = table, sleep = sleep, os = os, shell = {run = shell.run},
        pairs = pairs, ipairs = ipairs, tonumber = tonumber, tostring = tostring,
        type = type, pcall = pcall, error = error, assert = assert,
    }
    return env
end

rednet.open(channel and channel or 65)
-- open the channel we listen on
local m = peripheral.find("modem")
m.open(channel)

print("Turtle server listening on channel " .. channel .. " (id " .. os.getComputerID() .. ")")

while true do
    local id, msg, proto = rednet.receive(PROTO)
    if type(msg) ~= "table" then goto continue end
    if msg.action == "ping" then
        rednet.send(id, {status="pong", id=os.getComputerID()}, PROTO)
    elseif msg.action == "status" then
        rednet.send(id, {status="ok", fuel=turtle.getFuelLevel(), id=os.getComputerID()}, PROTO)
    elseif msg.action == "exec" then
        local code = msg.code or ""
        local env = make_env()
        local fn, err = load(code, "remote", "t", env)
        if not fn then
            rednet.send(id, {success=false, output="", error="compile: " .. tostring(err)}, PROTO)
            goto continue
        end
        -- capture print
        local out = {}
        local orig_print = print
        env.print = function(...) local t={...}; for i=1,#t do t[i]=tostring(t[i]) end; out[#out+1]=table.concat(t,"\t"); orig_print(...) end
        local ok, rerr = pcall(fn)
        rednet.send(id, {success=ok, output=table.concat(out,"\n"), error=ok and nil or tostring(rerr)}, PROTO)
    end
    ::continue::
end
