-- Opt-in native execution profiler. Wall-clock values stay in this module and
-- the log: they must never influence synchronized AI decisions or unit state.
-- Exclusive time includes engine/core work called by M28, but excludes other
-- M28 functions. Inclusive time includes those descendants and is not additive.
local clock = GetSystemTimeSecondsOnlyForProfileUse
local getinfo = debug.getinfo
local sethook = debug.sethook
local currentThread = rawget(_G, 'CurrentThread') or coroutine.running
local mainThread = {}
local states = setmetatable({}, {__mode='k'})
local retainedStates = {}
local metadata = setmetatable({}, {__mode='k'})
local rows = {}
local running = false
local previous = false
local lastClock = false
local hookMilliseconds = 0
local eventCount = 0
local eventMillions = 0
local hookCorrection = 0
local unmatchedReturns = 0
local abandonedFrames = 0
local negativeDeltas = 0
local windowStart = 0
local windowWallStart = 0
local minimumClockStep = false
local maximumDepth = 0
local resumedCalls = 0
local anomalies = {}
local waitFunctions = {}

local function Add(row,field,correctionField,value)
    -- FA numbers are floats. Preserve sub-millisecond contributions even when
    -- a startup pass accumulates many seconds of work in a single sim tick.
    local corrected=value-row[correctionField]
    local total=row[field]+corrected
    row[correctionField]=(total-row[field])-corrected
    row[field]=total
end

local function Elapsed(state,frame)
    return (state.active_ms-frame.start_ms)-(state.active_error-frame.start_error)
end

local function RowFor(info)
    local cached = metadata[info.func]
    if cached then return cached end
    local source = string.lower(string.gsub(info.source or '', '\\', '/'))
    local offset = string.find(source, '/m28ai/', 1, true)
    local row = false
    local internal = offset and string.find(source, '/m28timing.lua', 1, true)
    if offset and not(internal) then
        source = string.sub(source, offset+7)
        local key = source..':'..(info.linedefined or 0)..':'..(info.name or '<anonymous>')
        row = rows[key]
        if not(row) then
            row = {key=key, source=source, line=info.linedefined or 0,
                name=info.name or '<anonymous>', calls=0, returns=0, open=0,
                exclusive_ms=0, exclusive_error=0, inclusive_ms=0, inclusive_error=0, max_ms=0}
            rows[key] = row
        end
    end
    cached = {row=row, internal=internal, wait=waitFunctions[info.func] or false}
    metadata[info.func] = cached
    return cached
end

local function Charge(now)
    if lastClock then
        local delta = (now-lastClock)*1000
        if delta < 0 then negativeDeltas=negativeDeltas+1 delta=0 end
        if delta > 0 and (not(minimumClockStep) or delta < minimumClockStep) then minimumClockStep=delta end
        if previous and not(previous.suspended) and previous.owner then
            Add(previous.owner,'exclusive_ms','exclusive_error',delta)
            Add(previous,'active_ms','active_error',delta)
        end
    end
end

local function Push(state, fn, meta, partial)
    local depth = state.depth+1
    local frame = state.frames[depth]
    if not(frame) then frame={} state.frames[depth]=frame end
    frame.fn=fn
    frame.meta=meta
    frame.start_ms=state.active_ms
    frame.start_error=state.active_error
    frame.partial=partial
    frame.parentOwner=state.owner
    state.depth=depth
    if meta.internal then state.owner=false
    elseif meta.row then
        state.owner=meta.row
        if partial then meta.row.open=meta.row.open+1 else meta.row.calls=meta.row.calls+1 end
    end
    if meta.wait then state.suspended=true end
    if depth > maximumDepth then maximumDepth=depth end
end

local function Pop(state, completed)
    local frame=state.frames[state.depth]
    if frame.meta.row then
        local row=frame.meta.row
        local elapsed=Elapsed(state,frame)
        Add(row,'inclusive_ms','inclusive_error',elapsed)
        if completed and not(frame.partial) then
            row.returns=row.returns+1
            row.max_ms=math.max(row.max_ms,elapsed)
        end
    end
    if frame.meta.wait then
        state.suspended=false
        state.resumeCaller=state.depth>1 and state.frames[state.depth-1].fn or false
    end
    state.owner=frame.parentOwner
    frame.fn=false
    state.depth=state.depth-1
