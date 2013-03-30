# represents a point
class window.Point
  # constructor
  constructor: (@x, @y, @z) ->

  # get the length squared
  len_sq: () -> @x * @x + @y * @y + @z * @z

  # get the length
  len: () -> Math.sqrt(@x * @x + @y * @y + @z * @z)

  # return the sum of this and another point
  plus: (other) ->
    return new Point(@x + other.x, @y + other.y, @z + other.z)

  # return the difference of this and another point
  minus: (other) ->
    return new Point(@x - other.x, @y - other.y, @z - other.z)

  # return the dot product of this and another point
  dot: (other) ->
    return @x * other.x + @y * other.y + @z * other.z

  # return the cross product of this and another point
  cross: (other) ->
    return new Point(@y * other.z - @z * other.y, @z * other.x - @x * other.z, @x * other.y - @y * other.x)

  # return a times version of the vector
  times: (s) ->
    return new Point(@x * s, @y * s, @z * s)

  # normalize the vector
  normalized: () ->
    len_inv = 1 / @len()
    return new Point(@x * len_inv, @y * len_inv, @z * len_inv)

# represents a ray
class window.Ray
  # constructor
  constructor: (@origin, @dir) ->

# represents a color
class window.Color
  # constructor (component values must lie in range [0, 1])
  constructor: (@r, @g, @b) ->

  # returns a CSS-compatible string
  to_str: () -> "rgb(" + String(Math.round(@r * 255)) + ", " + String(Math.round(@g * 255)) + ", " + String(Math.round(@b * 255)) + ")";

  # returns a CSS-compatible string
  to_str_with_alpha: (alpha) -> "rgba(" + String(Math.round(@r * 255)) + ", " +
                                          String(Math.round(@g * 255)) + ", " +
                                          String(Math.round(@b * 255)) + ", " +
                                          String(           alpha    ) + ")";

  # return the sum of this and another color
  plus: (other) ->
    return new Color(Math.min(@r + other.r, 1), Math.min(@g + other.g, 1), Math.min(@b + other.b, 1))

  # return a times version of the color
  times: (s) ->
    return new Color(Math.max(Math.min(@r * s, 1), 0), Math.max(Math.min(@g *s, 1), 0), Math.max(Math.min(@b * s, 1), 0))

# represents the surface properties of an object
class window.Material
  # constructor
  constructor: (@color, @texture_url, @scale) ->
    @texture_loaded = false
    if @texture_url
      @canvas = document.createElement("canvas")
      @context = @canvas.getContext("2d")
      @image_data = null
      self = this
      $("<img />").attr("src", @texture_url).load(() ->
        if this.complete and typeof this.naturalWidth != "undefined" and this.naturalWidth != 0
          self.canvas.width = this.naturalWidth
          self.canvas.height = this.naturalHeight
          self.context.clearRect(0, 0, this.naturalWidth, this.naturalHeight)
          self.context.drawImage(this, 0, 0)
          self.image_data = self.context.getImageData(0, 0, this.naturalWidth, this.naturalHeight)
          self.texture_loaded = true
      )

  # determine the surface color
  shade: (tx, ty) ->
    if @texture_loaded
      tx *= @scale
      ty *= @scale
      if tx < 0
        tx = 1 + (tx % 1)
      else
        tx %= 1
      if ty < 0
        ty = 1 + (ty % 1)
      else
        ty %= 1
      tx = Math.floor(tx * @canvas.width)
      ty = Math.floor(ty * @canvas.height)
      offset = (ty * @canvas.width + tx) * 4
      return new Color(@image_data.data[offset] / 255, @image_data.data[offset + 1] / 255, @image_data.data[offset + 2] / 255)
    return @color

# represents the result of an intersection
class window.Hit
  # constructor
  constructor: (@t, @tx, @ty, @material) ->

# a list of objects in the scene (see objects.js.coffee)
window.scene_graph = []

# device information
window.device = {
  # the canvas context
  context: null,

  # the x position of the render region in the canvas
  x: 0,

  # the y position of the render region in the canvas
  y: 0,

  # the width of the render region in the canvas
  width: 100,

  # the height of the render region in the canvas
  height: 100,

  # the render quality (> 0)
  quality: 10
}

