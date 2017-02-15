download = require('download-file')
async = require('async')
request = require('request')
geolib = require('geolib')
fs = require('fs')
fse = require('fs-extra')
filesize = require('filesize')

if process.argv.length < 3
  console.error "give url"
  process.exit -1

MAX_ZOOM = 19
MAX_TILES = 500

# remove old tiles
fse.emptydirSync('tiles')

coord_string2arr = (coord) -> coord.split(', ')

# load bound details
request process.argv[2], (error, response, body) ->
  bound = JSON.parse body

  # collect all coordinates in bound
  bound_coordinates = []

  # start point
  if 'start-point' of bound.settings and bound.settings['start-point']
    bound_coordinates.push coord_string2arr(bound.settings['start-point'])
  
  # look at elements
  for element in bound.content
    if 'location' of element and element.location
      bound_coordinates.push coord_string2arr(element.location).reverse()

  if bound_coordinates.length == 0
    console.error "count does not contain any coordinates"
    process.exit -1

  bound_center = geolib.getCenter(bound_coordinates)
  bound_box = geolib.getBounds(bound_coordinates)

  console.log "bound bounding_box"
  console.log bound_box

  # set bounding box
  NORTH = bound_box.maxLat
  SOUTH = bound_box.minLat
  EAST = bound_box.maxLng
  WEST = bound_box.minLng

  # https://wiki.openstreetmap.org/wiki/Slippy_map_tilenames
  # osm helper methods
  lon2tile = (lon, zoom) ->
    Math.floor (lon + 180) / 360 * 2 ** zoom

  lat2tile = (lat, zoom) ->
    Math.floor (1 - (Math.log(Math.tan(lat * Math.PI / 180) + 
      1 / Math.cos(lat * Math.PI / 180)) / Math.PI)) / 2 * 2 ** zoom

  
  tiles = []
  # for stats
  zoom_tiles = {}
  zoom_levels = [1..MAX_ZOOM]
  
  # populate tiles
  for zoom in [1..MAX_ZOOM]
    top_tile = lat2tile(NORTH, zoom)
    left_tile = lon2tile(WEST, zoom)
    bottom_tile = lat2tile(SOUTH, zoom)
    right_tile = lon2tile(EAST, zoom)

    width = Math.abs(left_tile - right_tile) + 1
    height = Math.abs(top_tile - bottom_tile) + 1

    zoom_tiles[zoom] = { files: [] }
    total_tiles = width * height

    if total_tiles > MAX_TILES
      console.log "ZoomLevel #{zoom} would have #{total_tiles}, skipping this onwards."
      zoom_levels = [1..zoom-1]
      MAX_ZOOM = zoom - 1
      break

    for x in [left_tile..right_tile]
      for y in [top_tile..bottom_tile]
        tiles.push 
          name: "#{zoom}-#{x}-#{y}.png"
          url: "http://b.tile.openstreetmap.de/tiles/osmde/#{zoom}/#{x}/#{y}.png"

        zoom_tiles[zoom].files.push "#{zoom}-#{x}-#{y}.png"

  download_tile = (tile, next) ->
    process.stdout.write('.')
    download tile.url, { directory: 'tiles', filename: tile.name}, next

  # download 50 tiles at once
  async.eachLimit tiles, 50, download_tile, (err) ->
    console.log ".done"

    add_size_for_file = (memo, file, next) ->
      fs.stat "tiles/#{file}", (err, stats) ->
        next null, stats.size + memo

    size_sum = 0

    size_for_zoom_level = (zoom_level, next) ->
      async.reduce zoom_tiles[zoom_level].files, 0, add_size_for_file, (err, result) ->
        size_sum += result
        console.log "ZoomLevel: #{zoom_level} TILES: #{zoom_tiles[zoom_level].files.length} SIZE: #{filesize(result)} SIZESUM: #{filesize(size_sum)}"
        next()

    
    async.eachSeries zoom_levels, size_for_zoom_level, () ->
      console.log "done"
      fs.writeFile "setCenter.js", "L.tileLayer('tiles/{z}-{x}-{y}.png', { maxZoom: #{MAX_ZOOM} }).addTo(map); map.setView([#{bound_center.latitude}, #{bound_center.longitude}], #{MAX_ZOOM})", () ->
        process.exit 0
