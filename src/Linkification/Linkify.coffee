Linkify =
  init: ->
    return if g.VIEW is 'catalog'

    @regString = if Conf['Allow False Positives']
      ///(
        \b(
          [a-z]+://
          |
          [a-z]{3,}\.[-a-z0-9]+\.[a-z]
          |
          [-a-z0-9]+\.[a-z]
          |
          [0-9]+\.[0-9]+\.[0-9]+\.[0-9]
          |
          [a-z]{3,}:[a-z0-9?]
          |
          [\S]+@[a-z0-9.-]+\.[a-z0-9]
        )
        [^\s'"]+
      )///gi
    else
      /(((magnet|mailto)\:|(www\.)|(news|(ht|f)tp(s?))\:\/\/){1}\S+)/gi

    if Conf['Comment Expansion']
      ExpandComment.callbacks.push @node

    Post::callbacks.push
      name: 'Linkify'
      cb:   @node

  node: ->
    if @isClone and Conf['Embedding']
      for embedder in $$ '.embedder', @nodes.comment
        $.on embedder, "click", Linkify.cb.toggle
      return

    snapshot = $.X './/text()', @nodes.comment
    i      = -1
    len    = snapshot.snapshotLength
    links  = []

    while ++i < len
      node = snapshot.snapshotItem i
      data = node.data

      if match = data.match Linkify.regString
        links.pushArrays Linkify.gatherLinks match, node

    if Conf['Linkify']
      for range in links
        @nodes.links.push Linkify.makeLink range

    return unless Conf['Embedding'] or Conf['Link Title']
    
    for range in @nodes.links or links
      if link = Linkify.services range
        if Conf['Embedding']
          Linkify.embed link
        if Conf['Link Title']
          Linkify.title link

    return

  gatherLinks: (match, node) ->
    links = []
    i = 0
    len = match.length
    data  = node.data

    while (link = match[i++]) and i > len
      range = document.createRange();
      range.setStart node, len2 = data.indexOf link
      range.setEnd   node, len2 + link.length
      links.push range

    range = document.createRange()
    range.setStart node, len = data.indexOf link

    if (data.length - (len += link.length)) > 0
      range.setEnd node, len
      links.push range
      return links

    while (next = node.nextSibling) and next.nodeName.toLowerCase() isnt 'br'
      node = next
      data = node.data
      if result = /[\s'"]/.exec data
        range.setEnd node, result.index

    if range.collapsed
      if node.nodeName.toLowerCase() is 'wbr'
        node = node.previousSibling
      range.setEnd node, node.length

    links.push range
    return links

  makeLink: (range) ->
    link = range.toString()
    link =
      if link.contains ':'
        link
      else (
        if link.contains '@'
          'mailto:'
        else
          'http://'
      ) + link

    a = $.el 'a',
      className: 'linkify'
      rel:       'nofollow noreferrer'
      target:    '_blank'
      href:      link

    range.surroundContents a
    return a

  services: (link) ->
    href = if Conf['Linkify']
      link.href
    else
      link.toString()

    for key, type of Linkify.types
      continue unless match = type.regExp.exec href
      link = Linkify.makeLink link unless Conf['Linkify']
      return [key, match[1], match[2], link]

    return

  embed: (data) ->
    [key, uid, options, link] = data
    embed = $.el 'a',
      name:        uid
      option:      options
      className:   'embedder'
      href:        'javascript:;'
      textContent: '(embed)'

    embed.dataset.service     = key
    embed.dataset.originalurl = link.href

    $.addClass link, "#{embed.dataset.service}"

    $.on embed, 'click', Linkify.cb.toggle
    $.after link, [$.tn(' '), embed]

  cb:
    toggle: ->
      # We setup the link to be replaced by the embedded video
      embed = @previousElementSibling
   
      # Unembed.
      el = unless @className.contains "embedded"
        Linkify.cb.embed @
      else
        Linkify.cb.unembed @
   
      $.replace embed, el
      $.toggleClass @, 'embedded'
   
    embed: (a) ->
      # We create an element to embed
      el = (type = Linkify.types[a.dataset.service]).el.call a
   
      # Set style values.
      el.style.cssText = if style = type.style
        style
      else
        "border: 0; width: 640px; height: 390px"
   
      a.textContent = '(unembed)'

      return el
   
    unembed: (a) ->
      # Recreate the original link.
      el = $.el 'a',
        rel:         'nofollow noreferrer'
        target:      'blank'
        className:   'linkify'
        href:        url = a.dataset.originalurl
        textContent: a.dataset.title or url
   
      a.textContent = '(embed)'
      $.addClass el, "#{a.dataset.service}"
   
      return el

    title: (data) ->
      [key, uid, options, link] = data
      service = Linkify.types[key].title
      link.textContent = switch @status
        when 200, 304
          text = "#{service.text.call @}"
          if Conf['Embedding']
             link.nextElementSibling.dataset.title = text
          text
        when 404
          "[#{key}] Not Found"
        when 403
          "[#{key}] Forbidden or Private"
        else
          "[#{key}] #{@status}'d"

  title: (data) ->
    [key, uid, options, link] = data
    titles = {}
    service = Linkify.types[key].title
    title = ""

    $.get 'CachedTitles', {}, (item) ->
      titles = item['CachedTitles']
      if title = titles[uid]
        link.textContent = title[0]
        if Conf['Embedding']
           link.nextElementSibling.dataset.title = title[0]
        return
      else
        try
          $.cache service.api(uid), ->
            title = Linkify.cb.title.apply @, [data]
        catch err
          link.innerHTML = "[#{key}] <span class=warning>Title Link Blocked</span> (are you using NoScript?)</a>"
          return
        if title
          titles[uid]  = [title, Date.now()]
          $.set 'CachedTitles', titles

  types:
    YouTube:
      regExp:  /.*(?:youtu.be\/|youtube.*v=|youtube.*\/embed\/|youtube.*\/v\/|youtube.*videos\/)([^#\&\?]*)\??(t\=.*)?/
      el: ->
        $.el 'iframe',
          src: "//www.youtube.com/embed/#{@name}#{if @option then '#' + @option else ''}?wmode=opaque"
      title:
        api: (uid) -> "https://gdata.youtube.com/feeds/api/videos/#{uid}?alt=json&fields=title/text(),yt:noembed,app:control/yt:state/@reasonCode"
        text: -> JSON.parse(@responseText).entry.title.$t

    Vocaroo:
      regExp:  /.*(?:vocaroo.com\/)([^#\&\?]*).*/
      style: 'border: 0; width: 150px; height: 45px;'
      el: ->
        $.el 'object',
          innerHTML:  "<embed src='http://vocaroo.com/player.swf?playMediaID=#{@name.replace /^i\//, ''}&autoplay=0' wmode='opaque' width='150' height='45' pluginspage='http://get.adobe.com/flashplayer/' type='application/x-shockwave-flash'></embed>"

    Vimeo:
      regExp:  /.*(?:vimeo.com\/)([^#\&\?]*).*/
      el: ->
        $.el 'iframe',
          src: "//player.vimeo.com/video/#{@name}?wmode=opaque"
      title:
        api: (uid) -> "https://vimeo.com/api/oembed.json?url=http://vimeo.com/#{uid}"
        text: -> JSON.parse(@responseText).title

    LiveLeak:
      regExp:  /.*(?:liveleak.com\/view.+i=)([0-9a-z_]+)/
      el: ->
        $.el 'object',
          innerHTML:  "<embed src='http://www.liveleak.com/e/#{@name}?autostart=true' wmode='opaque' width='640' height='390' pluginspage='http://get.adobe.com/flashplayer/' type='application/x-shockwave-flash'></embed>"

    audio:
      regExp:  /(.*\.(mp3|ogg|wav))$/
      el: ->
        $.el 'audio',
          controls:    'controls'
          preload:     'auto'
          src:         @name

    image:
      regExp:  /(http|www).*\.(gif|png|jpg|jpeg|bmp)$/
      style: 'border: 0; width: auto; height: auto;'
      el: ->
        $.el 'div',
          innerHTML: "<a target=_blank href='#{@dataset.originalurl}'><img src='#{@dataset.originalurl}'></a>"

    SoundCloud:
      regExp: /.*(?:soundcloud.com\/|snd.sc\/)([^#\&\?]*).*/
      style: 'height: auto; width: 500px; display: inline-block;'
      el: ->
        div = $.el 'div',
          className: "soundcloud"
          name: "soundcloud"
        $.ajax(
          "//soundcloud.com/oembed?show_artwork=false&&maxwidth=500px&show_comments=false&format=json&url=https://www.soundcloud.com/#{@name}"
          div: div
          onloadend: ->
            @div.innerHTML = JSON.parse(@responseText).html
          false)
        div
      title:
        api: (uid) -> "//soundcloud.com/oembed?show_artwork=false&&maxwidth=500px&show_comments=false&format=json&url=https://www.soundcloud.com/#{uid}"
        text: -> JSON.parse(@responseText).title

    pastebin:
      regExp:  /.*(?:pastebin.com\/(?!u\/))([^#\&\?]*).*/
      el: ->
        div = $.el 'iframe',
          src: "http://pastebin.com/embed_iframe.php?i=#{@name}"

    gist:
      regExp: /.*(?:gist.github.com.*\/)([^\/][^\/]*)$/
      el: ->
        div = $.el 'iframe',
          # Github doesn't allow embedding straight from the site, so we use an external site to bypass that.
          src: "http://www.purplegene.com/script?url=https://gist.github.com/#{@name}.js"
      title:
        api: (uid) -> "https://api.github.com/gists/#{uid}"
        text: ->
          response = JSON.parse(@responseText).files
          return file for file of response when response.hasOwnProperty file

    InstallGentoo:
      regExp:  /.*(?:paste.installgentoo.com\/view\/)([0-9a-z_]+)/
      el: ->
        $.el 'iframe',
          src: "http://paste.installgentoo.com/view/embed/#{@name}"