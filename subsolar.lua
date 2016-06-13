--
--    subsolar.lua
--    Copyright (C) 2014/2016 Okko Hartikainen <okko.hartikainen@gmail.com>
--
--    This program is free software: you can redistribute it and/or modify
--    it under the terms of the GNU General Public License as published by
--    the Free Software Foundation, either version 3 of the License, or
--    (at your option) any later version.
--
--    This program is distributed in the hope that it will be useful,
--    but WITHOUT ANY WARRANTY; without even the implied warranty of
--    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--    GNU General Public License for more details.
--
--    You should have received a copy of the GNU General Public License
--    along with this program.  If not, see <http://www.gnu.org/licenses/>.
--
--    Version: 1.1.3+post
--    Depends: conky-all, qdbus, librsvg2-bin, xmlstarlet, gmt, gmt-gshhg,
--    python3-ephem | python-ephem, geoclue-2.0, geographiclib-tools, 
--    fonts-cantarell, gnome-icon-theme-symbolic, gcalcli
--
--    Magnetic field dataset:
--    # geographiclib-get-magnetic wmm2015
--

require 'cairo'
--require 'strict'	-- checks uses of undeclared global variables

local colors = {
    foreground = {0.8, 0.8, 0.8, 1},
    background = {0, 0, 0, 1},
    outline = {0, 0, 0, 0},
    gray1 = {1, 1, 1, 0.1},
    gray2 = {1, 1, 1, 0.2},
    accent = {0x77/255, 0x66/255, 0x55/255, 1},
    map = {0, 0, 0, 0.33},
    graticule = {1, 1, 1, 0.033},
    }
local default_font = {
    family = "Cantarell",
    weight = CAIRO_FONT_WEIGHT_BOLD,
    slant = CAIRO_FONT_SLANT_NORMAL,
    color = colors.gray2,
    }
local icons = {
    media = "/usr/share/icons/gnome/scalable/mimetypes/" ..
        "audio-x-generic-symbolic.svg",
    }
local icon_size = 16 -- px
local panel_height = 28 -- px
local media_bar_vertical_alignment = 0.2
local clock_scale = 1
local clock_line_width
local clock_radius
local clock_secondary_radius
local clock_marker_length
local weather_api_key
local weather_days = 7
local weather_scale = 1
local weather_margin_x, weather_margin_y = 25, 50 -- px
local calendar_marks_whitelist = {"@gmail.com"}
local geolocation_fallback = {
    lat = 61.0745,
    lon = 24.5755,
    }
local geolocation_timeout = 10

local M_PI = math.pi
local MOON_RADIUS = 0.273 -- Earths
local EARTH_OBLIQUITY = 23.4
local SUBSOLAR_OWM_API_KEY = "a65f66be4ed52d8fc08e5a41f81b621a"

local sun_rise_angle, sun_set_angle = nil, nil
local center_x, center_y, gap_x = nil, nil, nil
local cr, extents = nil, nil
local is_first_run = true
local updates = nil
local scale
local tles = {}
local ephem, locationmap, subsolarmap, weather, calendar, geolocation

