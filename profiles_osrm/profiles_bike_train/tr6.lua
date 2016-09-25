-- Car profile

local find_access_tag = require("lib/access").find_access_tag

-- Begin of globals
barrier_whitelist = { ["cattle_grid"] = true, ["border_control"] = true, ["checkpoint"] = true, ["toll_booth"] = true, ["sally_port"] = true, ["gate"] = true, ["lift_gate"] = true, ["no"] = true, ["entrance"] = true }
access_tag_whitelist = { ["yes"] = true, ["motorcar"] = true, ["motor_vehicle"] = true, ["vehicle"] = true, ["permissive"] = true, ["designated"] = true, ["destination"] = true, ["no"] = true, ["private"] = true, ["agricultural"] = true, ["forestry"] = true }
access_tag_blacklist = { ["emergency"] = true, ["psv"] = true }
access_tag_restricted = { ["destination"] = true, ["delivery"] = true }
access_tags = { "motorcar", "motor_vehicle", "vehicle","train","tramway","light_rail","railway","tram" }
access_tags_hierachy = { "motorcar", "motor_vehicle", "vehicle", "access","train","tramway","light_rail","railway","tram" }
service_tag_restricted = { ["parking_aisle"] = true }
restriction_exception_tags = { "motorcar", "motor_vehicle", "vehicle","train","tramway","light_rail","railway","tram" }

speed_profile = {
  ["motorway"] = 10,
  ["motorway_link"] = 10,
  ["trunk"] = 10,
  ["trunk_link"] = 10,
  ["primary"] = 10,
  ["primary_link"] = 10,
  ["secondary"] = 10,
  ["secondary_link"] = 10,
  ["tertiary"] = 10,
  ["tertiary_link"] = 10,
  ["unclassified"] = 10,
  ["residential"] = 10,
  ["living_street"] = 10,
  ["service"] = 10,
  ["track"] = 50,
  ["ferry"] = 5,
  ["movable"] = 5,
  ["shuttle_train"] = 10,
  ["default"] = 10,
  ["train"] = 160,
  ["railway"] = 100,
  ["subway"] = 20,
  ["light_rail"] = 20,
  ["monorail"] = 25,
  ["tram"] = 20
}


-- surface/trackype/smoothness
-- values were estimated from looking at the photos at the relevant wiki pages

-- max speed for surfaces
surface_speeds = {
  ["asphalt"] = nil,    -- nil mean no limit. removing the line has the same effect
  ["concrete"] = nil,
  ["concrete:plates"] = nil,
  ["concrete:lanes"] = nil,
  ["paved"] = nil,

  ["cement"] = 80,
  ["compacted"] = 80,
  ["fine_gravel"] = 80,

  ["paving_stones"] = 60,
  ["metal"] = 60,
  ["bricks"] = 60,

  ["grass"] = 40,
  ["wood"] = 40,
  ["sett"] = 40,
  ["grass_paver"] = 40,
  ["gravel"] = 40,
  ["unpaved"] = 40,
  ["ground"] = 40,
  ["dirt"] = 40,
  ["pebblestone"] = 40,
  ["tartan"] = 40,

  ["cobblestone"] = 30,
  ["clay"] = 30,

  ["earth"] = 20,
  ["stone"] = 20,
  ["rocky"] = 20,
  ["sand"] = 20,

  ["mud"] = 10
}

-- max speed for tracktypes
tracktype_speeds = {
  ["grade1"] =  60,
  ["grade2"] =  40,
  ["grade3"] =  30,
  ["grade4"] =  25,
  ["grade5"] =  20
}

-- max speed for smoothnesses
smoothness_speeds = {
  ["intermediate"]    =  80,
  ["bad"]             =  40,
  ["very_bad"]        =  20,
  ["horrible"]        =  10,
  ["very_horrible"]   =  5,
  ["impassable"]      =  0
}

-- http://wiki.openstreetmap.org/wiki/Speed_limits
maxspeed_table_default = {
  ["urban"] = 50,
  ["rural"] = 60,
  ["trunk"] = 60,
  ["motorway"] = 60,
  ["train"] = 160,
  ["railway"] = 100,
  ["subway"] = 20,
  ["light_rail"] = 20,
  ["monorail"] = 25,
  ["tram"] = 20
  
}