end

local function NativeHook(event)
    local entered=clock()
    Charge(entered)
    eventCount=eventCount+1
    if eventCount>=1000000 then eventMillions=eventMillions+1 eventCount=0 end
    -- Native FA throws for main-state callbacks; coroutine.running is absent.
    -- The protected identity query does not enclose or alter a yielding call.
    local hasThread,thread=pcall(currentThread)
    if not(hasThread) or not(thread) then thread=mainThread end
    local state=states[thread]
    local newState=not(state)
    if not(state) then
        state={frames={}, depth=0, owner=false, active_ms=0, active_error=0, suspended=false}
        states[thread]=state
        -- Retain unfinished accounting until export even if the engine destroys
        -- the thread and its weak identity key is collected in this window.
        retainedStates[state]=true
        -- A profiler may start while callers are already running. Reconstruct
        -- ancestors without pretending their invocations started in this window.
        local ancestors={}
        local level=3
        while true do
            local info=getinfo(level,'fSn')
            if not(info) then break end
            ancestors[table.getn(ancestors)+1]=info
            level=level+1
        end
        for index=table.getn(ancestors),1,-1 do
            local info=ancestors[index]
            Push(state,info.func,RowFor(info),true)
        end
    end
    previous=state
    local info=getinfo(2,'fSn')
    local resumeCaller=state.resumeCaller
    state.resumeCaller=false
    if event=='call' then
        -- Native FA returns from yield, then emits an extra call for the same
        -- caller frame before executing its next instruction (not recursion).
        local resumed=resumeCaller==info.func and state.depth>0 and state.frames[state.depth].fn==info.func
        if resumed then resumedCalls=resumedCalls+1 end
        if state.suspended then
            -- Also tolerate a scheduler resume without a native wait return.
            -- A real recursive call cannot originate from a suspended frame.
            local found=state.depth
            while found>0 and state.frames[found].fn~=info.func do found=found-1 end
            if found>0 then
                while state.depth>found do Pop(state,false) end
                state.suspended=false
                resumed=true
                resumedCalls=resumedCalls+1
            end
        end
        if not(resumed) then Push(state,info.func,RowFor(info),false) end
    elseif event=='return' then
        if newState then Push(state,info.func,RowFor(info),true) end
        local found=state.depth
        while found>0 and state.frames[found].fn~=info.func do found=found-1 end
        if found==0 then
            unmatchedReturns=unmatchedReturns+1
            if table.getn(anomalies)<8 then
                anomalies[table.getn(anomalies)+1]='unmatched-return|'..(info.source or '?')..':'..(info.linedefined or 0)..':'..(info.name or '?')
            end
        else
            while state.depth>found do
                if table.getn(anomalies)<8 then
                    local abandoned=getinfo(state.frames[state.depth].fn,'S') or {}
                    anomalies[table.getn(anomalies)+1]='unwound-frame|'..(abandoned.source or '?')..':'..(abandoned.linedefined or 0)..'|returning='..(info.name or '?')
                end
                Pop(state,false) abandonedFrames=abandonedFrames+1
            end
            Pop(state,true)
        end
    elseif event=='tail return' then
        if state.depth>0 then Pop(state,true) else unmatchedReturns=unmatchedReturns+1 end
    end
    if state.depth==0 then states[thread]=nil retainedStates[state]=nil previous=false end
    local finished=clock()
    local corrected=(finished-entered)*1000-hookCorrection
    local total=hookMilliseconds+corrected
    hookCorrection=(total-hookMilliseconds)-corrected
    hookMilliseconds=total
    lastClock=finished
end

function IsRunning()
    return running
end

