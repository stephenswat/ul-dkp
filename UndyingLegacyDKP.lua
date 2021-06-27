local roll_state = {}

local PREFIX = 'UL DKP'

local function reset_roll_state()
    roll_state.rolling_item = nil
    roll_state.bids = {}
    roll_state.candidates = {}
    roll_state.ticker = nil
end

reset_roll_state()

local function clean_name(name)
    local dash = name:find('-')

    if dash then
        return name:sub(1, dash - 1)
    else
        return name
    end
end

local function get_announce_target(warn)
    if warn and (UnitIsGroupLeader('player') or UnitIsGroupAssistant('player')) then
        return 'RAID_WARNING'
    else
        return 'RAID'
    end
end

local function send_whisper(msg, target)
    local fmsg = PREFIX .. ': ' .. msg

    if target == UnitName('player') then
        print(fmsg)
    else
        SendChatMessage(fmsg, 'WHISPER', nil, target)
    end
end

local function send_message(msg, warn)
    SendChatMessage(PREFIX .. ': ' .. msg, get_announce_target(warn), nil, nil)
end

local function do_finish_roll()
    local bids = {}
    local bidders = {}

    for name, bid in pairs(roll_state.bids) do
        if bid >= 0 then
            if bidders[bid] == nil then
                bidders[bid] = {name}
                table.insert(bids, bid)
            else
                table.insert(bidders[bid], name)
            end
        end
    end

    table.sort(bids)

    if #bids > 0 then
        local highest = bids[#bids]

        send_message('Highest bid: ' .. tostring(highest) .. ' by ' .. table.concat(bidders[highest], ', '))

        if #bids > 1 then
            send_message('Other bids:')

            for i = 2, #bids do
                local b = bids[#bids + 1 - i]
                send_message('    ' .. tostring(b) .. ': ' .. table.concat(bidders[b], ', '))
            end
        end
    else
        send_message('Nobody has bid on this item.', false)
    end

    reset_roll_state()
end

local function handle_tick()
    if not roll_state.ticker then
        return
    end

    local iter = roll_state.ticker._remainingIterations - 1

    if iter == 0 then
        do_finish_roll()
    elseif iter <= 3 then
        send_message('{rt1} ' .. tostring(iter) .. ' {rt1}', false)
    end
end

local function do_start_roll(item_link, duration)
    roll_state.rolling_item = item_link

    for n = 1, GetNumGroupMembers() do
        local name = GetRaidRosterInfo(n)
        roll_state.candidates[clean_name(name)] = true
    end

    send_message('Bid for ' .. item_link .. ' (' .. tostring(duration) .. ' seconds)', true)

    roll_state.ticker = C_Timer.NewTicker(1, handle_tick, duration)
end

local function handle_bid(msg, player)
    if roll_state.rolling_item == nil then
        return
    end

    if not roll_state.candidates[player] then
        return
    end

    msg = string.lower(msg)
    local num = tonumber(msg)

    if num ~= nil then
        if roll_state.bids[player] ~= nil then
            send_whisper('Error: You have already placed a bid!', player)
            return
        end

        if num < 0 then
            send_whisper('Error: You cannot bid less than 0 DKP!', player)
            return
        end

        roll_state.bids[player] = math.floor(num)

        send_whisper('Success: Your bid of ' .. tostring(roll_state.bids[player]) .. ' has been registered!', player)
    elseif msg == 'out' or msg == 'withdraw' or msg == 'cancel' then
        if roll_state.bids[player] == nil then
            send_whisper('Error: You cannot withdraw your bid, you haven\'t placed one!', player)
            return
        end

        roll_state.bids[player] = -1

        send_whisper('Success: Your bid has been withdrawn!', player)
    else
        send_whisper('Error: Command \'' .. msg .. '\' was not recognised. Did you mean \'withdraw\' or \'cancel\'?', player)
    end
end

local function handle_msg(msg, player)
    handle_bid(msg, clean_name(player))
end

local function do_cancel_roll()
    if roll_state.ticker then
        roll_state.ticker:Cancel()
    end

    send_message('{rt7} Cancelled bidding for ' .. roll_state.rolling_item .. '!', false)
    reset_roll_state()
end

local function event_handler(self, event, ...)
    if event == 'CHAT_MSG_WHISPER' then
        handle_msg(...)
    end
end

local frame = CreateFrame('frame', 'UndyingLegacyDKPFrame')
frame:RegisterEvent('CHAT_MSG_WHISPER')
frame:SetScript('OnEvent', event_handler)

SLASH_ULDKP1 = '/ul'
function SlashCmdList.ULDKP(arg)
    if not IsInRaid() then
        print('You are not in a raid!')
        return
    end

    local cmd = nil
    local rest = nil

    local space = arg:find(' ')
    if space then
        cmd = arg:sub(1, space - 1)
        rest = arg:sub(space + 1)
    else
        cmd = arg
    end

    if cmd == 'start' and rest then
        if roll_state.rolling_item == nil then
            do_start_roll(rest, 20)
        else
            print('There is an ongoing bid for ' .. roll_state.rolling_item)
        end
    elseif cmd == 'cancel' then
        if roll_state.rolling_item then
            do_cancel_roll()
        else
            print('There is no ongoing bid')
            reset_roll_state()
        end
    elseif cmd == 'bid' then
        handle_bid(rest, UnitName('player'))
    else
        print('Usage: /ul start [item] | /ul cancel | /ul bid [bid]')
    end
end
