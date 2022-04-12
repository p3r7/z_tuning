-- helper functions for octave ratio tables
local note_freq_from_table = function(midi, rats, root_note, root_hz, oct)
   -- FIXME [OPTIMIZE]:
   -- in general, there can be more memoization and explicit use of integer types
   -- when oct==2^N (as is near-universal), can maybe use some bitwise ops
   -- fractional degrees are quite costly (x2, plus exponential intep)
   oct = oct or 2
   local degree = midi - root_note
   local n = #rats
   local mf = math.floor(midi)
   if midi == mf then
      return root_hz * rats[(degree % n) + 1] * (oct ^ (math.floor(degree / n)))
   else
      local mf = math.floor(midi)
      local f = math.abs(midi - mf)
      local deg1
      if (degree > 0) then
         deg1 = deg + 1
      else
         deg1 = deg - 1
      end
      local a = root_hz * rats[(degree % n) + 1] * (oct ^ (math.floor(degree / n)))
      local b = root_hz * rats[(deg1 % n) + 1] * (oct ^ (math.floor(deg1 / n)))
      return a * math.pow((b / a), f)
   end
end

local midi_note_from_table = function(midi, bend_range, rats, root_note, root_hz, oct)
  local prev_midi = midi - (bend_range / 2)
  local next_midi = midi + (bend_range / 2)

  print("prev_midi="..prev_midi)
  print("next_midi="..next_midi)

  local hz = note_freq_from_table(midi, rats, root_note, root_hz, oct)
  local prev_hz = note_freq_from_table(prev_midi, rats, root_note, root_hz, oct)
  local next_hz = note_freq_from_table(next_midi, rats, root_note, root_hz, oct)

  print("prev_hz="..prev_hz)
  print("next_hz="..next_hz)
  print("prev_diff="..math.log(hz-prev_hz, 2))
  print("next_diff="..math.log(next_hz-hz, 2))

  -- FIXME: bad math
  local bend_v = util.linlin(-math.log(hz-prev_hz), math.log(next_hz-hz), -(bend_range / 2), (bend_range / 2), 0)
  -- local bend_v = util.linlin(prev_hz-hz, next_hz-hz, -(bend_range / 2), (bend_range / 2), 0)

  print("bend_v="..bend_v)

  -- normalize bend_range to be between -1..1
  bend_v = util.clamp(bend_v/(bend_range/2), -1, 1)

  print("bend_v(normalized)="..bend_v)


  local midi_bend_v = math.floor((bend_v + 1) * 8192)
  return {midi, midi_bend_v}
end

local interval_ratio_from_table = function(interval, rats, oct)
   oct = oct or 2
   local n = #rats
   local rat = rats[(int % n) + 1]
   return rat * (oct ^ (math.floor(interval / n)))
end

----------------------------------------------------
-- tuning class

local Tuning = {}
Tuning.__index = Tuning

Tuning.new = function(args)
   local x = setmetatable({}, Tuning)

   x.pseudo_octave = args.pseudo_octave or 2

   if args.note_freq and args.interval_ratio then
      x.note_freq = args.note_freq
      x.interval_ratio = args.interval_ratio
   elseif args.ratios then
      x.note_freq = function(midi, root_note, root_hz)
         return note_freq_from_table(midi, args.ratios, root_note, root_hz, x.pseudo_octave)
      end
      x.interval_ratio = function(interval)
         return interval_ratio_from_table(interval, args.ratios, x.pseudo_octave)
      end
      x.midi_note = function(midi, bend_range, root_note, root_hz)
        return midi_note_from_table(midi, bend_range, args.ratios, root_note, root_hz, x.pseudo_octave)
      end
   else
      print("error; don't know how to construct tuning with these arguments: ")
      tab.print(args)
      return nil
   end

   return x
end

return Tuning
