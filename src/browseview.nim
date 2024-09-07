import std/[algorithm, strformat, sequtils, strutils, random, math]
import downit
import niprefs
import imstyle
import nimgl/imgui

import utils, icons

proc sortFilterFeed(app: var App) = 
  if app.browseView.feed.len <= 0:
    app.browseView.falseFeed.setLen(0)
    return

  app.browseView.falseFeed = toSeq app.browseView.feed.low..app.browseView.feed.high

  # Filter feed
  if app.browseView.authorFilter.len > 0:
    app.browseView.falseFeed.keepItIf(
      app.browseView.feed[it].author == app.browseView.authorFilter)

  if app.browseView.tagFilters.len > 0:
    app.browseView.falseFeed.keepItIf(
      app.browseView.tagFilters.all(proc (x: Tag): bool = x in app.browseView.feed[it].tags))

  if app.browseView.colorFilters.len > 0:
    app.browseView.falseFeed.keepItIf(
      app.browseView.tagFilters.all(proc (x: Color): bool = x in app.browseView.feed[it].colors))

  if app.browseView.starredFilter:
    app.browseView.falseFeed.keepItIf(app.browseView.feed[it].name in app.prefs[starred])

  # Sort feed
  case app.currentSort
  of AlphAsc:
    app.browseView.falseFeed.sort(order = SortOrder.Ascending) do (x, y: int) -> int:
      cmp(x.name, y.name)
  of AlphDesc:
    app.browseView.falseFeed.sort(order = SortOrder.Descending) do (x, y: int) -> int:
      cmp(x.name, y.name)
  of Newest:
    app.browseView.falseFeed.sort(order = SortOrder.Ascending) do (x, y: int) -> int:
      cmp(x.name, y.name)
  of Oldest:
    result = result.sortedByIt(it["date"].getDateTime())

proc drawBrowseListHeader(app: var App) = 
  igInputTextWithHint("##search", "Search...", cstring app.browseBuffer, 64); igSameLine()

  if igButton(FA_Sort):
    igOpenPopup("sort")
  igSameLine()

  app.drawFilters(app.filters, app.authorFilter)

  if igBeginPopup("sort"):
    for e, ele in [FA_SortAlphaAsc, FA_SortAlphaDesc, "Newest", "Oldest"]:
      if igSelectable(cstring ele, e == app.currentSort):
        app.currentSort = e

    igEndPopup()

proc drawBrowseList(app: var App) = 
  let style = igGetStyle()
  let feed = app.getFeed()

  for e, theme in feed:
    if app.browseBuffer.passFilter(theme["name"].getString()):
      let starred = theme["name"] in app.prefs["starred"]
      let starText = if starred: FA_Star else: FA_StarO
      let selected = theme["name"] == app.browseCurrentTheme["name"]
      if igSelectable(cstring "##" & $e, selected, size = igVec2(0, igGetFrameHeight() + app.strongFont.fontSize + (style.framePadding.y * 2)), flags = ImGuiSelectableFlags.AllowItemOverlap):
        app.browseCurrentTheme = feed[e]

      igSameLine(); igBeginGroup()
      app.strongFont.igPushFont()
      igText(cstring theme["name"].getString())
      igPopFont()
      
      igTextWithEllipsis(
        if theme["description"].getString().len > 0: theme["description"].getString() else: "No description.", 
        maxWidth = igGetContentRegionAvail().x - (style.itemSpacing.x + igCalcFrameSize(starText).x)
      )
      igSameLine(); igCenterCursorX(igCalcFrameSize(starText).x, align = 1)
      
      if igButton(cstring starText & "##" & $e):
        if starred:
          app.prefs["starred"].delete app.prefs["starred"].find(theme["name"])
        else:
          app.prefs["starred"].add theme["name"]

      igEndGroup()

proc getForkName(app: App, name: string): string = 
  let forkName = "Fork of " & name
  let forks = app.prefs["themes"].getTables().filterIt(it["name"].getString().startsWith(forkName))
  if forks.len == 0:
    result = forkName
  else:
    result = &"{forkName} #{forks.len}"

proc drawForkThemeModal(app: var App, theme: TomlTableRef) = 
  igSetNextWindowPos(igGetMainViewport().getCenter(), Always, igVec2(0.5f, 0.5f))
  if igBeginPopupModal("Fork Theme", flags = makeFlags(AlwaysAutoResize)):
    igText("Are you sure you want to fork it?")

    if igButton("Yes"):
      app.prefs["themes"].add toTTable({name: app.getForkName(theme["name"].getString()), style: theme["style"], forkedFrom: theme["name"]})
      app.currentView = 0 # Switch to edit view
      app.switchTheme(app.prefs["themes"].getTables().high)

    igSameLine()
    if igButton("Cancel"): igCloseCurrentPopup()

    igEndPopup()