# the camera
window.camera = {
  # the location of the camera in world-space
  pos: new Point(0, 0, 0),

  # a unit vector describing the forward direction of the camera
  aim: new Point(1, 0, 0),

  # a unit vector describing the left direction of the camera
  left: new Point(0, 1, 0),

  # a unit vector describing the up direction of the camera
  up: new Point(0, 0, 1),

  # horizontal field of view in radians
  fov: 1.57,

  # background color
  background_color: new Color(1, 1, 1),

  # fog settings
  fog_enabled: true,
  fog_distance: 50,
  fog_color: new Color(1, 1, 1),

  # aspect ratio (width/height)
  aspect: 1
}

# sample the color at a point in screen space
sample = (x, y) ->
  # compute which ray corresponds to this point
  tmp = 2 * Math.tan(window.camera.fov * 0.5)
  left = -(x / window.device.width - 0.5) * tmp
  up = -(y / window.device.height - 0.5) * tmp / window.camera.aspect
  dir = window.camera.aim.plus(window.camera.left.times(left)).plus(window.camera.up.times(up)).normalized()
  ray = new Ray(window.camera.pos, dir)

  # intersect the ray with all the objects in the scene graph
  hit = null
  for item in window.scene_graph
    test_hit = item.intersect(ray)
    if test_hit != null and (hit == null or test_hit.t < hit.t)
      hit = test_hit

  # check if there was a hit
  if hit == null
    return window.camera.background_color
  else
    # perform shading
    col = hit.material.shade(hit.tx, hit.ty)

    # apply fog
    if window.camera.fog_enabled
      fog_factor = Math.min(hit.t / window.camera.fog_distance, 1)
      col = col.times(1 - fog_factor).plus(window.camera.fog_color.times(fog_factor))

    # return the color
    return col

# render a piece of the scene
render_block = (x, y, width, height, samples, index) ->
  # determine how many samples we need
  num_samples = Math.max(Math.min(Math.max(Math.round(width * height / 10000 * window.device.quality), 3), 20), samples.length)

  # collect samples
  if num_samples > samples.length
    new_samples = num_samples - samples.length
    sample_area = width * height / new_samples
    columns = Math.round(width / Math.sqrt(sample_area))
    rows = Math.ceil(new_samples / columns)
    cell_width = width / columns
    cell_height = height / rows

    for i in [0...new_samples]
      if window.device.random_sampling == true
        the_x = x + Math.random() * width
        the_y = y + Math.random() * height
      else
        the_x = x + (i % columns + 0.5) * cell_width
        the_y = y + (Math.floor(i / columns) + 0.5) * cell_height

      the_sample = sample(the_x, the_y).times(1)
      the_sample.x = the_x
      the_sample.y = the_y
      the_sample.index = index
      samples.push(the_sample)

  # average the samples
  average = new Color(0, 0, 0)
  for s in samples
    average.r += s.r
    average.g += s.g
    average.b += s.b
  average.r /= num_samples
  average.g /= num_samples
  average.b /= num_samples

  # compute the deviation
  deviation = 0
  for s in samples
    deviation += Math.sqrt(Math.pow(s.r - average.r, 2) + Math.pow(s.g - average.g, 2) + Math.pow(s.b - average.b, 2))
  deviation /= num_samples

  # if the deviation is small, just render the average color
  if (deviation < 1 / window.device.quality) or width * height <= 64
    window.device.context.fillStyle = average.to_str_with_alpha(0.1)
    window.device.context.fillRect(x - 0.5, y - 0.5, width + 1, height + 1)

    #window.device.context.fillStyle = "#f00"
    #for my_sample in samples
    #  window.device.context.fillRect(my_sample.x, my_sample.y, 2, 2)
  else
    pivot = Math.random()
    if width > height
      threshold = x + width * pivot
      render_block(x,                 y,                width *    pivot , height, samples.filter((e) -> e.x <  threshold), index + 1)
      render_block(x + width * pivot, y,                width * (1-pivot), height, samples.filter((e) -> e.x >= threshold), index + 1)
    else
      threshold = y + height * pivot
      render_block(x,               y,                  width, height *    pivot , samples.filter((e) -> e.y <  threshold), index + 1)
      render_block(x,               y + height * pivot, width, height * (1-pivot), samples.filter((e) -> e.y >= threshold), index + 1)

# render the scene
window.render = () ->
  # render the scene as a huge block
  render_block(device.x, device.y, device.width, device.height, [], 0)