-------------------------------------------------------------------------------
--                                                                        Ephem
local function Ephem()
    local self = {}
    
    local function _unserialize(str)
        local e1, e2 = unpack(explode("; ", str, 2))
        
        -- recursive case
        if e2 then 
            local array = {}
            array[e1] = _unserialize(e2)
            return array
        end -- if
        
        -- terminating case
        if e1:find(": ") then
            local a, k, v = {}, nil, nil
            for _, p in pairs(explode(", ", e1)) do
                k, v = unpack(explode(": ", p))
                a[k] = v
            end
            return a
        else
            return e1
        end -- if
    end -- _unserialize
   
    function self.compute(lat, lon, tles)
        local command = 
            [[python$(python3 -c 'import ephem' 2> /dev/null && echo 3) -c "]] 
            .. dedent([[
            import ephem
            import ephem.stars
            import math

            current_utc = '$(date -u +'%Y/%m/%d %T')'
            next_solstice_utc = ephem.next_solstice(current_utc)
            sun = ephem.Sun(epoch='date')
            moon = ephem.Moon(epoch='date')
            greenwich = ephem.Observer()
            greenwich.lat = '51:28:36.7'
            greenwich.date = current_utc
            obs = ephem.Observer()
            obs.lat = ']] .. lat .. [['
            obs.lon = ']] .. lon .. [['
            obs.date = current_utc
            obs.pressure = 0

            # earth's obliquity
            sun.compute(next_solstice_utc)
            earth_obliquity = abs(sun.dec)
            print('earth_obliquity; %s' % (math.degrees(earth_obliquity)))

            # subsolar point
            sun.compute(current_utc)
            lon_subsolar = sun.ra - greenwich.sidereal_time()
            print('subsolar; lat: %s, lon: %s' % (
                math.degrees(sun.dec), 
                (math.degrees(lon_subsolar) + 180)%360 - 180))

            # sublunar point
            moon.compute(current_utc)
            lon_sublunar = moon.ra - greenwich.sidereal_time()
            print('sublunar; lat: %s, lon: %s' % (
                math.degrees(moon.dec), 
                (math.degrees(lon_sublunar) + 180)%360 - 180))
                
            # sun rising and setting times
            try:
                print('sunrise; %s' % (obs.previous_rising(sun)))
                print('sunset; %s' % (obs.next_setting(sun)))
            except ephem.AlwaysUpError:
                print('sunrise; always')
                print('sunset; always')
            except ephem.NeverUpError:
                print('sunrise; never')
                print('sunset; never')

            # angle of earth's rotation axis as seen from the sun
            print('earthrot; %s' % (
                -math.cos(sun.hlon)*math.degrees(earth_obliquity)))

            # planets visible with the unaided eye
            planets = {
                'Mercury': ephem.Mercury(obs),
                'Venus': ephem.Venus(obs),
                'Mars': ephem.Mars(obs),
                'Jupiter': ephem.Jupiter(obs),
                'Saturn': ephem.Saturn(obs),
                }
            for name in planets:
                print('planets; %s; alt: %s, az: %s' % (
                    name, 
                    math.degrees(planets[name].alt), 
                    math.degrees(planets[name].az)))

            # famous bright stars
            for line in ephem.stars.db.split('\n'):
                name = line.split(',')[0]     
                if name=='': break
                star = ephem.star(name)   
                star.compute(obs)
                print('stars; %s; alt: %s, az: %s' % (
                    name, 
                    math.degrees(star.alt), 
                    math.degrees(star.az)))
            ]])
        if tles then
            for k, v in pairs(tles) do
                command = command .. dedent([[
                    ]] .. k .. [[ = ephem.readtle(
                        ']] .. v[1] .. [[', 
                        ']] .. v[2] .. [[', 
                        ']] .. v[3] .. [[')
                    ]] .. k .. [[.compute(current_utc)
                    print('tles; ]] .. k .. [[; lat: %s, lon: %s' % (
                        math.degrees(]] .. k .. [[.sublat), 
                        math.degrees(]] .. k .. [[.sublong))) 
                    ]])
            end -- for
        end -- if
        command = command .. [["]]

        local file = io.popen(command)
        for line in file:lines() do
            table_merge(self, _unserialize(line))
        end -- for
        file:close()

        return self
    end -- compute

    -- return the instance
    return self
end -- Ephem

-------------------------------------------------------------------------------
--                                                                         text
local function text(str, args)
    local self = {}

    local args = args or {}
    local font_size = args.font_size or default_font.size
    local color = args.color or default_font.color
    local non_ascii_chars = args.non_ascii_chars or {}

    local function _setup(cr)
        cairo_select_font_face(
           cr, default_font.family, default_font.slant, default_font.weight)
        cairo_set_font_size(cr, font_size)
        cairo_set_source_rgba(cr, unpack(color))
    end -- _setup

    function self.center(cr, x, y)
        _setup(cr)
        cairo_text_extents(cr, str, extents)
        cairo_save(cr)
        cairo_translate(cr, 
            x - extents.width/2 - extents.x_bearing*2, 
            y - extents.y_bearing/2)
        cairo_show_text(cr, str)
        cairo_restore(cr)
        cairo_stroke(cr)
    end -- center

    function self.to_arc(cr, r, sign, rotation, x, y)
        _setup(cr)
        cairo_font_extents(cr, font_extents)
        local font_extents_height = font_extents.height
        local vcenter = 1
        x, y = x or center_x, y or center_y
        local rotation = rotation or 0
        
        cairo_text_extents(cr, str, extents)
        cairo_save(cr)
        cairo_translate(cr, x, y)
        cairo_rotate(cr, -sign*(extents.width/r)/2 + rotation)

        local advance = 0
        local char = nil
        for i = 1, #str do
            char = non_ascii_chars[i] or str:sub(i, i)
            cairo_text_extents(cr, char, extents)
            cairo_rotate(cr, advance)
            advance = sign*math.asin(extents.x_advance/r)
            cairo_move_to(
                cr, 0, -r*sign + (font_extents_height/2)*(math.abs((sign-1)/2))
                + vcenter*sign*font_extents_height/4)
            cairo_show_text(cr, char)
        end -- for

        cairo_restore(cr)
        cairo_stroke(cr)
    end -- to_arc
        
    -- return the instance
    return self
end -- text

-------------------------------------------------------------------------------
--                                                               OpenWeatherMap
local OpenWeatherMap = {}
OpenWeatherMap.__index = OpenWeatherMap

setmetatable(OpenWeatherMap, {
    __call = function(cls, ...)
        local self = setmetatable({}, cls)
        self:_init(...)
        return self
    end, -- __call
    })

function OpenWeatherMap:_init(api_key)
    self.api_key = api_key
    self.forecast = {}
    self.scale = 7*scale*weather_scale
end -- _init

function OpenWeatherMap:draw_weather_condition_symbol(code, x, y)
    -- http://openweathermap.org/weather-conditions
    local s = self.scale/2
    cairo_set_line_width(cr, 1)

    -- thunder
    if code >= 200 and code <= 299 then
        cairo_set_source_rgba(cr, unpack(colors.foreground))
        cairo_arc(cr, x, y, s*0.1, 0, 2*M_PI)
        cairo_fill(cr)
        cairo_save(cr)
        for i = 1, 3 do
            cairo_translate(cr, x, y)
            cairo_rotate(cr, 120*M_PI/180)
            cairo_translate(cr, -x, -y)
            cairo_move_to(cr, x, y)
            cairo_line_to(cr, x, y - s*0.7)
            cairo_stroke(cr)
        end -- for
        cairo_restore(cr)

    -- drizzle
    elseif code >= 300 and code <= 399 then
        cairo_set_source_rgba(cr, unpack(colors.accent))
        cairo_arc(cr, x - s*0.2, y - s*0.2, s*0.05, 0, 2*M_PI)
        cairo_fill(cr)
        cairo_arc(cr, x + s*0.2, y - s*0.2, s*0.05, 0, 2*M_PI)
        cairo_fill(cr)
        cairo_arc(cr, x - s*0.2, y + s*0.2, s*0.05, 0, 2*M_PI)
        cairo_fill(cr)
        cairo_arc(cr, x + s*0.2, y + s*0.2, s*0.05, 0, 2*M_PI)
        cairo_fill(cr)

    -- rain
    elseif code == 500 then
        cairo_set_source_rgba(cr, unpack(colors.accent))
        cairo_arc(cr, x, y, s*0.1, 0, 2*M_PI)
        cairo_fill(cr)
    elseif code == 501 then
        cairo_set_source_rgba(cr, unpack(colors.accent))
        cairo_arc(cr, x, y, s*0.3, 0, 2*M_PI)
        cairo_fill(cr)
    elseif code >= 502 and code <= 599 then
        cairo_set_source_rgba(cr, unpack(colors.accent))
        cairo_arc(cr, x, y, s*0.5, 0, 2*M_PI)
        cairo_fill(cr)

    -- snow
    elseif code >= 600 and code <=699 then
        cairo_set_source_rgba(cr, unpack(colors.foreground))
        cairo_arc(cr, x, y, s*0.1, 0, 2*M_PI)
        cairo_fill(cr)
        cairo_set_source_rgba(cr, unpack(colors.gray2))
        cairo_arc(cr, x, y, s*0.3, 0, 2*M_PI)
        cairo_stroke(cr)
        if code >= 601 then
            cairo_set_source_rgba(cr, unpack(colors.gray2))
            cairo_arc(cr, x, y, s*0.5, 0, 2*M_PI)
            cairo_stroke(cr)
        end -- if
        if code >= 602 then
            cairo_set_source_rgba(cr, unpack(colors.gray2))
            cairo_arc(cr, x, y, s*0.7, 0, 2*M_PI)
            cairo_stroke(cr)
        end -- if

    -- atmosphere
    elseif code >= 700 and code <= 799 then
        cairo_set_source_rgba(cr, unpack(colors.gray1))
        cairo_save(cr)
        cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
        cairo_set_line_width(cr, s*0.15)
        cairo_move_to(cr, x - s*0.3, y - s*0.3)
        cairo_rel_line_to(cr, s*0.6, 0)
        cairo_move_to(cr, x - s*0.3, y)
        cairo_rel_line_to(cr, s*0.6, 0)
        cairo_move_to(cr, x - s*0.3, y + s*0.3)
        cairo_rel_line_to(cr, s*0.6, 0)
        cairo_stroke(cr)
        cairo_restore(cr)

    -- extreme/additional
    elseif code > 899 and code < 1000 then
        cairo_set_line_width(cr, 2)
        cairo_set_source_rgba(cr, unpack(colors.foreground))
        cairo_arc(cr, x, y, s*0.5, 0, 2*M_PI)
        cairo_stroke(cr)
    end -- if
end -- draw_weather_condition_symbol

function OpenWeatherMap:request_forecast(lat, lon)
    self.expired = true
    self.tmpfile = os.tmpname()
    local command = "(wget -qO " .. self.tmpfile .. 
        " 'http://api.openweathermap.org/data/2.5/forecast/daily?" ..
        "lat=" .. lat .. "&lon=" .. lon .. "&APPID=" .. self.api_key .. 
        "&mode=xml&units=metric') &"
    os.execute(command)
end -- request_forecast

function OpenWeatherMap:extract_forecast()
    if os.execute("[ -f " .. self.tmpfile .. 
            " ] && ! lsof -S 2 " .. self.tmpfile) then
        self.forecast = {}
        local command = "xmlstarlet sel -t " .. 
            "-v 'weatherdata/forecast/time/@day' " .. self.tmpfile
        local temperature, symbol = nil, nil
        local file = io.popen(command)
        for line in file:lines() do
            command = "xmlstarlet sel -t " ..
                "-v 'weatherdata/forecast/time[@day=" .. '"' .. line ..'"' ..
                "]/temperature/@day' -n " .. 
                "-v 'weatherdata/forecast/time[@day=" .. '"' .. line ..'"' ..
                "]/symbol/@number' " .. self.tmpfile
            local file2 = io.popen(command)
            temperature = file2:read("*l") -- daily averaged temperature
            symbol = file2:read("*l")
            file2:close()
            table.insert(self.forecast, {
                date = line,
                temperature = temperature,
                symbol = symbol,
                })
        end -- for
        file:close()
        os.remove(self.tmpfile)
        self.expired = false
    end -- if
end -- extract_forecast

function OpenWeatherMap:sync()
    if self.expired then
        self:extract_forecast()
    end -- if
    return self
end -- sync

function OpenWeatherMap:draw()
    local s = self.scale
    local days = math.min(weather_days, #self.forecast)
    local weather_x = conky_window.width - gap_x - s*days - weather_margin_x
    local weather_y = conky_window.height - s*3 - weather_margin_y

    -- grid
    cairo_set_source_rgba(cr, unpack(colors.gray1))
    cairo_set_line_width(cr, 1)
    for i = 1, days - 2 do
        cairo_move_to(cr, weather_x + i*s, weather_y)
        cairo_rel_line_to(cr, 0, s*3)
    end -- for
    cairo_move_to(cr, weather_x, weather_y + s)
    cairo_rel_line_to(cr, (days - 1)*s, 0)
    cairo_move_to(cr, weather_x, weather_y + 2*s)
    cairo_rel_line_to(cr, (days - 1)*s, 0)
    cairo_stroke (cr)

    if next(self.forecast) ~= nil then
        -- date numbers
        local date = nil
        for i = 2, days - 1 do
            date = self.forecast[i]["date"]:sub(-2)
            if tonumber(date) == tonumber(os.date("%d")) then
                date = date .. "•"
            end
            text(date).center(cr, weather_x + (i - 1)*s, weather_y - s*0.5)
        end -- for

        -- max/min temperatures
        local temperatures = {}
        for i = 1, days do 
            table.insert(temperatures, self.forecast[i]["temperature"])
        end -- for
        local max_temperature = math.floor(math.max(unpack(temperatures)))
        local min_temperature = math.floor(math.min(unpack(temperatures)))
        if max_temperature == min_temperature then 
            max_temperature = max_temperature + 1
            min_temperature = min_temperature - 1
        end -- if
        text(string.format("%+d", max_temperature)).center(cr, 
            weather_x + (days - 0.5)*s, 
            weather_y + s)
        text(string.format("%+d", min_temperature)).center(cr,
            weather_x + (days - 0.5)*s, 
            weather_y + 2*s)

        -- temperature graph, weather condition symbols
        local vx, vy = {}, {}
        for i = 1, days do
            table.insert(vx, weather_x - s + s*i)
            table.insert(vy, weather_y + s 
                - math.floor(self.forecast[i]["temperature"]
                - max_temperature)*s/(max_temperature
                - min_temperature))

            -- weather condition symbol
            if self.forecast[i]["symbol"] then
                self:draw_weather_condition_symbol(
                    tonumber(self.forecast[i]["symbol"]), 
                    weather_x - s + s*i,
                    weather_y + s*2.5)
            end -- if
        end -- for
        bezier_spline(cr, vx, vy)
        cairo_set_source_rgba(cr, unpack(colors.gray2))
        cairo_set_line_width(cr, 1)
        cairo_stroke(cr)
    end -- if
end -- draw

function OpenWeatherMap:cleanup()
    os.remove(self.tmpfile)
end -- cleanup

-------------------------------------------------------------------------------
--                                                              OrthographicMap
local OrthographicMap = {}
OrthographicMap.__index = OrthographicMap

setmetatable(OrthographicMap, {
    __call = function(cls, ...)
        local self = setmetatable({}, cls)
        self:_init(...)
        return self
    end, -- __call
    })

function OrthographicMap:_init()
    self.postscript_file = os.tmpname()
    self.png_file = self.postscript_file .. ".png"
end -- _init

function OrthographicMap:create_projection(lat, lon, r, color)
    self.cache_expired = true
    self.gmt_lat = lat
    self.gmt_lon = lon
    self.gmt_r = r
    self.color = color
    local command = "(gmt pscoast --MAP_ORIGIN_X=0i --MAP_ORIGIN_Y=0i " ..
        "--PS_MEDIA=1ix1i -Rg -JG" .. lon .. "/" .. lat .. 
        "/1i -Dc -A1000 -G" .. color[1]*255 .. "/" .. color[2]*255 .. "/" .. 
        color[3]*255 .. " -P > " .. self.postscript_file .. 
        " && gmt psconvert " .. self.postscript_file .. " -E" .. r*2 .. 
        " -TG -F" .. self.png_file .. ") &"
    os.execute(command)
end -- create_projection

function OrthographicMap:update_cache()
    local image = cairo_image_surface_create_from_png(self.png_file)
    if cairo_surface_status(image) == CAIRO_STATUS_SUCCESS then
        os.remove(self.postscript_file)
        os.remove(self.png_file)
        local size = cairo_image_surface_get_width(image) 
        if size > self.gmt_r*2 - 1 and size < self.gmt_r*2 + 1 then
            self.size = size
            self.cache_expired = false
            cairo_surface_destroy(self.cache)
            self.cache = image
            cairo_surface_reference(image)
        else -- reject and recreate ill-proportioned projections
            self:create_projection(
                self.gmt_lat, self.gmt_lon, self.gmt_r, self.color)
        end -- if
    end -- if
    cairo_surface_destroy(image)
end -- update_cache

function OrthographicMap:sync()
    if self.cache_expired then
        self:update_cache()
    end -- if
    return self
end -- sync

function OrthographicMap:draw(cr, x, y, rotation)
    self.lat = self.gmt_lat
    self.lon = self.gmt_lon
    self.r = self.gmt_r
    self.x = x
    self.y = y
    self.rotation = rotation
    if self.cache then
        cairo_save(cr)
        cairo_translate(cr, x - self.size/2, y - self.size/2)
        if rotation then
            cairo_translate(cr, self.size/2, self.size/2)
            cairo_rotate(cr, math.rad(rotation))
            cairo_translate(cr, -self.size/2, -self.size/2)
        end
        cairo_set_source_surface(cr, self.cache, 0, 0)
        cairo_paint_with_alpha(cr, self.color[4])
        cairo_restore(cr)
    end -- if
    return self
end -- draw

-- https://en.wikipedia.org/wiki/Orthographic_projection_in_cartography
function OrthographicMap:compute_formulas(lat, lon)
    local lat_origin = math.rad(self.lat or self.gmt_lat or 0)
    local lon_origin = math.rad(self.lon or self.gmt_lon or 0)
    local r = self.r or self.gmt_r or 1
    local x = r*math.cos(lat)*math.sin(lon - lon_origin)
    local y = r*(math.cos(lat_origin)*math.sin(lat)
        - math.sin(lat_origin)*math.cos(lat)*math.cos(lon - lon_origin))
    local cos_c = math.sin(lat_origin)*math.sin(lat) 
        + math.cos(lat_origin)*math.cos(lat)*math.cos(lon - lon_origin)
    return x, y, cos_c
end -- compute_formulas

-- Orthographic projection of a circle of a sphere. All circles plot as
-- ellipses or straight lines.
function OrthographicMap:project_circle(cr, r_circle, lat, lon, color)
    lat = math.rad(lat)
    lon = math.rad(lon)
    local r = self.r or self.gmt_r or 1
    r_circle = r*r_circle
    local map_x = self.x or 0
    local map_y = self.y or 0
    local map_rotation = self.rotation or 0
    local linewidth = 1

    local x, y, cos_c = self:compute_formulas(lat, lon)
    local p = math.sqrt(x^2 + y^2)

    -- polar coordinates
    local y_e = r*math.sin(math.acos(r_circle/r))*(p/r)
    local angle = math.asin(x/p)
    if y < 0 then angle = M_PI - angle end
    if x < 0 then angle = M_PI*2 + angle end

    -- semi-major and semi-minor axes
    local a = r_circle
    local b = r_circle*math.sin(math.acos(p/r))

    --[[
    "An ellipse intersects a circle in 0, 1, 2, 3, or 4 points. The points of
    intersection of a circle of center (x_0,y_0) and radius r with an ellipse 
    of semi-major and semi-minor axes a and b, respectively and center 
    (x_e,y_e) can be determined by simultaneously solving 
    (x-x_0)^2+(y-y_0)^2=r^2                                                (1)
    ((x-x_e)^2)/(a^2)+((y-y_e)^2)/(b^2)=1.                                 (2)"
    -- Weisstein, Eric W. "Circle-Ellipse Intersection." From MathWorld--A 
    Wolfram Web Resource. 
    http://mathworld.wolfram.com/Circle-EllipseIntersection.html 

    If x_0 = y_0 = x_e = 0, then (r^2-y^2)/a^2 + (y-y_e)^2/b^2 = 1.

    $ maxima --very-quiet
    string(solve((r^2-y^2)/a^2 + (y-y_e)^2/b^2 = 1, y));
     [y = (b*sqrt(a^2*y_e^2+(b^2-a^2)*r^2-a^2*b^2+a^4)-a^2*y_e)/(b^2-a^2),\
    y = -(b*sqrt(a^2*y_e^2+(b^2-a^2)*r^2-a^2*b^2+a^4)+a^2*y_e)/(b^2-a^2)]
    --]]
    r = 0.9999*r
    local y_i = (b*math.sqrt(a^2*y_e^2 + (b^2 - a^2)*r^2 - a^2*b^2 + a^4) 
                - a^2*y_e)/(b^2 - a^2)
    local x_i = math.sqrt(r^2 - y_i^2)

    if not (y_i > y_e + b and cos_c < 0) or b == 0 or a == 0 then
        cairo_save(cr)
        cairo_translate(cr, map_x, map_y)
        cairo_rotate(cr, math.rad(map_rotation))
        if angle > 0 then
            cairo_rotate(cr, angle)
        end -- if
        cairo_translate(cr, -map_x, -map_y)

        -- clip
        if not (y_i > y_e + b) and a ~= 0 and b ~= 0 then
            if cos_c < 0 then
                cairo_move_to(cr, map_x - x_i - linewidth, map_y - y_i)
                cairo_rel_line_to(cr, x_i*2  + linewidth*2, 0)
                cairo_rel_line_to(cr, 0, y_i - y_e - b - linewidth/2)
                cairo_rel_line_to(cr, -(x_i*2  + linewidth*2), 0)
                cairo_rel_line_to(cr, 0, -(y_i - y_e - b - linewidth/2))
                cairo_clip(cr)
            else
                cairo_move_to(cr, map_x - a - linewidth/2, map_y - y_i)
                cairo_rel_line_to(cr, a*2  + linewidth, 0)
                cairo_rel_line_to(cr, 0, y_i - y_e + b + linewidth/2)
                cairo_rel_line_to(cr, -(a*2  + linewidth), 0)
                cairo_rel_line_to(cr, 0, -(y_i - y_e + b + linewidth/2))
                cairo_clip(cr)
            end -- if
        end -- if 

        cairo_set_source_rgba(cr, unpack(color))
        cairo_set_line_width(cr, linewidth)
        cairo_translate(cr, map_x, map_y - y_e)
        if b == 0 then
            cairo_move_to(cr, 0 - a, 0)
            cairo_line_to(cr, 0 + a, 0)
        elseif a == 0 then
            cairo_move_to(cr, 0, 0 - b)
            cairo_line_to(cr, 0, 0 + b) 
        else
            ellipse(cr, 0, 0, a*2, b*2)
        end
        cairo_stroke(cr)
        cairo_restore(cr)
    end -- if
end -- project_circle

function OrthographicMap:graticule(cr, color)
    cairo_push_group(cr)
    cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE)
    local r_lat = nil
    for i = 10, 80, 10 do
        r_lat = math.sin(math.rad(i))
        self:project_circle(cr, r_lat, 90, 0, color)
        self:project_circle(cr, r_lat, -90, 0, color)
    end -- for
    self:project_circle(cr, 1, 90, 0, color)
    for i = 0, 170, 10 do
        self:project_circle(cr, 1, 0, i, color)
    end -- for
    cairo_pop_group_to_source(cr)
    cairo_paint(cr)
end -- graticule

function OrthographicMap:cleanup()
    os.remove(self.postscript_file)
    os.remove(self.png_file)
end -- cleanup

-------------------------------------------------------------------------------
--                                                                MagneticField
--
--[[
"Does the compass needle point toward the magnetic pole?

No. The compass points in the directions of the horizontal component of the 
magnetic field where the compass is located, and not to any single point."
-- http://www.ngdc.noaa.gov/geomag/faqgeom.shtml
--]]

local MagneticField = {}
MagneticField.__index = MagneticField

setmetatable(MagneticField, {
    __call = function(cls, ...)
        local self = setmetatable({}, cls)
        self:_init(...)
        return self
    end, -- __call
    })

function MagneticField:_init(...)
    self:update(...)
end -- _init

function MagneticField:update(lat, lon)
    local command = "echo $(date +%F) " .. lat .. " " .. lon .. 
        " | MagneticField | cut -f1 -d' '"
    local file = io.popen(command)
    self.magnetic_declination = tonumber(file:read("*l"))
    file:close()
end -- update

function MagneticField:draw_magnetic_declination()
    if self.magnetic_declination then
        cairo_save(cr)
        cairo_translate(cr, center_x, center_y)
        cairo_rotate(cr, self.magnetic_declination*M_PI/180)
        cairo_set_line_width(cr, 1)
        cairo_set_source_rgba(cr, unpack(colors.gray1))
        cairo_move_to(cr, 0, -clock_radius - clock_line_width/2)
        cairo_rel_line_to(cr, 0, -clock_line_width)
        cairo_stroke(cr)
        cairo_translate(cr, -center_x, -center_y)
        text("MD", {font_size = (11/15)*clock_line_width})
            .to_arc(cr, clock_radius, 1)
        cairo_restore(cr)
    end -- if
end -- draw_magnetic_declination

-------------------------------------------------------------------------------
--                                                                     Calendar
local Calendar = {}
Calendar.__index = Calendar

setmetatable(Calendar, {
    __call = function(cls, ...)
        local self = setmetatable({}, cls)
        self:_init(...)
        return self
    end, -- __call
    })

function Calendar:_init()
    self.marks = {}
    self.tmpfile = os.tmpname()
end -- _init

function Calendar:request_marks(...)
    self.marks_expired = true
    self.marks_month = os.date("%m")
    local command = [[(test -e ~/.gcalcli_oauth && echo "$(gcalcli]]
    for _, v in ipairs(arg) do
        command = command .. [[ --calendar "]] .. v .. [["]]
    end
    command = command .. [[ --tsv agenda]] ..
        [[ 1 $(date -d "-$(date +%d) days +1 month" "+%d")]] .. 
        [[ | cut -f 1 | uniq | date +%d -f -)\nEOF" > ]] .. 
        self.tmpfile .. [[) &]]
    os.execute(command)
end -- request_marks

function Calendar:update_marks()
    local file = io.open(self.tmpfile, "r")
    if file then
        self.marks = {}
        for line in file:lines() do
            if type(tonumber(line)) == "number" then
                self.marks[tonumber(line)] = true
            elseif line == "EOF" then
                os.remove(self.tmpfile)
                self.marks_expired = false
            end -- if    
        end -- for
    end -- if
    file:close()
end -- update_marks

function Calendar:sync()
    if self.marks_month ~= os.date("%m") then
        self.marks_expired = true
    end -- if
    if self.marks_expired then
        self:update_marks()
    end -- if
    return self
end -- sync

function Calendar:draw()
    local cal_size = math.min(conky_window.height*(55/1050),
        conky_window.width*(55/1680))
    local cal_radius = cal_size*(20/55)
    local cal_x = center_x - (4 + 1.5)*cal_size - clock_radius 
                  - clock_marker_length
    local cal_y = center_y

    -- get first weekday, first week and last day of current month etc.
    local command = 'date -d "-$(date +%d) days +1 day" "+%u" && ' ..
        'date -d "-$(date +%d) days +1 day" "+%V" && ' ..
        'date -d "-$(date +%d) days +1 month" "+%d" && ' ..
        'date -d "$(($(date +%Y)+1))-01-01 -1 day" +%V'
    local file = io.popen(command)
    local first_weekday = tonumber(file:read("*l"))
    local first_week = tonumber(file:read("*l"))
    local last_day = tonumber(file:read("*l"))
    local last_week_of_year = tonumber(file:read("*l"))
    file:close()

    -- draw days
    local weekday = first_weekday
    local row = 1
    for i = 1, last_day do

        -- circle
        cairo_set_source_rgba(cr, unpack(colors.gray1))
        if weekday > 5 then
            cairo_set_line_width(cr, 2)
        else 
            cairo_set_line_width(cr, 1)
        end -- if
        cairo_arc(cr, 
            cal_x + weekday*cal_size, 
            cal_y + row*cal_size, cal_radius, 0, 2*M_PI)
        if i == tonumber(os.date("%d")) then
            cairo_fill(cr)
        else
            cairo_stroke(cr)
        end -- if

        -- mark
        if self.marks_month == os.date("%m") and self.marks[i] then
            cairo_set_source_rgba(cr, unpack(colors.gray2))
            cairo_arc(cr, 
                cal_x + weekday*cal_size, 
                cal_y + row*cal_size + cal_radius/1.8, 2, 0, 2*M_PI)
            cairo_fill(cr)
        end -- if
        
        -- number
        text(i, {font_size = (10/55)*cal_size}).center(cr, 
            cal_x + weekday*cal_size, cal_y + row*cal_size)

        weekday = weekday + 1
        if weekday > 7 then
            weekday = 1
            row = row + 1
        end -- if
    end -- for

    -- draw week numbers
    if last_day%7 == (7 - (first_weekday - 1))%7 then row = row - 1 end
    for i = 1, row do
        if first_week + i - 2 == last_week_of_year then first_week = 2 - i end
        text(first_week + i - 1, {font_size = (10/55)*cal_size}).center(cr,
            cal_x, cal_y + i*cal_size)
    end -- for

    -- draw date (ISO 8601)
    text(os.date("%Y-%m-%d")).center(cr, cal_x + 4*cal_size, cal_y)
end -- draw

function Calendar:cleanup()
    os.remove(self.tmpfile)
end -- cleanup

-------------------------------------------------------------------------------
--                                                                  Geolocation
local function Geolocation()
    local self = setmetatable({}, {
        __index = {
            lat = geolocation_fallback.lat,
            lon = geolocation_fallback.lon,
            }
        })
    
    local tmpfile = os.tmpname()
    local previous_lat, previous_lon

    function self.locate(timeout)
        local command = "(/usr/lib/geoclue-2.0/demos/where-am-i -t " ..
            timeout .. " | fgrep itude | paste -s" ..
            " | sed -e 's#Longitude#/#' -e 's/[^0-9./]*//g'" .. 
            " > " .. tmpfile .. ") &"
        os.execute(command)
    end -- locate

    function self.sync()
        local file = io.open(tmpfile, "r")
        local lat, lon
        if pcall(function()
                lat, lon = unpack(explode("/", file:read("*l")))
                end) then
            previous_lat, previous_lon = self.lat, self.lon
            self.lat, self.lon = tonumber(lat), tonumber(lon)
        end -- if
        file:close()
        return self
    end -- sync

    function self.is_changed()
        if self.lat == previous_lat and self.lon == previous_lon then
            return false
        else
            return true
        end -- if
    end -- is_changed

    function self.draw()
        local lat = string.format("%.4f", self.lat)
        local lon = string.format("%.4f", self.lon)
        local d1 = lat:len() + 1
        local d2 = d1 + lon:len() + 1 + 2
        text(lat .. " , " .. lon .. " ", 
            {font_size = (11/15)*clock_line_width, 
            non_ascii_chars = {[d1] = "°", [d2] = "°"}})
            .to_arc(cr, clock_radius, -1)
    end -- draw

    function self.cleanup()
        os.remove(tmpfile)
    end -- cleanup
    
    return self
end -- Geolocation

-------------------------------------------------------------------------------
--                                                                  get_iss_tle
function get_iss_tle()
    local command = "wget -qO - " .. 
        "http://www.celestrak.com/NORAD/elements/stations.txt" ..
        " | grep -A 2 ISS"
    local file = io.popen(command)
    local name = trim(file:read("*l"))
    local line1 = trim(file:read("*l"))
    local line2 = trim(file:read("*l"))
    file:close()
    tles.iss = {name, line1, line2}
end -- get_iss_tle()

-------------------------------------------------------------------------------
--                                                                        stars
function stars()
    for k, v in pairs(ephem.stars or {}) do
        if tonumber(v.alt) > 0  then        
            cairo_save(cr)
            cairo_translate(cr, center_x, center_y)
            cairo_rotate(cr, math.rad(v.az))
            cairo_translate(cr, -center_x, -center_y)

            -- circle
            cairo_set_source_rgba(cr, unpack(colors.foreground))
            cairo_arc(cr, center_x, center_y 
                - clock_radius - clock_line_width/2 
                - ((clock_marker_length-0.3*scale-clock_line_width/2)/90)*v.alt
                - 0.3*scale, math.max(0.075*scale, 0.5), 0, 2*M_PI)
            cairo_fill(cr)

            -- text
            local sign, rot = nil, nil
            if tonumber(v.az) > 270 or tonumber(v.az) < 90 then
                sign = 1
                rot = 0
            else
                sign = -1
                rot = M_PI
            end
            cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE)
            text(k, {font_size = (10/14)*default_font.size, 
                color = colors.gray1}).to_arc(cr, clock_radius 
                + clock_line_width/2 
                + ((clock_marker_length-0.3*scale-clock_line_width/2)/90)*v.alt
                + 1.2*scale, sign, rot)

            cairo_restore(cr)
        end -- if
    end -- for
end -- stars

-------------------------------------------------------------------------------
--                                                                      planets
function planets()
    for k, v in pairs(ephem.planets or {}) do
        if tonumber(v.alt) > 0 then        
            cairo_save(cr)
            cairo_translate(cr, center_x, center_y)
            cairo_rotate(cr, math.rad(v.az))
            cairo_translate(cr, -center_x, -center_y)
    
            -- circle
            cairo_set_source_rgba(cr, unpack(colors.foreground))
            cairo_arc(cr, center_x, center_y 
                - clock_radius - clock_line_width/2 
                - ((clock_marker_length-0.3*scale-clock_line_width/2)/90)*v.alt
                - 0.3*scale, 0.3*scale, 0, 2*M_PI)
            cairo_fill(cr)

            -- text
            local sign, rot = nil, nil
            if tonumber(v.az) > 270 or tonumber(v.az) < 90 then
                sign = 1
                rot = 0
            else
                sign = -1
                rot = M_PI
            end -- if
            text(k).to_arc(cr, 
                clock_radius + clock_line_width/2 
                + ((clock_marker_length-0.3*scale-clock_line_width/2)/90)*v.alt
                + 1.5*scale, sign, rot)

            cairo_restore(cr)
        end -- if
    end -- for
end -- planets

-------------------------------------------------------------------------------
--                                                    calculate_twilight_angles
function calculate_twilight_angles()
    if pcall(function()
            if ephem.sunrise == "never" then
                sun_rise_angle = 0
                sun_set_angle = 0
            elseif ephem.sunrise == "always" then
                sun_rise_angle = 0
                sun_set_angle = 360
            else
                local command = "echo '" .. ephem.sunrise .. "\\n" .. 
                    ephem.sunset .. "' | date -u +'%FT%T%z' -f -" .. 
                    " | date +'%T' -f -"
                local file = io.popen(command)
                local sun_rise_time = file:read("*l")
                local sun_set_time = file:read("*l")
                file:close()
                if sun_rise_time and sun_set_time then
                    sun_rise_angle = (
                        sun_rise_time:sub(1, 2)*60*60 
                        + sun_rise_time:sub(4, 5)*60
                        + sun_rise_time:sub(7, 8))*(360/86400)
                    sun_set_angle = (
                        sun_set_time:sub(1, 2)*60*60 
                        + sun_set_time:sub(4, 5)*60
                        + sun_set_time:sub(7, 8))*(360/86400)
                end -- if
            end -- if
            end) then
    else
    end -- if pcall            
end -- calculate_twilight_angles

-------------------------------------------------------------------------------
--                                                                   draw_clock
function draw_clock()
    -- get time and calculate angles
    local hours24 = tonumber(os.date("%H"))
    local hours12 = tonumber(os.date("%I"))
    local minutes = tonumber(os.date("%M"))
    local seconds = tonumber(os.date("%S"))
    local hours24_angle = (hours24*60*60 + minutes*60 + seconds)*(360/86400)
    local hours12_angle = (hours12*60*60 + minutes*60 + seconds)*(360/43200)
    local minutes_angle = (minutes*60 + seconds)*0.1
    local seconds_angle = seconds*6

    -- background
    cairo_set_source_rgba(cr, unpack(colors.gray1))
    cairo_set_line_width(cr, clock_line_width)
    cairo_arc(cr, center_x, center_y, clock_radius, 0, 2*M_PI)
    cairo_stroke(cr)

    cairo_set_line_width(cr, 1)
    cairo_move_to(cr, 
        center_x + clock_radius - clock_marker_length, 
        math.floor(center_y + 0.5))
    cairo_rel_line_to(cr, clock_marker_length*2, 0)
    cairo_move_to(cr, 
        center_x - clock_radius - clock_marker_length,
        math.floor(center_y + 0.5))
    cairo_rel_line_to(cr, clock_marker_length*2, 0)
    cairo_move_to(cr, 
        math.floor(center_x + 0.5), 
        center_y + clock_radius - clock_marker_length)
    cairo_rel_line_to(cr, 0, clock_marker_length*2)
    cairo_move_to(cr, 
        math.floor(center_x + 0.5), 
        center_y - clock_radius - clock_marker_length)
    cairo_rel_line_to(cr, 0, clock_marker_length*2)
    cairo_stroke(cr)
    
    cairo_set_source_rgba(cr, unpack(colors.gray2))
    cairo_set_line_width(cr, 1)
    local angles = {30, 60, 120, 150, 210, 240, 300, 330}
    for _, angle in ipairs(angles) do
        cairo_move_to(cr, 
            center_x 
            + (clock_radius + clock_line_width)*math.sin(angle*M_PI/180), 
            center_y 
            - (clock_radius + clock_line_width)*math.cos(angle*M_PI/180))
        cairo_line_to(cr, 
            center_x 
            + (clock_radius + 2*clock_line_width)*math.sin(angle*M_PI/180), 
            center_y 
            - (clock_radius + 2*clock_line_width)*math.cos(angle*M_PI/180))
    end -- for
    cairo_stroke(cr)
    for i = 1, #angles, 2 do
        cairo_arc(cr, center_x, center_y, clock_radius + 1.5*clock_line_width, 
            angles[i]*M_PI/180, angles[i + 1]*M_PI/180)
        cairo_stroke(cr)
    end -- for
    
    -- 24 hour clock
    if not sun_rise_angle or not sun_set_angle then
        sun_rise_angle, sun_set_angle = 0, 360
    end -- if
    local rotation = 180
    cairo_set_line_width(cr, 0.75)
    cairo_set_source_rgba(cr, unpack(colors.gray1))
    cairo_save(cr)
    cairo_translate(cr,
        center_x + clock_radius + clock_marker_length + clock_secondary_radius,
        center_y)
    cairo_arc(cr, 0, 0, clock_secondary_radius, 0, 2*M_PI)
    cairo_stroke(cr)
    cairo_set_line_width(cr, scale/2)
    cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE)
    cairo_arc(cr, 0, 0, 0.9*clock_secondary_radius,
        (rotation + 90 + sun_rise_angle)*M_PI/180,
        (rotation + 90 + sun_set_angle)*M_PI/180)
    cairo_stroke(cr)
    cairo_set_source_rgba(cr, unpack(colors.foreground))
    cairo_arc(cr, 
        0 - 0.9*clock_secondary_radius*math.sin((rotation 
        + hours24_angle)*M_PI/180), 
        0 + 0.9*clock_secondary_radius*math.cos((rotation 
        + hours24_angle)*M_PI/180), scale*0.2, 0, 2*M_PI)
    cairo_fill(cr)
    cairo_restore(cr)

    -- 12 hour clock
    cairo_set_source_rgba(cr, unpack(colors.foreground))
    cairo_save(cr)
    cairo_translate(cr, 
        center_x + clock_radius*math.sin(hours12_angle*M_PI/180),
        center_y - clock_radius*math.cos(hours12_angle*M_PI/180))
    cairo_rotate(cr, (180 + hours12_angle)*M_PI/180)
    cairo_translate(cr, -2*scale, -2.5*scale - clock_line_width/2)
    cairo_move_to(cr, 0, 0)
    cairo_line_to(cr, 2*scale, 2*scale)
    cairo_line_to(cr, 4*scale, 0)
    cairo_fill(cr)
    cairo_restore(cr)

    -- minutes
    cairo_set_source_rgba(cr, unpack(colors.foreground))
    cairo_save(cr)
    cairo_translate(cr, 
        center_x + clock_radius*math.sin(minutes_angle*M_PI/180),
        center_y - clock_radius*math.cos(minutes_angle*M_PI/180))
    cairo_arc(cr, 0, 0, clock_line_width/3, 0, 2*M_PI)
    cairo_fill(cr)

    -- seconds
    cairo_push_group(cr)
    cairo_set_source_rgba(cr, unpack(colors.gray1))
    cairo_set_line_width(cr, 0.75)
    cairo_arc(cr, 0, 0, clock_secondary_radius, 0, 2*M_PI)
    cairo_stroke(cr)
    cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE)
    for i = 0, 360, 90 do
        cairo_arc(cr, 
            0 + clock_secondary_radius*math.sin(i*M_PI/180),
            0 - clock_secondary_radius*math.cos(i*M_PI/180), 
            scale*0.2, 0, 2*M_PI)
        cairo_fill(cr)
    end -- for
    cairo_pop_group_to_source(cr)
    cairo_paint(cr)
    cairo_set_source_rgba(cr, unpack(colors.foreground))
    cairo_arc(cr, 
        0 + clock_secondary_radius*math.sin(seconds_angle*M_PI/180),
        0 - clock_secondary_radius*math.cos(seconds_angle*M_PI/180), 
        scale*0.2, 0, 2*M_PI)
    cairo_fill(cr)
    cairo_restore(cr)
end -- draw_clock

-------------------------------------------------------------------------------
--                                                                    media_bar
function media_bar()
    -- get current track
    local mpris2_metadata = get_mpris2_metadata()
    local artist = mpris2_metadata["xesam:artist"]
    local title = mpris2_metadata["xesam:title"]

    if artist and title then
        local text = artist .. ": " .. title
        cairo_select_font_face(
            cr, default_font.family, default_font.slant, default_font.weight)
        cairo_set_font_size(cr, panel_height/2)
        cairo_text_extents(cr, text, extents)

        -- draw sidebar
        local horizontal_padding = 14
        local vertical_padding = 2
        local bar_width = extents.width + extents.x_bearing*2 + icon_size 
            + horizontal_padding*3
        local bar_height = panel_height + vertical_padding*2
        local bar_y = conky_window.height*media_bar_vertical_alignment 
            - bar_height/2
        draw_sidebar(bar_y, bar_width, bar_height)

        -- draw text
        cairo_set_source_rgba(cr, unpack(colors.foreground))
        cairo_move_to(cr, 
            conky_window.width - gap_x - extents.width - extents.x_bearing*2 
            - horizontal_padding, bar_y + bar_height/2 - extents.y_bearing/2)
        cairo_show_text(cr, text)

        -- draw icon
        cairo_set_source_surface(cr, icons.media, 
            conky_window.width - gap_x - bar_width + horizontal_padding, 
            bar_y + bar_height/2 - icon_size/2)
        cairo_paint(cr)
    end -- if
end -- media_bar

-------------------------------------------------------------------------------
--                                                          get_mpris2_metadata
function get_mpris2_metadata()
    local command = 'qdbus $(qdbus org.mpris.MediaPlayer2.* | head -1) ' ..
        '/org/mpris/MediaPlayer2 ' ..
        'org.freedesktop.DBus.Properties.Get ' ..
        'org.mpris.MediaPlayer2.Player Metadata 2> /dev/null'
    local file = io.popen(command)
    local mpris2_metadata, key, value = {}, nil, nil
    for line in file:lines() do
        key, value = unpack(explode(": ", line, 2))
        mpris2_metadata[key] = value
    end -- for
    file:close()
    return mpris2_metadata
end -- get_mpris2_metadata

-------------------------------------------------------------------------------
--                                                                 draw_sidebar
function draw_sidebar(y, width, height)
    local radius = 7
    cairo_move_to(cr, conky_window.width - gap_x , y)
    cairo_line_to(cr, conky_window.width - gap_x - width + radius, y)
    cairo_arc_negative(cr, 
        conky_window.width - gap_x - width + radius, y + radius, 
        radius, 1.5*M_PI, 1*M_PI)
    cairo_arc_negative(cr, 
        conky_window.width - gap_x - width + radius, y + height - radius, 
        radius, 1*M_PI, 0.5*M_PI)    
    cairo_line_to(cr, conky_window.width - gap_x, y + height)
    cairo_set_source_rgba(cr, unpack(colors.background))
    cairo_fill_preserve(cr)

    -- outline
    cairo_set_source_rgba(cr, unpack(colors.outline))
    cairo_set_line_width(cr, 1)
    cairo_stroke(cr)
end -- draw_sidebar

-------------------------------------------------------------------------------
--                                                                convert_icons
function convert_icons()
    local tmpfile, command = nil, nil
    for key, value in pairs(icons) do
        if string.sub(value, -4) == ".svg" then
            tmpfile = os.tmpname()
            command = "rsvg-convert -w " .. icon_size .. " -h " .. icon_size ..
                " -f png -o " .. tmpfile .. " " .. icons[key]
            os.execute(command)
            icons[key] = cairo_image_surface_create_from_png(tmpfile)
            os.remove(tmpfile)
        elseif string.sub(value, -4) == ".png" then
            icons[key] = cairo_image_surface_create_from_png(value)
        end -- if
    end -- for
end -- convert_icons

-------------------------------------------------------------------------------
--                                                random_geographic_coordinates
--
-- Uniformly distributed random spherical coordinates.
-- http://mathworld.wolfram.com/SpherePointPicking.html
--
function random_geographic_coordinates()
    local lon = 2*M_PI*math.random()
    local lat = math.acos(2*math.random() - 1)
    return math.deg(lat) - 90, math.deg(lon) - 180
end -- random_geographic_coordinates

-------------------------------------------------------------------------------
--                                                                      ellipse
--
-- Adds an ellipse to the current path.
--
function ellipse(cr, x, y, width, height, angle)
    angle = angle or 0
    if width > 0 and height > 0 then
        cairo_save(cr)
        cairo_translate(cr, x, y)
        cairo_rotate(cr, angle)
        cairo_scale(cr, width/2, height/2)
        cairo_arc(cr, 0, 0, 1, 0, 2*M_PI)
        cairo_restore(cr)
    end -- if
end -- ellipse

-------------------------------------------------------------------------------
--                                                                bezier_spline
--                                                       compute_control_points
--                                                                  bezier_test
--
-- Smooth Bézier spline through prescribed points. Computes cubic bezier
-- coefficients to generate a smooth line through specified points.
-- Copied and adapted from 
-- http://www.particleincell.com/blog/2012/bezier-splines/
--
function bezier_spline(cr, x, y)
    local px = compute_control_points(x)
    local py = compute_control_points(y)
    cairo_move_to(cr, x[1], y[1])
    for i = 1, #x - 1 do       
        cairo_curve_to(
            cr, px.p1[i], py.p1[i], px.p2[i], py.p2[i], x[i+1], y[i+1])
    end -- for
end -- bezier_spline

function compute_control_points(knots)
    local p1, p2 = {}, {}
    local n = #knots - 1
    local m = nil

    -- rhs vector
    local a, b, c, r = {}, {}, {}, {}

    -- left most segment
    a[0 + 1] = 0
    b[0 + 1] = 2
    c[0 + 1] = 1
    r[0 + 1] = knots[0 + 1] + 2*knots[1 + 1]

    -- internal segments
    for i = 1, n - 1 do
        a[i + 1] = 1
        b[i + 1] = 4
        c[i + 1] = 1
        r[i + 1] = 4 * knots[i + 1] + 2 * knots[i + 1 + 1]
    end -- for

    -- right segment
    a[n - 1 + 1] = 2
    b[n - 1 + 1] = 7
    c[n - 1 + 1] = 0
    r[n - 1 + 1] = 8*knots[n - 1 + 1] + knots[n + 1]

    -- solves Ax=b with the Thomas algorithm (from Wikipedia)
    for i = 1, n - 1, 1 do
        m = a[i + 1]/b[i - 1 + 1]
        b[i + 1] = b[i + 1] - m * c[i - 1 + 1]
        r[i + 1] = r[i + 1] - m*r[i - 1 + 1]
    end -- for

    p1[n - 1 + 1] = r[n - 1 + 1]/b[n - 1 + 1]
    for i = n - 2, 0, -1 do
        p1[i + 1] = (r[i + 1] - c[i + 1] * p1[i + 1 + 1]) / b[i + 1]
    end -- for

    -- we have p1, now compute p2
    for i = 0, n - 1 - 1, 1  do
        p2[i + 1] = 2*knots[i + 1 + 1] - p1[i + 1 + 1]
    end -- for

    p2[n - 1 + 1] = 0.5*(knots[n + 1] + p1[n - 1 + 1])

    return {["p1"] = p1, ["p2"] = p2}
end -- compute_control_points

function bezier_test()
    local vx, vy = {}, {}
    for i = 1, 40 do
        vx[i] = 50 + math.random(100) + 20*i
        vy[i] = 100 + math.random(100)
    end -- for
    bezier_spline(cr, vx, vy)
    cairo_set_source_rgba(cr, 1, 1, 1, 1)
    cairo_set_line_width(cr, 4)
    cairo_stroke(cr)
end -- bezier_test

-------------------------------------------------------------------------------
--                                                                  table_merge
--
-- Recursively merge tables.
--
function table_merge(a, b, path)
    path = path or {}
    for k, _ in pairs(b) do
        if a[k] then
            if type(a[k]) == "table" and type(b[k]) == "table" then
                table.insert(path, k)
                table_merge(a[k], b[k], path)
            elseif a[k] ~= b[k] then
                table.insert(path, k)
                print("table_merge: conflict at " .. table.concat(path, "."))
            end -- if
        else
            a[k] = b[k]
        end -- if
    end -- for
    return a
end -- table_merge

-------------------------------------------------------------------------------
--                                                                       dedent
--
-- Remove excess indentation from multi-line strings.
--
function dedent(str)
    local lines = setmetatable({}, {
        __index = {excess = math.huge},
        __newindex = function(t, k, v)
            local _, indent = v:find('^%s*')
            if indent < t.excess and indent > 0 
                    and v:sub(indent + 1, indent + 1):find('%C') then 
                rawset(t, "excess", indent) 
            elseif indent == 0 and v:sub(1, 1):find('%C') then 
                rawset(t, "excess", 0) 
            end -- if
            rawset(t, k, v)
        end, -- __newindex
        __tostring = function(t)
            local cum = ""
            for _, v in ipairs(t) do 
                cum = cum .. '\n' .. v:sub(t.excess + 1)
            end -- for
            return cum 
        end, -- __tostring
        })

    local i, pos = 1, 0
    for s, e in function() return string.find(str, '\n', pos, true) end do
        lines[i] = string.sub(str, pos, s - 1)
        pos = e + 1
        i = i + 1
    end -- for
    lines[i] = string.sub(str, pos)

    return tostring(lines)
end -- dedent

-------------------------------------------------------------------------------
--                                                                         trim
--
-- Remove leading and trailing whitespace.
-- http://lua-users.org/wiki/StringTrim
--
function trim(str)
    return str:match'^()%s*$' and '' or str:match'^%s*(.*%S)'
end -- trim

-------------------------------------------------------------------------------
--                                                                      explode
--
-- Break string into an array of substrings.
--
function explode(delimiter, str, limit)
    if (delimiter == '') then return false end
    local i, pos, arr = 0, 0, {}
    for s, e in function() return string.find(str, delimiter, pos, true) end do
        table.insert(arr, string.sub(str, pos, s - 1))
        pos = e + 1
        if limit and limit > 1 then 
            i = i + 1
            if i >= limit - 1 then break end
        end -- if
    end -- for
    table.insert(arr, string.sub(str, pos))
    return arr
end -- explode

-------------------------------------------------------------------------------
--                                                                  conky_color
function conky_color(name)
    local color = colors[name]
    local r = math.floor(color[1]*255)
    local g = math.floor(color[2]*255)
    local b = math.floor(color[3]*255)
    local hex = string.format("#%.2x%.2x%.2x", r, g, b)
    return "${color " .. hex .. "}"
end -- conky_color

-------------------------------------------------------------------------------
--                                                               conky_shutdown
function conky_shutdown()
    locationmap:cleanup()
    subsolarmap:cleanup()
    weather:cleanup()
    calendar:cleanup()
    geolocation.cleanup()
end -- conky_shutdown

-------------------------------------------------------------------------------
--                                                                   conky_main
function conky_main(conkyrc_gap_x)
    -- setup
    if conky_window == nil then return end
    local cs = cairo_xlib_surface_create(
        conky_window.display, conky_window.drawable, conky_window.visual,
        conky_window.width, conky_window.height)
    cr = cairo_create(cs)
    extents = cairo_text_extents_t:create()
    tolua.takeownership(extents)
    font_extents = cairo_font_extents_t:create()
    tolua.takeownership(font_extents)

    gap_x = conkyrc_gap_x or 5
    center_x, center_y = conky_window.width/2 - gap_x, conky_window.height/2
    updates = tonumber(conky_parse('${updates}'))

    if is_first_run and updates > 1 then
        -- scale
        scale = math.min(
            (10/1050)*conky_window.height, (10/1680)*conky_window.width)
        if scale == 0 then scale = nil end
        clock_line_width = clock_line_width or 1.5*scale*clock_scale
        clock_radius = clock_radius or 29*scale*clock_scale
        clock_secondary_radius = clock_secondary_radius or 10*scale*clock_scale
        clock_marker_length = clock_marker_length or 15*scale*clock_scale
        default_font.size = default_font.size or 1.4*scale

        text("Loading...").center(cr, center_x, center_y)

        locationmap = OrthographicMap()
        subsolarmap = OrthographicMap()
        weather = OpenWeatherMap(weather_api_key or SUBSOLAR_OWM_API_KEY)
        calendar = Calendar()
        geolocation = Geolocation()

        ephem = Ephem()
        ephem.compute(geolocation.lat, geolocation.lon)
        calculate_twilight_angles()
        locationmap:create_projection(geolocation.lat, geolocation.lon,
            clock_radius - clock_line_width/2, colors.map)
        if pcall(function()
                subsolarmap:create_projection(
                    ephem.subsolar.lat, ephem.subsolar.lon,
                    clock_secondary_radius, colors.map)
                end) then
        else
        end -- if pcall
        
        convert_icons()
        os.setlocale('C') -- needed for weather forecast floats
        is_first_run = not is_first_run
    elseif updates > 1 then
        ephem = Ephem()
        ephem.compute(geolocation.lat, geolocation.lon, tles)

        -- maps
        locationmap:sync():draw(cr, center_x, center_y)
        subsolarmap:sync():draw(cr, center_x 
            + clock_radius + clock_secondary_radius + clock_marker_length, 
            center_y, 
            ephem.earthrot)

        -- graticule
        locationmap:graticule(cr, colors.graticule)

        -- major circles of latitude
        local axial_tilt = ephem.earth_obliquity or EARTH_OBLIQUITY
        local r_equator = 1
        local r_polar = r_equator*math.sin(math.rad(axial_tilt))
        local r_tropical = r_equator*math.cos(math.rad(axial_tilt))
        subsolarmap:project_circle(cr, r_polar, 90, 0, colors.graticule)
        subsolarmap:project_circle(cr, r_tropical, 90, 0, colors.graticule)
        subsolarmap:project_circle(cr, r_equator, 90, 0, colors.graticule)
        subsolarmap:project_circle(cr, r_tropical, -90, 0, colors.graticule)
        subsolarmap:project_circle(cr, r_polar, -90, 0, colors.graticule)

--        -- random small circles
--        local z, w
--        for i = 1, 100, 1 do
--            z, w = random_geographic_coordinates()
--            locationmap:project_circle(cr, 
--                0.1*math.random(), z, w, colors.accent)
--        end
--
--        -- subsolar
--        local subsolar_color = {unpack(colors.accent)}
--        for i = 1, 9, 1 do
--            subsolar_color[4] = 1 - (i/9)*0.75
--            locationmap:project_circle(cr, math.sin(math.rad(i*10)), 
--                ephem.subsolar.lat, ephem.subsolar.lon, subsolar_color) 
--        end -- for

        if pcall(function()
                -- sublunar
                locationmap:project_circle(cr, MOON_RADIUS,
                    ephem.sublunar.lat, ephem.sublunar.lon, colors.graticule)
                locationmap:project_circle(cr, MOON_RADIUS*0.5,
                    ephem.sublunar.lat, ephem.sublunar.lon, colors.graticule)

                -- iss
                local x, y, cos_c = 
                    locationmap:compute_formulas(
                        math.rad(ephem.tles.iss.lat), 
                        math.rad(ephem.tles.iss.lon))
                if cos_c >= 0 then
                    text("ISS").center(cr, center_x + x, center_y + y)
                end -- if
                end) then
        else
        end -- if pcall

        stars()
        planets()
        draw_clock()
        local magnetic = MagneticField(geolocation.lat, geolocation.lon)
        magnetic:draw_magnetic_declination()
        geolocation.draw()
        calendar:sync():draw()
        weather:sync():draw()
        media_bar()
--        bezier_test()
    end -- if

    -- hourly
    if updates%3600 == 2 then   
        calculate_twilight_angles()
        geolocation.locate(geolocation_timeout)
        weather:request_forecast(geolocation.lat, geolocation.lon)
        calendar:request_marks(unpack(calendar_marks_whitelist))
        get_iss_tle()
    end -- if

    -- minutely
    if updates%60 == 2 then
        geolocation.sync()
        if geolocation.is_changed() then
            locationmap:create_projection(geolocation.lat, geolocation.lon,
                clock_radius - clock_line_width/2, colors.map)
        end -- if
        if pcall(function()
                subsolarmap:create_projection(
                    ephem.subsolar.lat, ephem.subsolar.lon,
                    clock_secondary_radius, colors.map)
                end) then
        else
        end -- if pcall
    end -- if

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
    cr = nil
    collectgarbage()
end -- conky_main


