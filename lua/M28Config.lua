---
--- Generated by EmmyLua(https://github.com/EmmyLua)
--- Created by maudlin27.
--- DateTime: 16/11/2022 07:31
---

M28ShowUnitNames = true --Will update units to reflect the order theyve been given
M28ShowEnemyUnitNames = true --Will rename enemy units to reflect their ID and lifetime count
M28RunVeryFast = true --Game starts off at +15 speed if set to adjustable

--Profiling config options
M28RunProfiling = false --If turning to true-part way through the game then also run ForkThread(M28Profiler.ProfilerActualTimePerTick); Records data on how long most functions are taking
M28ProfilingIncludePerTick = false --if M28RunProfiling is true, then this determins whether will just do the detailed log of time taken for functions, or will also include the per tick results
M28ProfilerIgnoreFirst2Seconds = false --Means logic relating to pathing generation gets ignored