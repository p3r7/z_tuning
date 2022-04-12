local mod = require 'core/mods'
local util = require 'lib/util'

local tuning = require 'z_tuning/lib/tuning'
local tunings_builtin = require 'z_tuning/lib/tunings_builtin'
local tuning_files = require 'z_tuning/lib/tuning_files'

local tuning_state = {
   root_note = 69,
   root_freq = 440.0,
   selected_tuning = 'ji_ptolemaic',
   midi_bend_range = 2,
}

local tunings = {}
local tuning_keys = {}
local tuning_keys_rev = {}
local num_tunings = 0

local setup_tunings = function()
   tunings = {}
   tuning_keys = {}
   tuning_keys_rev = {}
   num_tunings = 0

   -- add built-in tunings
   for k, v in pairs(tunings_builtin) do
      tunings[k] = v
      table.insert(tuning_keys, k)
      num_tunings = num_tunings + 1
   end

   -- add tunings from disk
   local tf = tuning_files.load_files()
   for k, v in pairs(tf) do
      tunings[k] = v
      table.insert(tuning_keys, k)
      num_tunings = num_tunings + 1
   end
   table.sort(tuning_keys)
   for i, v in ipairs(tuning_keys) do
      tuning_keys_rev[v] = i
   end
end

-- set the root note number, without changing the concert pitch (w/r/t a=440)
-- in other words, update the root frequency such that the tuning would not change under 12tet
local set_root_note_move_freq = function(num)
   local interval = num - tuning_state.root_note
   local ratio = tunings['edo12'].interval_ratio(interval)
   local new_freq = tuning_state.root_freq * ratio
   new_freq = math.floor(new_freq * 16) * 0.0625
   tuning_state.root_note = num
   tuning_state.root_freq = new_freq
end

-- set the root note number, without changing root frequency
-- this effects a simple transposition unless root frequency is updated separately
local set_root_note_keep_freq = function(num)
   tuning_state.root_note = num
end

local interval_ratio = function(interval)
   return tunings[tuning_state.selected_tuning].interval_ratio(interval)
end