function Start()
    if running then return true end
    if not(currentThread) then LOG('M28PROFILE|error|reason=no-thread-identity') return false end
    local existing=debug.gethook()
    if existing then LOG('M28PROFILE|error|reason=another-debug-hook-is-active') return false end
    states=setmetatable({}, {__mode='k'})
    retainedStates={}
    metadata=setmetatable({}, {__mode='k'})
    rows={}
    previous=false
    lastClock=false
    hookMilliseconds=0
    hookCorrection=0
    eventCount=0
    eventMillions=0
    unmatchedReturns=0
    abandonedFrames=0
    negativeDeltas=0
    minimumClockStep=false
    maximumDepth=0
    resumedCalls=0
    anomalies={}
    windowStart=GetGameTimeSeconds()
    windowWallStart=clock()
    waitFunctions={[coroutine.yield]=true}
    for _,name in {'WaitFor','SuspendCurrentThread'} do
        local fn=rawget(_G,name)
        if fn then waitFunctions[fn]=true end
    end
    running=true
    LOG('M28PROFILE|start|version=2|unit=ms|clock=wall|exclusive=includes-called-core-excludes-other-M28|t='..windowStart)
    sethook(NativeHook,'cr')
    return true
end

local function CaptureRows()
    for state in retainedStates do
        for index=1,state.depth do
            local frame=state.frames[index]
            if frame.meta.row then
                Add(frame.meta.row,'inclusive_ms','inclusive_error',Elapsed(state,frame))
                frame.meta.row.open=frame.meta.row.open+1
            end
            frame.start_ms=0
            frame.start_error=0
            frame.partial=true
        end
        state.active_ms=0
        state.active_error=0
    end
    retainedStates={}
    for _,state in states do retainedStates[state]=true end
    local result={}
    for _,row in rows do
        result[table.getn(result)+1]={key=row.key,source=row.source,line=row.line,name=row.name,
            calls=row.calls,returns=row.returns,open=row.open,exclusive_ms=row.exclusive_ms,
            inclusive_ms=row.inclusive_ms,max_ms=row.max_ms}
        row.calls=0 row.returns=0 row.open=0 row.exclusive_ms=0 row.exclusive_error=0 row.inclusive_ms=0 row.inclusive_error=0 row.max_ms=0
    end
    return result
end

function Flush(stop)
    if not(running) then return false end
    sethook()
    Charge(clock())
    local finish=GetGameTimeSeconds()
    local wallMilliseconds=(clock()-windowWallStart)*1000
    local result=CaptureRows()
    table.sort(result,function(a,b) return a.exclusive_ms>b.exclusive_ms end)
    local total=0
    for _,row in result do total=total+row.exclusive_ms end
    local events=eventMillions>0 and (eventMillions..string.format('%06d',eventCount)) or tostring(eventCount)
    LOG('M28PROFILE|window|from='..windowStart..'|to='..finish..'|wall_ms='..wallMilliseconds..'|exclusive_ms='..total..'|hook_ms='..hookMilliseconds..'|events='..events..'|unmatched='..unmatchedReturns..'|abandoned='..abandonedFrames..'|resumed='..resumedCalls..'|clock_backwards='..negativeDeltas..'|clock_step_ms='..tostring(minimumClockStep)..'|max_depth='..maximumDepth)
    for _,detail in anomalies do LOG('M28PROFILE|anomaly|from='..windowStart..'|'..detail) end
    for _,row in result do
        if row.calls>0 or row.open>0 or row.exclusive_ms>0 then
            LOG('M28PROFILE|function|from='..windowStart..'|to='..finish..'|source='..row.source..'|line='..row.line..'|name='..row.name..'|calls='..row.calls..'|returns='..row.returns..'|open='..row.open..'|self_ms='..row.exclusive_ms..'|inclusive_ms='..row.inclusive_ms..'|max_complete_ms='..row.max_ms)
        end
    end
    hookMilliseconds=0 hookCorrection=0 eventCount=0 eventMillions=0 unmatchedReturns=0 abandonedFrames=0 negativeDeltas=0 resumedCalls=0
    minimumClockStep=false maximumDepth=0 anomalies={}
    windowStart=finish
    if stop then
        running=false states=setmetatable({}, {__mode='k'}) retainedStates={} previous=false lastClock=false
    else
        lastClock=clock()
        windowWallStart=lastClock
        sethook(NativeHook,'cr')
    end
    return result
end