-- List only exceptions
maxspeed_table = {
  ["ch:rural"] = 80,
  ["ch:trunk"] = 100,
  ["ch:motorway"] = 120,
  ["de:living_street"] = 7,
  ["ru:living_street"] = 20,
  ["ru:urban"] = 60,
  ["ua:urban"] = 60,
  ["at:rural"] = 100,
  ["de:rural"] = 100,
  ["at:trunk"] = 100,
  ["cz:trunk"] = 0,
  ["ro:trunk"] = 100,
  ["cz:motorway"] = 0,
  ["de:motorway"] = 0,
  ["ru:motorway"] = 110,
  ["gb:nsl_single"] = (60*1609)/1000,
  ["gb:nsl_dual"] = (70*1609)/1000,
  ["gb:motorway"] = (70*1609)/1000,
  ["uk:nsl_single"] = (60*1609)/1000,
  ["uk:nsl_dual"] = (70*1609)/1000,
  ["uk:motorway"] = (70*1609)/1000
}

traffic_signal_penalty          = 2
use_turn_restrictions           = true

local turn_penalty              = 10
-- Note: this biases right-side driving.  Should be
-- inverted for left-driving countries.
local turn_bias                 = 1.2

local obey_oneway               = true
local ignore_areas              = true
local u_turn_penalty            = 20

local abs = math.abs
local min = math.min
local max = math.max

local speed_reduction = 0.8

--modes
local mode_normal = 1
local mode_ferry = 2
local mode_movable_bridge = 3

function get_exceptions(vector)
  for i,v in ipairs(restriction_exception_tags) do
    vector:Add(v)
  end
end

local function parse_maxspeed(source)
  if not source then
    return 0
  end
  local n = tonumber(source:match("%d*"))
  if n then
    if string.match(source, "mph") or string.match(source, "mp/h") then
      n = (n*1609)/1000
    end
  else
    -- parse maxspeed like FR:urban
    source = string.lower(source)
    n = maxspeed_table[source]
    if not n then
      local highway_type = string.match(source, "%a%a:(%a+)")
      n = maxspeed_table_default[highway_type]
      if not n then
        n = 0
      end
    end
  end
  return n
end

-- FIXME Why was this commented out?
-- function turn_function (angle)
--   -- print ("called at angle " .. angle )
--   local index = math.abs(math.floor(angle/10+0.5))+1 -- +1 'coz LUA starts as idx 1
--   local penalty = turn_cost_table[index]
--   -- print ("index: " .. index .. ", bias: " .. penalty )
--   return penalty
-- end

function node_function (node, result)
  -- parse access and barrier tags
  local access = find_access_tag(node, access_tags_hierachy)
  if access and access ~= "" then
    if access_tag_blacklist[access] then
      result.barrier = true
    end
  else
    local barrier = node:get_value_by_key("barrier")
    if barrier and "" ~= barrier then
      --  make an exception for rising bollard barriers
      local bollard = node:get_value_by_key("bollard")
      local rising_bollard = bollard and "rising" == bollard

      if not barrier_whitelist[barrier] and not rising_bollard then
        result.barrier = true
      end
    end
  end

  -- check if node is a traffic light
  local tag = node:get_value_by_key("highway")
  if tag and "traffic_signals" == tag then
    result.traffic_lights = true
  end
end

function way_function (way, result)
  local highway = way:get_value_by_key("highway")
  local route = way:get_value_by_key("route")
  local bridge = way:get_value_by_key("bridge")

  -- we dont route over areas
  local area = way:get_value_by_key("area")
  if ignore_areas and area and "yes" == area then
    return
  end

  result.forward_speed = 100
  result.backward_speed = 100


end

function turn_function (angle)
  ---- compute turn penalty as angle^2, with a left/right bias
  k = turn_penalty/(90.0*90.0)
  if angle>=0 then
    return angle*angle*k/turn_bias
  else
    return angle*angle*k*turn_bias
  end
end