proc drawbrowseView(app: var App) = 
  let style = igGetStyle()
  let avail = igGetContentRegionAvail()

  let prevWindowPadding = igGetStyle().windowPadding
  igPushStyleVar(WindowPadding, igVec2(150, 20))
  if igBeginChild("##browseView", igVec2(app.browseSplitterSize.b, avail.y), flags = makeFlags(AlwaysUseWindowPadding)):
    let theme = app.browseCurrentTheme
    let themeStyle = theme["style"].styleFromToml()

    app.strongFont.igPushFont()
    igText(cstring theme["name"].getString())
    igPopFont()
  
    igSameLine()

    igText("By ")
    if igClickableText(theme["author"].getString(), sameLineAfter = false):
      app.authorFilter = theme["author"].getString()

    if "forkedFrom" in theme:
      igSameLine()

      igText("forked from ")
      if igClickableText(theme["forkedFrom"].getString(), sameLineAfter = false):
        # Since there can be no themes with the same name index 0 is enough
        app.browseCurrentTheme = app.feed.filterIt(it["name"] == theme["forkedFrom"])[0]

    igTextWrapped(cstring(if theme["description"].getString().len > 0: theme["description"].getString() else: "No description provided."))

    if igButton("Get it"):
      app.copied = false
      igOpenPopup("###exportTheme")

    igSameLine()
    if igButton("Fork it"):
      igOpenPopup("Fork Theme")
    
    if theme["tags"].len > 0:
      igSameLine()
  
      igPushStyleVar(FrameRounding, 0f)
      igPushStyleColor(ImGuiCol.Button, igGetColorU32(ImGuiCol.Tab))
      igPushStyleColor(ImGuiCol.ButtonHovered, igGetColorU32(ImGuiCol.TabHovered))
      igPushStyleColor(ImGuiCol.ButtonActive, igGetColorU32(ImGuiCol.TabActive))

      let themesWidth = 
        theme["tags"].mapIt(igCalcTextSize(cstring it.getString().capitalizeAscii()).x).sum() + 
        (style.framePadding.x * float32(theme["tags"].len * 2)) + 
        (style.itemSpacing.x * float32 theme["tags"].len-1)

      igCenterCursorX(themesWidth, align = 1)
      for e, tag in theme["tags"].getArray():
        if igButton(cstring tag.getString().capitalizeAscii()) and tag.getString() notin app.filters:
          app.filters.add tag.getString()
        
        if e < theme["tags"].len-1:
          igSameLine()

      igPopStyleColor(3)
      igPopStyleVar()

    if igBeginChild("##preview"):
      igSetNextWindowPos(igGetWindowPos())
      igSetNextWindowSize(igGetWindowSize())

      app.drawStylePreview(theme["name"].getString(), themeSTyle)
    
    igEndChild()

    igPushStyleVar(WindowPadding, prevWindowPadding)
    app.drawExportThemeModal(themeStyle, theme["name"].getString(), theme["author"].getString())
    app.drawForkThemeModal(theme)
    igPopStyleVar()


  igEndChild()
  igPopStyleVar()

proc drawBrowseView*(app: var App) = 
  app.downloader.update()

  if not app.downloader.exists("feed"):
    app.downloader.download("https://github.com/Patitotective/ImThemes/blob/main/themes.toml?raw=true", "themes.toml", "feed")
  elif app.downloader.succeed("feed") and app.feed.len == 0:
    app.feed = Toml.loadFile(app.downloader.getPath("feed").get(), TomlValueRef)["themes"].getTables()

    randomize()
    app.browseCurrentTheme = app.feed[rand(app.feed.high)]

  const splitterWidth = 8
  let avail = igGetContentRegionAvail() - igVec2(splitterWidth, 0)

  # Keep splitter proportions on resize
  # And hide the editing zone when not editing
  if app.prevAvail != igVec2(0, 0) and app.prevAvail != avail:
    app.browseSplitterSize = ((app.browseSplitterSize.a / app.prevAvail.x) * avail.x, (app.browseSplitterSize.b / app.prevAvail.x) * avail.x)

  app.prevAvail = avail

  # First time
  if app.browseSplitterSize.a == 0:
    app.browseSplitterSize = (avail.x * 0.2f, avail.x * 0.8f)

  if app.downloader.succeed("feed"):
    igSplitter(true, splitterWidth, app.browseSplitterSize.a.addr, app.browseSplitterSize.b.addr, 200, 800, avail.y)
    # List
    if igBeginChild("##browseList", igVec2(app.browseSplitterSize.a, avail.y), flags = makeFlags(AlwaysUseWindowPadding)):
      app.drawBrowseListHeader()
      igSeparator()
      app.drawBrowseList()

    igEndChild(); igSameLine(spacing = splitterWidth)
    app.drawbrowseView()

  elif app.downloader.running("feed"):
    igCenterCursor(ImVec2(x: 15 * 2, y: (15 + igGetStyle().framePadding.y) * 2))
    igSpinner("##spinner", 15, 6, igGetColorU32(ButtonHovered))

  elif (let errorMsg = app.downloader.getErrorMsg("feed"); errorMsg.isSome):
    let text = "Error fetching browse feed: \n" & errorMsg.get().splitLines()[0] & "\n"

    igCenterCursorX(igCalcTextSize(cstring text).x)
    igCenterCursorY(igGetFrameHeight() + igCalcTextSize(cstring text).y + igGetStyle().itemSpacing.y)
    igBeginGroup()
    igTextWrapped(cstring text)

    if igIsItemHovered():
      igSetTooltip("Right click to copy full error")

    if igBeginPopupContextItem("menu"):
      if igMenuItem("Copy"):
        igsetClipboardText(cstring errorMsg.get())
      igEndPopup()

    if igButton("Retry") and not app.downloader.running("feed"):
      app.downloader.downloadAgain("feed")
    igEndGroup()
