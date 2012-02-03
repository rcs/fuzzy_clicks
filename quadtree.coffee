# Basic gameplan here for finding the closest links is to generate an overlay
# to sit on top, indexing all our clicking elements in a quadtree.
# When we click, find the quadtree nodes overlapping an ever-expanding circle
# until we find something.

# Helper for creating synthetic click events
fireEvent =  (obj, evt) ->
  if document.createEvent
      evtObj = document.createEvent('MouseEvents')
      evtObj.initEvent(evt, true, false)
      obj.dispatchEvent(evtObj)
  else if (document.createEventObject)
      # For IE -- untested
      evtObj = document.createEventObject()
      obj.fireEvent('on'+evt, evtObj)

# Helper function for determining if val is between min and max
inRange = (val, min, max) ->
  (val >= min) and (val <= max)


# Helper function for computing distance from point to rectangle
distance_to_rect = (point, rect) ->
  distance = {}

  # Check if contained in the horizontal
  if point.x >= rect.offset().left and point.x <= (rect.offset().left + rect.width())
    distance.x = 0
  else
    # Else the distance to the line projection
    distance.x = Math.min(
                  Math.abs(point.x - rect.offset().left),
                  Math.abs(point.x - (rect.offset().left + rect.width()))
                )

  # Check if contained in the vertical
  if point.y >= rect.offset().top and point.y <= (rect.offset().top + rect.height())
    distance.y = 0
  else
    # Else the distance to the line projection
    distance.y = Math.min(
                  Math.abs(point.y - rect.offset().top),
                  Math.abs(point.y - (rect.offset().top + rect.height()))
                )

  return Math.sqrt Math.pow(distance.x,2) + Math.pow(distance.y,2)


# Helper class emulating jquery's position functions
class Rectangle
  constructor: (options) ->
    @metrics =
      left: options.left
      top: options.top
      width: options.width
      height: options.height

  offset: =>
    {
      left: @metrics.left
      top: @metrics.top
    }

  width: => @metrics.width
  height: => @metrics.height


