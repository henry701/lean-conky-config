local _dirname_ = debug.getinfo(1, 'S').source:sub(2):match('(.*[/\\])')
package.path = _dirname_ .. '?.lua;' .. package.path
utils = require 'utils'

-- load conky config tables including font definitions
if conky == nil then conky = {} end
dofile(conky_config)

-- remove unavailable fonts
local function _check_fonts()
    for k, v in pairs(conky.fonts) do
        local font = conky.fonts[k]
        local p = font:find(':')
        if p then font = font:sub(1, p-1) end
        font = utils.trim(font)
        if #font > 0 then
            local s = utils.sys_call('fc-list -f "%{family[0]}" "'..font..'"', true)
            if #s < 1 then conky.fonts[k] = nil end
        elseif not p then
            conky.fonts[k] = nil
        end
    end
end
_check_fonts()

-- render `text` in specified font if it is available on system, otherwise
-- render `alt_text` with current font. if no `alt_text` is provided, it is
-- assumed to be the same as `text`.
function conky_font(font_key, text, alt_text)
    text = utils.unbrace(text)
    if alt_text == nil then
        alt_text = text
    else
        alt_text = utils.unbrace(alt_text)
    end
    font = conky.fonts[font_key]
    if font then
        return conky_parse(string.format('${font %s}%s${font}', font, text))
    else
        return conky_parse(alt_text)
    end
end

conky_percent_ratio = utils.percent_ratio

-- unified shortcut to all top_x variables, with optional padding
function _top_val(ord, dev, type, max_len, align)
    if dev == 'io' or dev == 'mem' or dev == 'time' then
        dev = '_' .. dev
    else
        dev = ''
    end
    local rendered = conky_parse(
        string.format('${top%s %s %d}', dev, type, ord)
    )
    return utils.padding(utils.trim(rendered), max_len, align, ' ')
        -- NOTE: the padding character here is FIGURE SPACE (U+2007)
        -- see https://en.wikipedia.org/wiki/Whitespace_character
end

-- render top (cpu) line
function conky_top_cpu_line(ord)
    local _H = '${color2}${font :bold:size=8}PROCESS ${goto 156}PID ${goto 194}MEM% ${alignr}CPU%${font}${color}'
    if ord == 'header' then return conky_parse(_H) end

    local function _t(type, padding_len)
        return _top_val(ord, 'cpu', type, padding_len, 'right')
    end
    return conky_parse(
        string.format('%s ${goto 156}%s ${goto 196}%s ${alignr}%s',
                      _t('name'), _t('pid'),
                      _t('mem', 6), _t('cpu'))
    )
end

-- render top_mem line
function conky_top_mem_line(ord)
    local _H = '${color2}${font :bold:size=8}PROCESS ${goto 156}PID ${goto 198}CPU%${alignr}MEM%${font}${color}'
    if ord == 'header' then return conky_parse(_H) end

    local function _t(type, padding_len)
        return _top_val(ord, 'mem', type, padding_len, 'right')
    end
    return conky_parse(
        string.format('%s ${goto 156}%s ${goto 196}%s ${alignr}%s',
                      _t('name'), _t('pid'),
                      _t('cpu', 6), _t('mem'))
    )
end

-- render top_io line
function conky_top_io_line(ord)
    local _H = '${color2}${font :bold:size=8}PROCESS ${goto 156}PID ${alignr}READ/WRITE${font}${color}'
    if ord == 'header' then return conky_parse(_H) end

    local function _t(type)
        return _top_val(ord, 'io', type)
    end
    return conky_parse(
        string.format('%s ${goto 156}%s ${alignr}%s / %s',
                      _t('name'), _t('pid'),
                      _t('io_read'), _t('io_write'))
    )
end

local function _interval_call(interv, ...)
    return conky_parse(utils.interval_call(tonumber(interv or 0), unpack(arg)))
end

-- dynamically show active ifaces
-- see https://matthiaslee.com/dynamically-changing-conky-network-interface/
local TPL_IFACE =
[[${if_existing /sys/class/net/<IFACE>/operstate up}]] ..
[[${voffset 2}${font :size=7}▼${font}  ${downspeed <IFACE>} ${alignc -22}${font :bold:size=8}<IFACE>${font}]] ..
[[${alignr}${upspeed <IFACE>} ${voffset -2}${font :size=7}▲${font}
${color3}${downspeedgraph <IFACE> 32,130} ${alignr}${upspeedgraph <IFACE> 32,130 }${color}]] ..
[[${endif}]]

local function _conky_ifaces()
    local rendered = {}
    for i, iface in ipairs(utils.enum_ifaces()) do
        rendered[i] = TPL_IFACE:gsub('<IFACE>', iface)
    end
    if #rendered > 0 then
        return table.concat(rendered, '\n')
    else
        return "${font}(no active network interface found)"
    end
end

function conky_ifaces(interv)
    return _interval_call(interv, _conky_ifaces)
end

-- dynamically show mounted disks
local TPL_DISK =
[[${font :bold:size=8}%s${font} ${alignc -8}%s / %s [%s] ${alignr}%s%%
${color3}${lua_bar 4 percent_ratio %s %s}${color}]]

local function _conky_disks()
    local rendered = {}
    for i, disk in ipairs(utils.enum_disks()) do
        -- human friendly size strings
        local size_h = utils.filesize(disk.size)
        local used_h = utils.filesize(disk.used)

        -- get succinct name for the mount
        local name = disk.mnt
        local media = name:match('^/media/'..utils.env.USER..'/(.+)$')
        if media then
            name = media
        elseif name == utils.env.HOME then
            name = '${font :bold:size=11}⌂'
        end
        rendered[i] = string.format(TPL_DISK, name, used_h, size_h, disk.type,
                                    utils.percent_ratio(disk.used, disk.size),
                                    disk.used, disk.size)
    end
    if #rendered > 0 then
        return table.concat(rendered, '\n')
    else
        return "${font}(no mounted disk found)"
    end
end

function conky_disks(interv)
    return _interval_call(interv, _conky_disks)
end