local apply_mod = function()
   local musicutil = require 'musicutil'
   musicutil.note_num_to_freq = function(num)
      return tunings[tuning_state.selected_tuning].note_freq(num, tuning_state.root_note, tuning_state.root_freq)
   end
   musicutil.interval_to_ratio = interval_to_ratio

   -- FIXME? this is a tricky one...
   -- (in fact i'm going to say, impossible in general
   -- since int->ratio not be invertible/continuous/monotonic
   -- musicutil.ratio_to_interval = ...

   local og_midi_send = midi.send
   midi.send = function(self, data)
     local msg
     if data.type == nil then
       msg = midi.to_msg(data)
     else
       msg = data
     end
     if msg.type == "note_on" then
       -- print("-------------")
       -- print("NOTE ON!")
       -- tab.print(tuning_state)
       local tuned_note = tunings[tuning_state.selected_tuning].midi_note(msg.note,
                                                                          tuning_state.midi_bend_range,
                                                                          tuning_state.root_note,
                                                                          tuning_state.root_freq)
       tab.print(tuned_note)
       msg.note = tuned_note[1]
       og_midi_send(self, msg)
       og_midi_send(self, {type="pitchbend", val=tuned_note[2], ch=msg.ch or 1})
     else
       og_midi_send(self, data)
     end
   end
end

----------------------
--- state persistence
local state_path = _path.data .. 'tuning_state.lua'

local save_tuning_state = function()
   local f = io.open(state_path, 'w')
   io.output(f)
   io.write('return { \n')
   local keys = {'selected_tuning', 'root_note', 'root_freq', 'midi_bend_range'}
   for _, k in pairs(keys) do
     local v = tuning_state[k]
     local vstr = v
     if type(v) == 'string' then
         vstr = "'" .. v .. "'"
      end
      io.write('  ' .. k .. ' = ' .. vstr .. ',\n')
   end
   io.write('}\n')
   io.close(f)
end

local recall_tuning_state = function()
   local f = io.open(state_path)
   if f then
      io.close(f)
      tuning_state = dofile(state_path)
   end
end

local mod_init = function()
   -- copy factory files, if needed
   tuning_files.bootstrap()
   -- build and populate the tunings container
   setup_tunings()
   apply_mod()

end

-----------------------------
---- hooks!

mod.hook.register("system_post_startup", "init tuning mod", mod_init)

mod.hook.register("system_post_startup", "recall tuning mod settings", recall_tuning_state)

mod.hook.register("system_pre_shutdown", "save tuning mod settings", save_tuning_state)

-----------------------------
---- menu UI

local edit_select = {
   [1] = 'tuning',
   [2] = 'note',
   [3] = 'freq',
   [4] = 'midi_bend_range',
}
local num_edit_select = 4

local m = {
  edit_select = 1,
  freq_mode_keep = false
}

m.key = function(n, z)
   if n == 3 then
      m.freq_mode_keep = (z > 0)
   end

   if n == 2 and z > 0 then
      -- return to the mod selection menu
      mod.menu.exit()
   end

end

m_enc = {
   [2] = function(d)
      m.edit_select = util.clamp(m.edit_select + d, 1, num_edit_select)
   end,

   [3] = function(d)
      (m_incdec[m.edit_select])(d)
   end
}

m_incdec = {
   -- edit tuning selection
   [1] = function(d)
      local sel = tuning_state.selected_tuning
      local i = tuning_keys_rev[sel]
      i = util.clamp(i + d, 1, num_tunings)
      tuning_state.selected_tuning = tuning_keys[i]
   end,
   -- edit root note
   [2] = function(d)
      local num = util.clamp(tuning_state.root_note + d, 0, 127)
      if m.freq_mode_keep then
         set_root_note_keep_freq(num)
      else
         set_root_note_move_freq(num)
      end
   end,
   -- edit base frequency
   [3] = function(d)
      tuning_state.root_freq = math.floor((tuning_state.root_freq + (d * 0.0625)) * 16) * 0.0625
      tuning_state.root_freq = util.clamp(tuning_state.root_freq, 1, 10000)
   end,
   -- edit midi bend range
   [4] = function(d)
     local sign = 1
     if d < 0 then sign = -1 end
     tuning_state.midi_bend_range = util.clamp(tuning_state.midi_bend_range + (sign * 2), 2, 4)
   end
}

m.enc = function(n, d)
   if m_enc[n] then
      (m_enc[n])(d)
   end
   mod.menu.redraw()
end

m.redraw = function()
   screen.clear()

   screen.move(0, 10)
   if edit_select[m.edit_select] == 'tuning' then
      screen.level(15)
   else
      screen.level(4)
   end
   screen.text("temperament: " .. tuning_state.selected_tuning)

   screen.move(0, 20)
   if edit_select[m.edit_select] == 'note' then
      screen.level(15)
   else
      screen.level(4)
   end
   screen.text("root note: " .. tuning_state.root_note)

   screen.move(0, 30)
   if edit_select[m.edit_select] == 'freq' then
      screen.level(15)
   else
      screen.level(4)
   end
   screen.text("root freq: " .. tuning_state.root_freq)

   screen.move(0, 40)
   if edit_select[m.edit_select] == 'midi_bend_range' then
     screen.level(15)
   else
     screen.level(4)
   end
   screen.text("midi bend range: " .. tuning_state.midi_bend_range)

   --- TODO:
   -- show some more basic data on selected tuning
   --- (pseudo-octave, degree count)

   screen.update()
end

m.init = function()
  print ('z_tuning: init menu?')
   -- (nothing to do)
end

m.deinit = function()
  print ('z_tuning: deinit menu?')
   -- (nothing to do)
end

mod.menu.register(mod.this_name, m)

----------------------
--- API

local api = {}

-- return the current state of the mod, a table containing:
-- - tuning selection (ID string)
-- - root note number
-- - base frequency
api.get_tuning_state = function()
   return tuning_state
end

-- get the entire collection of tuning data
api.get_tuning_data = function()
   return tunings
end

-- save the current tuning state
api.save_state = save_tuning_state
-- recall the saved tuning state
api.recall_state = recall_tuning_state

-- set the root note,  independent odf base frequency
api.set_root_note_keep_freq = set_root_note_keep_freq

-- change the root note, moving the base frequency
api.set_root_note_move_freq = set_root_note_move_freq

-- set the current tuning, given numerical index
api.select_tuning_by_index = function(idx)
   tuning_state.selected_tuning = tuning_keys[idx]
end

-- set the current tuning, given ID string
api.select_tuning_by_id = function(id)
   local idx = tuning_keys_rev[id]
   tuning_state.selected_tuning = tuning_keys[idx]
end

return api