# QuadTree implementation, holding rectangles
class QuadTree

  constructor: (bounds, maxElements = 3) ->
    @bounds = bounds
    @maxElements = maxElements
    @rectangles = []
    @subNodes = {}
    return this

  # Convenience function for creating and wrapping all <a>s
  @from_elem_with_as: ($elem) ->
    q = new QuadTree($elem)
    q.insert($elem.find('a'))
    q

  # Insert into the quadtree, or sub nodes if they exist and fully contain the inserted object
  insert: (rectangle) =>
    if rectangle.length and rectangle.length > 1
      for rect in rectangle
        # If it's a bare DOM element, wrap in jquery to give position accessor access
        if _.isElement(rect)
          @insert $(rect)
        else
          @insert(rect)
      return

    # Check if inserting this would make us go over max elements
    if (@rectangles.length == @maxElements) and (_.size(@subNodes) == 0)
      @subdivide()

    # Check first any subnodes, than ourself for full containment of the rectangle.
    # Insert into the first match
    contains = (quad for quad in _.values(@subNodes) when quad.fullyContains rectangle)[0]
    if contains
      contains.insert rectangle
    else
      @rectangles.push rectangle


    return this

  # Is rectangle fully contained in our bounding box?
  # TODO handle width/height == 0
  fullyContains: (rectangle) =>
    # Shortening these variables makes the code clearer in the comparisons
    r = @short_positions(rectangle)
    b = @short_positions(@bounds)

    # Left side contained
    r.l >= b.l and
      # Right side contained
      ((r.l + r.w) <= (b.l + b.w)) and
      # Top side contained
      (r.t >= b.t) and
      # Bottom side contained
      ((r.t + r.h) <= (b.t + b.h))

  # Does rectangle overlap our bounding box?
  overlaps: (rectangle) =>

    # X dimension overlaps
    x = inRange(rectangle.offset().left, @bounds.offset().left, @bounds.offset().left + @bounds.width()) or
      inRange(@bounds.offset().left, rectangle.offset().left, rectangle.offset().left + rectangle.width())

    # Y dimension overlaps
    y = inRange(rectangle.offset().top, @bounds.offset().top, @bounds.offset().top + @bounds.height()) or
      inRange(@bounds.offset().top, rectangle.offset().top, rectangle.offset().top + rectangle.height())

    # rect overlap if both true
    x and y


  # Find closest to the point, starting from a given radius, aborting the covering radius of the $body
  closest_to_point: (point, $body = $('body'), radius = 10) =>

    # Find matching points within our search radius
    found = @rectangles_within(point,radius)

    # If we found things, grab the closest
    if found.length > 0
      (_.sortBy found, (rect) ->
        distance_to_rect(point,rect)
      )[0]
    # Finish if we're over radius
    else if radius > $body.width()*Math.sqrt(2) and radius > $body.height()*Math.sqrt(2)
      undefined
    # Try again with a larger radius if we didn't find anything
    else
      @closest_to_point point, $body, radius*2




  # Find matching rectangles in this node and subnodes in a circle of radius centered on point
  rectangles_within: (point, radius) =>
    exscribed =  new Rectangle {
          top: point.y - radius
          left: point.x - radius
          width: radius*2
          height: radius*2
    }

    # Only care about found inside the circle defined by the radius, not the entire rectangle
    found = (rect for rect in @rectangles when distance_to_rect(point,rect) <= radius) || []

    # Find matching points in subnodes
    found = found.concat _.flatten((for sub in _.values(@subNodes) when sub.overlaps(exscribed)
                  sub.rectangles_within(point, radius)
                  ),true)

    found

  # Draw a bunch of spans corresponding to the bounding boxes of quadtree and subnodes
  paint: ($elem = $('body')) =>
    @painted = $('<span>')
      .addClass('quadtree-paint')
      .offset
        top: @bounds.offset().top
        left: @bounds.offset().left
      .width(@bounds.width())
      .height(@bounds.height())
      .css('position', 'absolute')
      .css('outline', 'black solid 2px')
      .appendTo($elem)

    quad.paint($elem) for quad in _.values(@subNodes)

  erase: ->
    @painted.remove()
    quad.erase() for quad in _.values(@subNodes)



  # Remove all painted nodes
  # Done as a class method not keeping track of painted nodes so we can clear
  # it easily even if we've lost the quadtree reference
  @erase: ->
    $('.quadtree-paint').remove()

  # Helper function to cut line length when accessing these properties repeatedly
  short_positions: (rectangle) ->
    {
      l: rectangle.offset().left
      t: rectangle.offset().top
      w: rectangle.width()
      h: rectangle.height()
    }


  # Give our quadtree subnodes corresponding to dividing the bounding box in four
  # TODO : handle non-evenly divisible width/height
  subdivide: =>
    # -----
    # | | |
    # -----
    # | | |
    # -----
    left = @bounds.offset().left
    top = @bounds.offset().top
    width = @bounds.width()
    height = @bounds.height()


    @subNodes = {
      # -----
      # |x| |
      # -----
      # | | |
      # -----
      nw: new QuadTree(
        new Rectangle {
          top: top
          left: left
          width: width/2
          height: height/2
        },
        @maxElements
      )
      # -----
      # | |x|
      # -----
      # | | |
      # -----
      ne: new QuadTree(
        new Rectangle {
          top: top
          left: left + width/2
          width: width/2
          height: height/2
        },
        @maxElements
      )
      # -----
      # | | |
      # -----
      # |x| |
      # -----
      sw: new QuadTree(
        new Rectangle {
          top: top + height/2
          left: left
          width: width/2
          height: height/2
        },
        @maxElements
      )
      # -----
      # | | |
      # -----
      # | |x|
      # -----
      se: new QuadTree(
        new Rectangle {
          top: top + height/2
          left: left + width/2
          width: width/2
          height: height/2
        },
        @maxElements
      )
    }

    holding = @rectangles
    @rectangles = []
    @insert holding

# Enable fuzzy clicking on an element
fuzzy_clicking = ($elem) ->
  q = QuadTree.from_elem_with_as($elem)

  # Define an overlay that sits on top of the element
  overlay = $('<span>')
    .addClass('fuzzy-overlay')
    .offset
      top: q.bounds.offset().top
      left: q.bounds.offset().left
    .width(q.bounds.width())
    .height(q.bounds.height())
    .css('position', 'absolute')
    .css('z-index', '9001') # Over 9000

  # Insert the overlay next to the element
  $elem.after overlay

  # Bind clicks on the element to find and act on the closest
  overlay.on 'click', (e) ->
    closest = q.closest_to_point { x: e.pageX, y: e.pageY }, $elem
    if closest
      # Fire a synthetic click event on the closest
      fireEvent(closest.get(0),'click')
      # We're done with this event
      e.stopPropagation()
      e.preventDefault()

base = (window || this)
base.fuzzy_clicking = fuzzy_clicking
