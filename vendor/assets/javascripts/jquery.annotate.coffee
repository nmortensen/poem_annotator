(($) ->

  # default html template for annotation dialog
  default_dialog = '<div class="errors"></div><form><label for="content">Content</label><input type="text" class="" value="" name="content" id="content"><input type="submit"> <button type="button" class="annotate-cancel">Cancel</button></form>'

  # convert form data to JSON
  serializeObject = (el, extras = {}) ->

    json = {}
    push_counters = {}
    patterns =
      validate  : /^[a-zA-Z][a-zA-Z0-9_]*(?:\[(?:\d*|[a-zA-Z0-9_]+)\])*$/,
      key       : /[a-zA-Z0-9_]+|(?=\[\])/g,
      push      : /^$/,
      fixed     : /^\d+$/,
      named     : /^[a-zA-Z0-9_]+$/

    @build = (base, key, value) ->
      base[key] = value
      base

    @push_counter = (key) ->
      push_counters[key] = 0 if push_counters[key] is undefined
      push_counters[key]++

    arrayData = $(el).serializeArray()
    $.each arrayData, (i, elem) =>
      return unless patterns.validate.test(elem.name)

      keys = elem.name.match patterns.key
      merge = elem.value
      reverse_key = elem.name

      while (k = keys.pop()) isnt undefined

        if patterns.push.test k 
          re = new RegExp("\\[#{k}\\]$")
          reverse_key = reverse_key.replace re, ''
          merge = @build [], @push_counter(reverse_key), merge

        else if patterns.fixed.test k 
          merge = @build [], k, merge

        else if patterns.named.test k
          merge = @build {}, k, merge

      json = $.extend true, json, merge, extras

    return {annotation: json}

  getCurrentTime = ->
    currentdate = new Date()
    currentdate.toString()

  # check if node is within annotatable area
  isDescendant = (parent, child) ->
    if child?
      node = child.parentNode
      while node?
        return true  if node is parent
        node = node.parentNode
    false

  inlineOffset = (mark) ->
    el = $("<i/>").css("display", "inline").insertBefore(mark)
    pos = el.offset()
    el.remove()
    pos

  generateAnnotateId = ->
    chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXTZabcdefghiklmnopqrstuvwxyz"
    string_length = 16
    randomstring = ""
    i = 0

    while i < string_length
      rnum = Math.floor(Math.random() * chars.length)
      randomstring += chars.substring(rnum, rnum + 1)
      i++
    randomstring

  # get the annotation id from an element, or its parent(s)
  getAnnotateId = ($element) ->
    $element.data('annotate-id') || $element.parent('*[data-annotate-id!=undefined]').data('annotate-id')

  titleize = (str) ->
    fixed_str = str.replace(/([a-z])([A-Z])/g, '$1 $2')
    words = fixed_str.split(/[\s_]+/)
    array = []
    i = 0

    while i < words.length
      array.push words[i].charAt(0).toUpperCase() + words[i].toLowerCase().slice(1)
      ++i
    array.join " "

  sendArticle = ($annotatable_element) ->
    settings = $annotatable_element.data()

    if typeof settings.article.update is "function"
      $annotatable_element.children('mark').addClass('hidden')
      settings.article.update.apply($annotatable_element[0], [$annotatable_element.html()])
      $annotatable_element.children('mark').removeClass('hidden')

  toCamel = (obj = {}) ->
    new_obj = {}
    $.each obj, (key, value) ->
      fixed_key = $.camelCase(key)
      new_obj[fixed_key] = value


  
  methods =

    init: (options) ->
      $annotatable_element = $(this)
      settings = $annotatable_element.data()

      # initialize rangy and a marker if not present
      unless settings.tempMarker?
        rangy.init()
        settings.tempMarker = rangy.createCssClassApplier("temp",
          normalize: true
          elementTagName: 'tempmark'
        )

      # default plugin settings
      $(this).data settings = $.extend(true,
        ignore_warnings: false                                          # Boolean, determines whether warnings will be displayed in the console log        
        _annotatable_id: generateAnnotateId()
        dialog:
          class: ''
          tag_name: 'div'
          offset_amount: 10                                             # Integer, amount of pixels between text and popup, or pixels between document width
          position: 'top'                                               # 'top' | 'bottom' | 'left' | 'right', float popup left/right, or hover above/below selected text
          trigger_type: 'select'                                        # 'select' | 'click' | null, which type of event triggers the build_annotation callback
          template: default_dialog                                      # String, HTML template for annotation dialog, should contain a form
          beforeCreate: null                                            # Function(), called before dialog is rendered
          create: methods['_createDialog']                              # Function(), renders dialog into DOM, overrides default functionality. Element should be created with a form inside and should contain a data-annotatable-id retrievable from the annotatable element: 
          afterCreate: null                                             # Function($dialog), called after dialog is rendered
          beforeCancel: null
          afterCancel: null
          outsideSelection: methods['_outsideSelection']                # Function(), called when .annotate('build') is called, but it is outside of the annotatable area.
        annotation:
          class: ''
          offset_amount: 10                                             # Integer, amount of pixels between text and popup, or pixels between document width
          position: 'top'                                               # 'top' | 'bottom' | 'left' | 'right', float popup left/right, or hover above/below selected text
          tag_name: 'div'                                               # String, valid tagName for annotation
          template: null                                                # String, HTML template for annotation to be inserted into the DOM
          container: $('body')[0]                                       # Element, where to insert rendered annotations if no callback is specified.        
          save: methods['_createAnnotation']                            # Function(annotation_data), called after annotation dialog form is submitted
          beforeRender: null                                            # Function(annotation_data), called before annotation is rendered
          render: methods['_renderAnnotation']                          # Function(annotation_data), render annotation template, or error message, overrides default functionality. Called after save. Must return true if successful
          afterRender: null                                             # Function(annotation_data), called after annotation is rendered
          delete: null                                                  # Function([annotate_id1, annotate_id2, ...]), called after annotation(s) are removed
          trigger_type: 'hover'                                         # 'select' | 'click' | null, specifies which type of event triggers the onTrigger and offTrigger callbacks
          onTrigger: methods['_defaultOnTrigger']                       # Function($marks, $annotation), called whenever the mouse enters the top-level mark (and optionally the matching annotation)
          offTrigger: methods['_defaultOffTrigger']                     # Function($marks, $annotation), called whenever the mouse leaves the top-level mark (and optionally the matching annotation)
          allow_remove: true                                            # Boolean, determines whether the user can remove annotations and the associated marks from the DOM
          existing_data: {}                                             # [{annotation1}, {annotation2}], Array of annotation data in JSON format. Keys should be "camelCased"
          include_time: false                                           # Boolean, determines whether Date.toString() will be included as part of the annotation JSON object
          render_from_marks: true                                       # Boolean, determines whether annotations will be rendered on initilization from existing marks in article
        article:
          update: null                                                  # Function(article_html), called whenever a permanent mark is added or removed to the article
        mark:
          trigger_type: 'hover'                                         # 'select' | 'click' | null, specifies which type of event triggers the onTrigger and offTrigger callbacks
          onTrigger: methods['_defaultOnTrigger']                       # Function($marks, $annotation), called the user enters the top-level mark, depending on the trigger 
          offTrigger: methods['_defaultOffTrigger']                     # Function($marks, $annotation), called the user enters the top-level mark, depending on the trigger 
      , options)
    
      # render existing annotations
      $marks = $('mark.annotated', this)
      rendered = []

      $.each settings.annotation.existing_data, (i, data) ->
        if (($.inArray data.annotateId, rendered) == -1) and (typeof $annotatable_element.data('annotation').render is "function")
          $annotatable_element.data().annotation.render.apply($annotatable_element, [{annotation: this, status: 'success'}])
          $("#{settings.annotation.tag_name}[data-annotate-id=#{data.annotateId}]").attr('data-annotatable-id', settings._annotatable_id)
          rendered.push data.annotateId
      
      if settings.annotation.render_from_marks
        $marks.each ->
          if (($.inArray $(this).data('annotateId'), rendered) == -1) and (typeof $annotatable_element.data('annotation').render is "function")
            settings.annotation.beforeRender.apply($annotatable_element, [{annotation: $(this).data(), status: 'success'}]) if typeof settings.annotation.beforeRender is "function"
            settings.annotation.render.apply($annotatable_element, [{annotation: $(this).data(), status: 'success'}])
            $annotation = $annotatable_element.annotate 'associated', $(this)
            settings.annotation.afterRender.apply($annotatable_element, [$annotation]) if typeof settings.annotation.afterRender is "function"
            rendered.push $(this).data('annotateId')

      # bind events for existing annotations and actions conforming to naming conventions
      $(this).data('build_trigger', 'select') if settings.dialog.trigger == 'click' && $('.annotate-build').length == 0
      $('mark.annotated', this).removeClass('hidden')
      $(this).annotate('_bindEvents')

      # display warnings unless explicitly ignored
      unless settings.ignore_warnings
        console.warn "It is highly recommended that you set a callback for updating the article" if settings.article.update is methods['_updateArticle']

    # default callback for rendering annotation dialog
    _createDialog: ->
      $annotatable_element = $(this)
      settings = $annotatable_element.data()

      $('body').append("<#{settings.dialog.tag_name} class='annotate-dialog#{' ' + settings.dialog.class}' data-annotatable-id='#{settings._annotatable_id}'>#{settings.dialog.template}</#{settings.dialog.tag_name}>")
      $dialog = $(".annotate-dialog[data-annotatable-id=#{settings._annotatable_id}]")
      $annotatable_element.annotate 'position', $dialog

    # default callback for creating annotations in database
    _createAnnotation: (data) -> $.extend data, {status: 'success'}

    # default callback for rendering annotations
    _renderAnnotation: (data) ->
      $annotatable_element = $(this)
      settings = $(this).data()
      annotate_id = data.annotation.annotate_id || data.annotation.annotateId

      if $.inArray(data.status, ['success', '200', 200]) > -1
        $mark = $("mark[data-annotate-id=#{annotate_id}]:first", this)

        if settings.annotation.template?
          annotation_innerHtml = settings.annotation.template
        else
          data_html = ''

          annotation_attr = if $mark[0]? then $mark.data() else data.annotation

          if annotation_attr?
            $.each annotation_attr, (key, value) -> data_html += "<dt class='#{key}'>#{titleize(key)}</dt><dd class='annotate-fill-#{key}'></dd>"
            annotation_innerHtml = "<dl>#{data_html}</dl> <button type='button' class='annotate-remove'>Remove</button>"

        annotation_html = "<#{settings.annotation.tag_name} class='annotate-annotation#{' ' + settings.annotation.class}' data-annotate-id='#{annotate_id}' data-annotatable-id='#{settings._annotatable_id}'>#{annotation_innerHtml}</#{settings.annotation.tag_name}>"
        
        if $annotatable_element.annotate('select', annotate_id, 'mark')[0]? && settings.annotation.position?
          $('body').append(annotation_html)
        else
          $(settings.annotation.container).append annotation_html

        $annotation = $(".annotate-annotation[data-annotatable-id=#{settings._annotatable_id}]:last")

        $.each $mark.data() || data.annotation, (key, value) -> 
          $attr_field = $(".annotate-fill-#{key}", $annotation[0])
          $attr_field.prepend(value)
        $annotatable_element.annotate 'position', $annotation
        true
      else
        $(".annotate-dialog[data-annotatable-id=#{settings._annotatable_id}] .errors").html('There was an error.')
        false

    # default mouseenter callback for marks
    _defaultOnTrigger: ($marks, $annotation) ->
      settings = $(this).data()
      $marks.add($annotation).addClass('selected')
      if $.inArray(settings.annotation.position, ['top', 'bottom']) > -1
        $annotation.show()
      $marks.add($annotation).mouseenter ->
        clearTimeout(settings._timer.id) if settings._timer? && settings._timer.annotation == $annotation.data('annotate-id')

    # default mouseleave callback for marks
    _defaultOffTrigger: ($marks, $annotation) ->
      settings = $(this).data()

      $marks.add($annotation).removeClass('selected')
      if $.inArray(settings.annotation.position, ['top', 'bottom']) > -1

        settings._timer =
          id: setTimeout (->
            $annotation.hide(250)
          ), 1000
          annotation: $annotation.data('annotate-id')

    _outsideSelection: -> console.warn "Selection is outside of the annotatable area"

    # bind hovers and actions
    _bindEvents: ($mark = null) ->
      $annotatable_element = $(this)
      settings = $annotatable_element.data()

      if $mark?
        annotate_id = $mark.data('annotate-id')
        $marks = $("mark[data-annotate-id=#{$mark.data('annotate-id')}]")
      else
        $marks = $('mark.annotated', $annotatable_element[0])
      
      $annotations = $annotatable_element.annotate('associated', $marks)

      # bind marks based on trigger type
      if $marks[0]? && settings.mark.trigger_type?
        switch settings.mark.trigger_type
          when 'hover'
            $marks.unbind('mouseenter mouseleave').hover((e) ->
              hover_target = e.currentTarget
              parents = $(this).parents('mark.annotated')
              $mark = if parents[parents.length-1]? then $(parents[parents.length-1]) else $(this)
              context_lengths = []
              hovered = [$mark[0]]
              annotate_id = undefined
              context_lengths.push $mark.data('annotate-context').length
              $mark.children('mark.annotated').each -> 
                if $(this).is(':hover')
                  context_lengths.push $(this).data('annotate-context').length
                  hovered.push this

              min_length = Math.min.apply Math, context_lengths

              $(hovered).each ->
                if $(this).data('annotate-context').length == min_length && typeof settings.mark.onTrigger is "function" && this == hover_target
                  top_mark_id = $(this).data('annotate-id')
                  $selected_marks = $annotatable_element.annotate('select', top_mark_id, 'mark')
                  params = [$selected_marks[0], $annotatable_element.annotate('associated', $selected_marks)[0]]
                  settings.mark.onTrigger.apply $annotatable_element[0], [$selected_marks, $annotatable_element.annotate('associated', $selected_marks)]
                  return false

            , (e) ->
              annotate_id = $(e.currentTarget).data('annotate-id')
              $marks = $annotatable_element.annotate('select', annotate_id, 'mark')
              if typeof settings.mark.offTrigger is "function"
                settings.mark.offTrigger.apply $annotatable_element[0], [$marks, $annotatable_element.annotate('associated', $marks)]
            )
      
      # bind annotations based on trigger type
      if $annotations[0]? && settings.annotation.trigger_type?
        switch settings.annotation.trigger_type
          when 'hover'
            $annotations.unbind('mouseenter mouseleave').hover((e) ->
              annotate_id = $(e.currentTarget).data('annotate-id')
              $marks = $annotatable_element.annotate('select', annotate_id, 'mark')

              if typeof settings.annotation.onTrigger is "function"
                settings.annotation.onTrigger.apply $annotatable_element[0], [$marks, $annotatable_element.annotate('associated', $marks)]
            , (e) ->
              annotate_id = $(e.currentTarget).data('annotate-id')
              $marks = $annotatable_element.annotate('select', annotate_id, 'mark')

              if typeof settings.annotation.offTrigger is "function"
                settings.annotation.offTrigger.apply $annotatable_element[0], [$marks, $annotatable_element.annotate('associated', $marks)]
            )

      # bind buttons to actions
      $('.annotate-remove').each -> $(this).unbind('click').click -> $annotatable_element.annotate('remove', $(this))
      $('.annotate-removeall').unbind('click').click -> $annotatable_element.annotate('removeall')
      $('.annotate-destroy').unbind('click').click -> $annotatable_element.annotate('destroy')
      $('.annotate-build').unbind('click').click -> $annotatable_element.annotate('build') if $.inArray settings.dialog.trigger, ['click', 'both'] > -1
      
      # bind .annotate('build') to text-select event, if applicable
      if $.inArray settings.dialog.trigger, ['hover', 'both'] > -1
        $annotatable_element.unbind('mouseup').mouseup (e) ->
          unless $(e.target).hasClass('annotate-dialog') || $(e.target).parents('.annotate-dialog').length > 0
            $annotatable_element.annotate('build')


    # remove annotation dialogs and placeholder marks
    cancel: ->
      $annotatable_element = $(this)
      settings = $annotatable_element.data()

      settings.dialog.beforeCancel.apply $annotatable_element[0], $(dialog) if typeof settings.dialog.beforeCancel is "function"

      annotatable_id = $(this).data('_annotatable_id')
      $(".annotate-dialog[data-annotatable-id=#{annotatable_id}]").remove()
      $('mark.temp', this).contents().unwrap()

      settings.dialog.afterCancel.apply $annotatable_element[0], $(dialog) if typeof settings.dialog.afterCancel is "function"

    # remove annotation and associated mark from DOM and call delete_annotations callback
    remove: ($elementOrId) ->
      settings = $(this).data()
      if settings.annotation.allow_remove
        if typeof($elementOrId) == 'object'
          annotate_id = getAnnotateId($elementOrId)
        else
          annotate_id = $elementOrId

        $marks = $("mark[data-annotate-id=#{annotate_id}]", this)
        if $marks.length > 0
          $marks.contents().unwrap()
          $(".annotate-annotation[data-annotate-id=#{annotate_id}]").remove()
          sendArticle($annotatable_element)
          settings.annotation.delete.apply(this, [annotate_id]) if typeof settings.annotation.delete is "function"

    # remove all annotations and associated marks from DOM and call delete_annotations callback
    removeall: ->
      settings = $(this).data()
      if settings.annotation.allow_remove
        annotate_ids = []
        $(this).annotate('cancel')
        $('mark.annotated', this).each ->
          annotate_id = $(this).data('annotate-id')
          annotate_ids.push annotate_id
          $(this).contents().unwrap()
          $(".annotate-annotation[data-annotate-id=#{annotate_id}]").remove()
        sendArticle $(this)
        settings.annotation.delete.apply(this, annotate_ids) if typeof settings.annotation.delete is "function"

    # select elements by data-annotate-id attribute
    select: (annotate_id, elementType = '*') -> $("#{elementType}[data-annotate-id=#{annotate_id}]")

    # unbind all relevant events and remove annotations from DOM
    destroy: ->
      $annotatable_element = $(this)
      annotatable_id = $(this).data('_annotatable_id')
      tag_name = $(this).data('annotation').tag_name
      
      $('mark.annotated', this).removeClass('selected').addClass('hidden').unbind()
      $("*[data-annotatable-id=#{annotatable_id}]").unbind('click')
      $("#{tag_name}[data-annotatable-id=#{annotatable_id}]").remove()
      $annotatable_element.annotate('associated', $('mark.annotated', this)).remove()
      $annotatable_element.unbind('mouseup').removeData()

    # select other elements by the same data-annotate-id attribute, with different tagNames
    associated: ($elements) ->
      ids = []
      annotations = []
      marks = []

      $elements.each ->
        annotate_id = getAnnotateId $(this)
        if $(this).prop("tagName") == 'MARK'
          if $.inArray ids, annotate_id == -1
            ids.push(annotate_id)
            annotations.push $("*[data-annotate-id=#{annotate_id}]").not('mark')[0]
        else
          $("mark[data-annotate-id=#{annotate_id}]", this).each -> marks.push(this)

      returned_elements = marks.concat(annotations).filter (val) -> val?
      $(returned_elements)

    # position a popup according to positioning options
    position: ($el, params = {}) ->
      settings = $(this).data()
      popup_type = if $el.hasClass('annotate-annotation') then settings.annotation else settings.dialog

      options = $.extend(
        offset_amount: popup_type.offset_amount
        direction: popup_type.position
        annotate_id: $el.data('annotate-id')
      , params)

      display_type = if $el.hasClass('annotate-annotation') && $.inArray(options.direction, ['top', 'bottom']) > -1 then 'none' else 'block'
      popup_placement = if options.direction == 'bottom' then 'last' else 'first'

      scope = "mark[data-annotate-id=#{options.annotate_id}]:#{popup_placement}"
      mark = if options.annotate_id? then $("mark[data-annotate-id=#{options.annotate_id}]:#{popup_placement}", this)[0] else $("mark.temp:#{popup_placement}", this)[0]
        
      if mark?
        mark_left = inlineOffset(mark).left
        mark_top = inlineOffset(mark).top

        switch options.direction
          when 'left'
            $el.css
              left: options.offset_amount 
              top: mark_top
              display: display_type
          when 'right'
            $el.css
              right: options.offset_amount
              top: mark_top
              display: display_type
          when 'top'
            $el.css
              left: $(mark).width()/2 + mark_left
              top: mark_top - options.offset_amount - $el.height()
              display: display_type
          when 'bottom'
            $el.css
              left: $(mark).width()/2 + mark_left
              top: $(mark).height() + mark_top + options.offset_amount
              display: display_type
      else
        $el.css { position: 'static' }

    # render annotation dialog, bind form, render annotation and update article if successful
    build: ->
      $annotatable_element = $(this)
      settings = $annotatable_element.data()

      # get selected text
      
      sel = rangy.getSelection()
      if sel.rangeCount > 0 && (selected_text = sel.toString()) != ''
        range = sel.getRangeAt(0)
        parentElement = range.commonAncestorContainer
        parentElement = parentElement.parentNode if parentElement.nodeType is 3 && parentElement.parentNode?

        # check if selected text is completely within annotatable area
        if isDescendant($annotatable_element[0], parentElement) || parentElement is $annotatable_element[0]
          
          # remove existing annotation dialogs
          $(this).annotate('cancel')
          
          # mark selected text and deselect
          settings.tempMarker.applyToSelection()
          sel.removeAllRanges()

          # replace tempmark with mark.temp to avoid issues with overlapping marks generated by rangy
          $('tempmark').wrap('<mark class="temp"></mark>')
          $('mark.temp tempmark').contents().unwrap()

          # render annotation dialog and callbacks
          settings.dialog.beforeCreate.apply($annotatable_element[0]) if typeof settings.dialog.beforeCreate is "function"
          settings.dialog.create.apply($annotatable_element[0]) if typeof settings.dialog.create is "function"

          dialog = $(".annotate-dialog[data-annotatable-id=#{settings._annotatable_id}]")[0]
          $('.annotate-cancel', dialog).click -> $annotatable_element.annotate('cancel')
          settings.dialog.afterCreate.apply $annotatable_element[0], $(dialog) if typeof settings.dialog.afterCreate is "function"
          $(':input:first', dialog).focus()

          # bind annotation dialog form
          $('.annotate-dialog form').submit (e) ->
            e.preventDefault()
            extras =
              annotate_id: generateAnnotateId()
              annotate_context: selected_text
              annotate_time: getCurrentTime()
            delete extras.annotate_time unless settings.annotation.include_time

            form_data = serializeObject(this, extras)
            response = settings.annotation.save(form_data)

            html_attr = {}
            $.each toCamel(response.annotation), (name, value) -> html_attr["data-#{name.replace('_', '-')}"] = value
            $marks = $('mark.temp', $annotatable_element[0])
            $marks.attr(html_attr)

            settings.annotation.beforeRender.apply($annotatable_element, [response]) if typeof settings.annotation.beforeRender is "function"
            if settings.annotation.render.apply($annotatable_element, [response]) && typeof settings.annotation.render is "function"
              $annotation = $annotatable_element.annotate 'associated', $marks
              settings.annotation.afterRender.apply($annotatable_element, [$annotation]) if typeof settings.annotation.afterRender is "function"
              $marks.addClass('annotated').removeClass('temp')

              $annotatable_element.annotate('cancel')
              sendArticle($annotatable_element)
              $annotatable_element.annotate('_bindEvents', $marks)

        else settings.dialog.outsideSelection()
      else $annotatable_element.annotate('cancel')

  $.fn.annotate = (methodOrOptions) ->
    try
      # if a method is called, apply; othwerwise, instantiate jQuery.annotate on the element
      if methods[methodOrOptions]
        if $(this).data()?.ignore_warnings?
          result = methods[methodOrOptions].apply this, Array::slice.call(arguments, 1)
          return result if $.inArray(methodOrOptions, ['associated', 'select']) > -1
        else
          $.error "jQuery.annotate has not been instantiated on this element"
      else if typeof methodOrOptions is "object" or not methodOrOptions
        methods.init.apply this, arguments
      else
        $.error "Method '#{methodOrOptions}' does not exist on jQuery.annotate"
      $(this)
    catch e
      console.log e.stack
) jQuery